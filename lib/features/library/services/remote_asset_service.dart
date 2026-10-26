import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
// ignore: implementation_imports
import 'package:app_ai_client/src/default_http_client.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/models/connectivity_status.dart';
import '../models/asset_source_config.dart';
import '../models/cached_asset.dart';
import '../models/remote_asset_file.dart';
import 'browser_asset_cache_stub.dart'
    if (dart.library.js_interop) 'browser_asset_cache_web.dart';

/// Public, allowlisted app-service resources. Authentication never participates
/// in this transport; caches are scoped by service origin, not user identity.
class RemoteAssetService {
  RemoteAssetService({
    http.Client? client,
    Uri? Function()? serviceOrigin,
    this.requestTimeout = const Duration(seconds: 20),
    this.browser = kIsWeb,
    this.cacheDirectory,
  }) : _client = client ?? createDefaultAiHttpClient(),
       _origin = serviceOrigin ?? (() => kIsWeb ? Uri.base : null);
  final http.Client _client;
  final Uri? Function() _origin;
  final bool browser;
  final Directory? cacheDirectory;
  final Duration requestTimeout;
  bool get usesPublishedLibrary => _origin() != null;
  bool get accessAllowed => true;
  Map<String, dynamic> _files = {};
  void invalidatePublication() {
    _files = {};
    _publicationOrigin = null;
  }

  String? _publicationOrigin;
  final _pending = <String, Future<Uint8List?>>{};
  final _downloads = <String, Future<String>>{};
  final _active = <Completer<void>>{};
  bool _closed = false;
  void dispose() {
    if (_closed) return;
    _closed = true;
    for (final abort in _active) {
      if (!abort.isCompleted) abort.complete();
    }
    _client.close();
  }

  // Public caches survive account changes.
  Uri? get _base {
    final origin = _closed ? null : _origin();
    return origin?.resolve(
      browser
          ? '/api/v1/apps/board_game_agent/library'
          : '/v1/apps/board_game_agent/library',
    );
  }

  static bool validPath(String path) =>
      path.length <= 1024 &&
      RegExp(r'^assets/[A-Za-z0-9_./-]+$').hasMatch(path) &&
      !path.split('/').any((p) => p.isEmpty || p.startsWith('.')) &&
      !path.toLowerCase().contains('docs/others');
  String _cacheKey(String path) {
    final extension =
        RegExp(r'\.[A-Za-z0-9]{1,8}$').firstMatch(path)?.group(0) ?? '.bin';
    return 'board-public-v1/${sha256.convert(utf8.encode(_base?.origin ?? 'unconfigured'))}/'
        '${sha256.convert(utf8.encode(path))}$extension';
  }

  Uri? resourceUri(String path) => validPath(path) && _base != null
      ? Uri.parse('${_base!}/files/$path').replace(
          queryParameters: {
            if (_files[path] != null) 'v': _files[path]['sha256'] as String,
          },
        )
      : null;

  Future<http.Response> _request(
    Uri uri, {
    String method = 'GET',
    Completer<void>? abort,
  }) async {
    if (_closed) throw StateError('Resource service closed');
    final cancellation = Completer<void>();
    _active.add(cancellation);
    abort?.future.then((_) {
      if (!cancellation.isCompleted) cancellation.complete();
    });
    final request = http.AbortableRequest(
      method,
      uri,
      abortTrigger: cancellation.future,
    )..followRedirects = false;
    try {
      return await (() async {
        final stream = await _client.send(request);
        final body = BytesBuilder(copy: false);
        await for (final bytes in stream.stream) {
          if (body.length + bytes.length > 64 * 1024 * 1024) {
            throw StateError('资料过大');
          }
          body.add(bytes);
        }
        return http.Response.bytes(
          body.takeBytes(),
          stream.statusCode,
          headers: stream.headers,
        );
      })().timeout(requestTimeout);
    } finally {
      if (!cancellation.isCompleted) cancellation.complete();
      _active.remove(cancellation);
    }
  }

  Future<bool> refreshPublishedLibrary({
    bool complete = false,
    String? checkedCatalog,
  }) async {
    final base = _base;
    if (base == null) throw StateError('请配置应用服务地址');
    final response = await _request(base);
    if (response.statusCode != 200 ||
        response.bodyBytes.length > 4 * 1024 * 1024) {
      throw StateError('公开资料目录暂不可用');
    }
    final index =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final files = index['files'] as Map<String, dynamic>;
    if (index['version'] != 1 ||
        files.length > 10000 ||
        !files.containsKey('assets/catalog.json') ||
        files.entries.any(
          (e) =>
              !validPath(e.key) ||
              e.value is! Map ||
              !RegExp(r'^[a-f0-9]{64}$').hasMatch('${e.value['sha256']}') ||
              e.value['size'] is! int,
        )) {
      throw const FormatException('Invalid publication');
    }
    if (_base != base) throw StateError('资料入口已变化');
    final changed =
        _publicationOrigin != base.origin ||
        jsonEncode(files) != jsonEncode(_files);
    _files = files;
    _publicationOrigin = base.origin;
    return changed;
  }

  Future<Uint8List?> _fetch(String path) async {
    if (!validPath(path)) return null;
    final uri = resourceUri(path);
    if (uri == null) return null;
    final key = uri.toString();
    return _pending.putIfAbsent(key, () async {
      try {
        if (_publicationOrigin != uri.origin || !_files.containsKey(path)) {
          await refreshPublishedLibrary();
        }
        final record = _files[path] as Map?;
        if (record == null) return null;
        final response = await _request(uri);
        if (resourceUri(path)?.origin != uri.origin) return null;
        if (response.statusCode != 200 ||
            response.bodyBytes.length != record['size'] ||
            sha256.convert(response.bodyBytes).toString() != record['sha256']) {
          throw StateError('公开资料下载未完成，请重试');
        }
        return response.bodyBytes;
      } finally {
        _pending.remove(key);
      }
    });
  }

  Future<File> _fileFor(String path) async {
    final key = _cacheKey(path);
    final directory = cacheDirectory ?? await getApplicationSupportDirectory();
    return File('${directory.path}/$key');
  }

  Future<Uint8List?> cachedBytesFor(String remotePath) async {
    if (!validPath(remotePath)) return null;
    if (browser) return readBrowserAsset(_cacheKey(remotePath));
    final file = await _fileFor(remotePath);
    return await file.exists() ? file.readAsBytes() : null;
  }

  Future<File?> cachedFileFor(String remotePath) async {
    if (browser || !validPath(remotePath)) return null;
    final file = await _fileFor(remotePath);
    return await file.exists() ? file : null;
  }

  Future<String> _downloadNative(String path, Uri uri, File target) async {
    if (_publicationOrigin != uri.origin || !_files.containsKey(path)) {
      await refreshPublishedLibrary();
    }
    final record = _files[path] as Map?;
    if (record == null) throw StateError('资料未发布');
    final staged = File('${target.path}.download');
    await target.parent.create(recursive: true);
    final abort = Completer<void>();
    _active.add(abort);
    final timer = Timer(const Duration(minutes: 5), () {
      if (!abort.isCompleted) abort.complete();
    });
    IOSink? sink;
    try {
      final request = http.AbortableRequest(
        'GET',
        uri,
        abortTrigger: abort.future,
      )..followRedirects = false;
      final response = await _client.send(request);
      if (response.statusCode != 200) throw StateError('公开资料下载未完成');
      sink = staged.openWrite();
      var size = 0;
      await for (final chunk in response.stream) {
        size += chunk.length;
        if (size > record['size'] ||
            size > 512 * 1024 * 1024 ||
            abort.isCompleted) {
          throw StateError('公开资料下载未完成');
        }
        sink.add(chunk);
        await sink.flush();
      }
      await sink.close();
      sink = null;
      final digest = await sha256.bind(staged.openRead()).first;
      if (size != record['size'] ||
          digest.toString() != record['sha256'] ||
          abort.isCompleted ||
          resourceUri(path)?.origin != uri.origin) {
        throw StateError('资料完整性校验未通过，请重试');
      }
      await staged.rename(target.path);
      return digest.toString();
    } finally {
      timer.cancel();
      if (!abort.isCompleted) abort.complete();
      _active.remove(abort);
      await sink?.close();
      if (await staged.exists()) await staged.delete();
    }
  }

  Future<CachedAsset?> ensureCached({
    required List<AssetSourceConfig> sources,
    required String remotePath,
    bool forceRefresh = false,
    bool allowCachedFallback = true,
  }) async {
    if (!validPath(remotePath)) return null;
    final uri = resourceUri(remotePath);
    if (browser) {
      if (uri == null) return null;
      final response = await _request(uri, method: 'HEAD');
      if (response.statusCode != 200 ||
          resourceUri(remotePath)?.origin != uri.origin) {
        return null;
      }
      return CachedAsset(
        remotePath: remotePath,
        localPath: uri.toString(),
        exists: true,
        fromRemote: true,
        sourceId: 'app_service',
      );
    }
    final file = await _fileFor(remotePath);
    var available = await file.exists();
    var downloaded = false;
    var stale = forceRefresh;
    if (available && _files[remotePath] != null && !stale) {
      stale =
          (await sha256.bind(file.openRead()).first).toString() !=
          _files[remotePath]['sha256'];
    }
    if (!available || stale) {
      try {
        if (uri == null) return null;
        final digest = await _downloads.putIfAbsent(
          file.path,
          () => _downloadNative(remotePath, uri, file).whenComplete(() {
            _downloads.remove(file.path);
          }),
        );
        if (_files[remotePath]?['sha256'] != digest) {
          throw StateError('资料版本已变化，请重试');
        }
        available = downloaded = true;
      } catch (_) {
        if (!allowCachedFallback) rethrow;
        if (!available) return null;
      }
    }
    if (!available || resourceUri(remotePath)?.origin != uri?.origin) {
      return null;
    }
    return CachedAsset(
      remotePath: remotePath,
      localPath: file.path,
      exists: true,
      fromRemote: downloaded,
      sourceId: 'app_service',
    );
  }

  Future<List<int>?> fetchRemoteBytes({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) => _fetch(remotePath);
  Future<String?> fetchRemoteText({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) async {
    final bytes = await _fetch(remotePath);
    return bytes == null ? null : utf8.decode(bytes);
  }

  Future<String?> loadCachedText({required String remotePath}) async {
    final bytes = await cachedBytesFor(remotePath);
    return bytes == null ? null : utf8.decode(bytes);
  }

  Future<List<int>?> loadBytes({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) async {
    if (browser) {
      try {
        final bytes = await _fetch(remotePath);
        if (bytes != null && bytes.length <= 8 * 1024 * 1024) {
          await writeBrowserAsset(_cacheKey(remotePath), bytes);
        }
        return bytes;
      } catch (_) {
        return cachedBytesFor(remotePath);
      }
    }
    final cached = await ensureCached(
      sources: sources,
      remotePath: remotePath,
      allowCachedFallback: false,
    );
    if (cached == null) return null;
    final file = File(cached.localPath);
    if (await file.length() > 64 * 1024 * 1024) {
      throw StateError('资料超过单次内存读取上限');
    }
    return file.readAsBytes();
  }

  Future<String?> loadText({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) async {
    final bytes = await loadBytes(sources: sources, remotePath: remotePath);
    return bytes == null ? null : utf8.decode(bytes);
  }

  Future<String?> loadTextFromAny({
    required List<AssetSourceConfig> sources,
    required List<String> remotePaths,
  }) async {
    for (final path in remotePaths) {
      final text = await loadText(sources: sources, remotePath: path);
      if (text != null && text.trim().isNotEmpty) return text;
    }
    return null;
  }

  Future<bool> hasRemoteChanged({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) async {
    final cached = await cachedBytesFor(remotePath);
    await refreshPublishedLibrary();
    return cached != null &&
        _files[remotePath] != null &&
        sha256.convert(cached).toString() != _files[remotePath]['sha256'];
  }

  Future<ConnectivityStatus> checkAccess(
    AssetSourceConfig source, {
    Completer<void>? abort,
    void Function(String)? onCatalog,
  }) async {
    try {
      await refreshPublishedLibrary();
      final text = await fetchRemoteText(
        sources: [],
        remotePath: 'assets/catalog.json',
      );
      if (text == null ||
          jsonDecode(text)['games'] is! List ||
          abort?.isCompleted == true) {
        throw StateError('Unavailable');
      }
      onCatalog?.call(text);
      return ConnectivityStatus(
        state: ConnectivityState.success,
        message: '公开资料可读取',
        checkedAt: DateTime.now(),
      );
    } catch (_) {
      return ConnectivityStatus(
        state: ConnectivityState.failure,
        message: '公开资料暂不可用，请检查应用服务地址',
        checkedAt: DateTime.now(),
      );
    }
  }

  Future<void> prefetchGameImages({
    required List<AssetSourceConfig> sources,
    required Iterable<String> remotePaths,
  }) async {
    for (final path in remotePaths.toSet()) {
      await ensureCached(sources: sources, remotePath: path);
    }
  }

  Future<List<RemoteAssetFile>> listFilesRecursively({
    required List<AssetSourceConfig> sources,
    required String remotePath,
    int maxDepth = 6,
    int maxEntries = 1000,
  }) async {
    await refreshPublishedLibrary();
    final prefix = '$remotePath/';
    return [
      for (final path
          in _files.keys
              .where(
                (p) =>
                    p.startsWith(prefix) &&
                    p.substring(prefix.length).split('/').length <=
                        maxDepth + 1,
              )
              .take(maxEntries))
        RemoteAssetFile(
          remotePath: path,
          name: path.split('/').last,
          sourceId: 'app_service',
          etag: _files[path]['sha256'] as String,
        ),
    ];
  }
}
