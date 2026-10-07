import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
// ignore: implementation_imports
import 'package:app_ai_client/src/default_http_client.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webdav_storage/webdav_storage.dart';
import 'package:webdav_settings/webdav_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'browser_asset_cache_stub.dart'
    if (dart.library.js_interop) 'browser_asset_cache_web.dart';

import '../models/asset_source_config.dart';
import '../models/cached_asset.dart';
import '../models/game_resource.dart';
import '../../games/models/game_catalog_manifest.dart';
import '../models/remote_asset_file.dart';
import 'board_game_remote_layout.dart';
import '../../../core/models/connectivity_status.dart';

class RemoteAssetService {
  RemoteAssetService({
    http.Client? client,
    WebDavSettings Function()? settingsProvider,
    WebDavSettings Function(Uri)? resourceSettingsProvider,
    bool Function()? accessAllowed,
    this.requestTimeout = const Duration(seconds: 8),
  }) : _settingsProvider = settingsProvider,
       _accessAllowed = accessAllowed,
       _resourceSettingsProvider = resourceSettingsProvider,
       _client = client ?? createDefaultAiHttpClient();

  final http.Client _client;
  final bool Function()? _accessAllowed;
  bool get accessAllowed => _accessAllowed?.call() ?? true;
  final WebDavSettings Function()? _settingsProvider;
  final WebDavSettings Function(Uri)? _resourceSettingsProvider;
  final Duration requestTimeout;

  static const String _versionManifestFileName = '_asset_versions.json';
  Future<void> _versionWriteQueue = Future<void>.value();

  Future<CachedAsset?> ensureCached({
    required List<AssetSourceConfig> sources,
    required String remotePath,
    bool forceRefresh = false,
    bool allowCachedFallback = true,
  }) async {
    if (!accessAllowed) return null;
    if (!_isUsableRemotePath(remotePath)) {
      return null;
    }
    if (kIsWeb) {
      Uint8List? bytes;
      if (!forceRefresh) bytes = await cachedBytesFor(remotePath);
      var fromRemote = false;
      if (bytes == null) {
        final result = await _firstResponse(sources, remotePath, 'GET');
        if (result != null) {
          if (!accessAllowed) return null;
          bytes = result.response.bodyBytes;
          if (forceRefresh) _validateUpdate(remotePath, bytes);
          await writeBrowserAsset(remotePath, bytes);
          await _saveVersionInfo(
            remotePath: remotePath,
            sourceId: result.source.id,
            headers: result.response.headers,
          );
          fromRemote = true;
        } else if (allowCachedFallback) {
          bytes = await cachedBytesFor(remotePath);
        }
      }
      if (bytes == null) return null;
      return CachedAsset(
        remotePath: remotePath,
        localPath: Uri.dataFromBytes(bytes).toString(),
        exists: true,
        fromRemote: fromRemote,
        sourceId: null,
      );
    }
    final File localFile = await _fileFor(remotePath);
    if (!forceRefresh && await localFile.exists()) {
      return CachedAsset(
        remotePath: remotePath,
        localPath: localFile.path,
        exists: true,
        fromRemote: false,
        sourceId: null,
      );
    }

    final result = await _firstResponse(sources, remotePath, 'GET');
    if (!accessAllowed) return null;
    if (result != null) {
      if (!accessAllowed) return null;
      final response = result.response;
      final source = result.source;
      if (forceRefresh) _validateUpdate(remotePath, response.bodyBytes);
      await localFile.parent.create(recursive: true);
      final staged = File('${localFile.path}.download');
      await staged.writeAsBytes(response.bodyBytes, flush: true);
      await staged.rename(localFile.path);
      await _saveVersionInfo(
        remotePath: remotePath,
        sourceId: source.id,
        headers: response.headers,
      );
      return CachedAsset(
        remotePath: remotePath,
        localPath: localFile.path,
        exists: true,
        fromRemote: true,
        sourceId: source.id,
      );
    }

    if (allowCachedFallback && await localFile.exists()) {
      return CachedAsset(
        remotePath: remotePath,
        localPath: localFile.path,
        exists: true,
        fromRemote: false,
        sourceId: null,
      );
    }
    return null;
  }

  Future<String?> fetchRemoteText({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) async {
    final List<int>? bytes = await fetchRemoteBytes(
      sources: sources,
      remotePath: remotePath,
    );
    if (bytes == null) return null;
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  void _validateUpdate(String path, List<int> bytes) {
    if (bytes.isEmpty) throw const FormatException('Empty resource');
    if (!path.endsWith('.json')) return;
    final value = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (path == 'assets/catalog.json') {
      if (value['games'] is! List) {
        throw const FormatException('Invalid catalog');
      }
      GameCatalogManifest.fromJson(value);
    } else if (path.endsWith('/game.json')) {
      GameManifest.fromJson(value);
    } else if (path.endsWith('/manifest.json')) {
      if (value['resources'] is! List) {
        throw const FormatException('Invalid manifest');
      }
      GameResourceManifest.fromJson(value);
    }
  }

  /// Fetches the declared remote file without interpreting its bytes.
  ///
  /// Keeping this separate from [fetchRemoteText] is important for PDF and
  /// other binary rule files: decoding arbitrary bytes as UTF-8 would corrupt
  /// the file before it reaches the Responses API.
  Future<List<int>?> fetchRemoteBytes({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) async {
    if (!_isUsableRemotePath(remotePath)) {
      return null;
    }
    return (await _firstResponse(
      sources,
      remotePath,
      'GET',
    ))?.response.bodyBytes;
  }

  /// A real, uncached knowledge-catalog read, independent of local game data.
  Future<ConnectivityStatus> checkAccess(
    AssetSourceConfig source, {
    Completer<void>? abort,
  }) async {
    ConnectivityStatus status(ConnectivityState state, String message) =>
        ConnectivityStatus(
          state: state,
          message: message,
          checkedAt: DateTime.now(),
        );
    final uri = _buildFileUri(source, 'assets/catalog.json');
    if (uri == null) return status(ConnectivityState.failure, '地址无效');
    try {
      final response = await _request('GET', uri, abort: abort);
      final message = switch (response.statusCode) {
        401 => '需要重新登录',
        403 => '没有资料访问权限',
        404 => '找不到知识库目录',
        _ => '资料服务不可用',
      };
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return status(ConnectivityState.failure, message);
      }
      final catalog = jsonDecode(utf8.decode(response.bodyBytes));
      if (catalog is! Map || catalog['games'] is! List) {
        return status(ConnectivityState.failure, '知识库目录内容无效');
      }
      return status(ConnectivityState.success, '知识库可读取');
    } on TimeoutException {
      return status(ConnectivityState.failure, '连接超时');
    } on FormatException {
      return status(ConnectivityState.failure, '知识库目录内容无效');
    } catch (_) {
      return status(ConnectivityState.failure, '地址暂时无法访问');
    }
  }

  /// Entrances share the same files: the first successful read wins. Only that
  /// response may write the cache; aborting losing requests avoids double writes.
  Future<_RemoteAssetResponse?> _firstResponse(
    List<AssetSourceConfig> sources,
    String path,
    String method,
  ) {
    final seen = <Uri>{};
    final entries = <(AssetSourceConfig, Uri)>[];
    for (final source in sources) {
      final uri = _buildFileUri(source, path);
      if (uri != null && seen.add(uri)) entries.add((source, uri));
    }
    if (entries.isEmpty) return Future.value(null);
    final result = Completer<_RemoteAssetResponse?>();
    final aborts = [for (final _ in entries) Completer<void>()];
    var remaining = entries.length;
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      unawaited(() async {
        try {
          final response = await _request(
            method,
            entry.$2,
            abort: aborts[index],
          );
          if (!result.isCompleted &&
              response.statusCode >= 200 &&
              response.statusCode < 300) {
            result.complete(_RemoteAssetResponse(entry.$1, response));
            for (final abort in aborts) {
              if (!abort.isCompleted) abort.complete();
            }
          }
        } catch (_) {
          // Every entrance settles independently; a failure cannot win the race.
        } finally {
          remaining--;
          if (remaining == 0) {
            if (!result.isCompleted) result.complete(null);
            for (final abort in aborts) {
              if (!abort.isCompleted) abort.complete();
            }
          }
        }
      }());
    }
    return result.future;
  }

  Future<String?> loadCachedOrBundledText({required String remotePath}) async {
    if (!accessAllowed) return null;
    if (kIsWeb) {
      final bytes = await cachedBytesFor(remotePath);
      return bytes == null ? null : utf8.decode(bytes);
    }
    final File? cached = await cachedFileFor(remotePath);
    if (cached != null && await cached.exists()) {
      return cached.readAsString();
    }
    return null;
  }

  Future<bool> hasRemoteChanged({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) async {
    if (!_isUsableRemotePath(remotePath)) {
      return false;
    }
    final Map<String, dynamic>? remote = await _probeRemoteVersion(
      sources: sources,
      remotePath: remotePath,
    );
    if (remote == null) {
      return false;
    }
    final Map<String, dynamic> localMap = await _loadVersionMap();
    final Map<String, dynamic>? local =
        localMap[remotePath] as Map<String, dynamic>?;
    if (local == null) {
      // A missing local fingerprint means this is the first time the
      // resource has been discovered (or the version map was introduced by a
      // newer app). Establish the remote value as the baseline instead of
      // showing a false "content updated" prompt.
      await _saveVersionProbe(remotePath: remotePath, probe: remote);
      return false;
    }
    return _fingerprint(remote) != _fingerprint(local);
  }

  Future<String?> loadText({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) async {
    final CachedAsset? asset = await ensureCached(
      sources: sources,
      remotePath: remotePath,
    );
    if (asset == null || !asset.exists) {
      return null;
    }
    return kIsWeb
        ? utf8.decode(Uri.parse(asset.localPath).data!.contentAsBytes())
        : File(asset.localPath).readAsString();
  }

  Future<Uint8List?> cachedBytesFor(String remotePath) async {
    if (!accessAllowed) return null;
    if (!_isUsableRemotePath(remotePath)) return null;
    if (kIsWeb) return readBrowserAsset(remotePath);
    final file = await cachedFileFor(remotePath);
    return file?.readAsBytes();
  }

  /// Loads a cached or remote file as bytes for an AI file input.
  ///
  /// On Web, private text files can still be fetched through the browser
  /// client. Binary files require a public URL or a same-origin gateway.
  Future<List<int>?> loadBytes({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) async {
    if (!accessAllowed) return null;
    if (!_isUsableRemotePath(remotePath)) {
      return null;
    }
    final CachedAsset? asset = await ensureCached(
      sources: sources,
      remotePath: remotePath,
    );
    if (asset != null && asset.exists) {
      return kIsWeb
          ? Uri.parse(asset.localPath).data!.contentAsBytes()
          : File(asset.localPath).readAsBytes();
    }
    final List<int>? remoteBytes = await fetchRemoteBytes(
      sources: sources,
      remotePath: remotePath,
    );
    if (remoteBytes != null) {
      return remoteBytes;
    }
    try {
      final ByteData data = await rootBundle.load(remotePath);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      return null;
    }
  }

  Future<String?> loadTextFromAny({
    required List<AssetSourceConfig> sources,
    required List<String> remotePaths,
  }) async {
    for (final String path in remotePaths) {
      if (!_isUsableRemotePath(path)) {
        continue;
      }
      final String? content = await loadText(
        sources: sources,
        remotePath: path,
      );
      if (content != null && content.trim().isNotEmpty) {
        return content;
      }
    }
    return null;
  }

  Future<File?> cachedFileFor(String remotePath) async {
    if (!accessAllowed) return null;
    if (kIsWeb || !_isUsableRemotePath(remotePath)) {
      return null;
    }
    final File file = await _fileFor(remotePath);
    if (await file.exists()) {
      return file;
    }
    return null;
  }

  Future<void> prefetchGameImages({
    required List<AssetSourceConfig> sources,
    required Iterable<String> remotePaths,
  }) async {
    for (final String remotePath in remotePaths.toSet()) {
      if (!_isUsableRemotePath(remotePath)) {
        continue;
      }
      await ensureCached(sources: sources, remotePath: remotePath);
    }
  }

  /// Enumerates files below a logical WebDAV directory.
  ///
  /// The shared [WebDavStorageClient] performs the actual `PROPFIND` request;
  /// this service only applies the app's canonical path layout and flattens
  /// the bounded recursive walk into paths the UI can consume.
  Future<List<RemoteAssetFile>> listFilesRecursively({
    required List<AssetSourceConfig> sources,
    required String remotePath,
    int maxDepth = 6,
    int maxEntries = 1000,
  }) async {
    if (!accessAllowed) throw StateError('请先登录后使用知识库');
    if (sources.isEmpty) {
      return const <RemoteAssetFile>[];
    }
    if (maxDepth < 0) {
      throw ArgumentError.value(maxDepth, 'maxDepth');
    }
    if (maxEntries <= 0) {
      throw ArgumentError.value(maxEntries, 'maxEntries');
    }

    final result = Completer<List<RemoteAssetFile>>();
    final aborts = [for (final _ in sources) Completer<void>()];
    var remaining = sources.length;
    for (var index = 0; index < sources.length; index++) {
      unawaited(() async {
        try {
          final files = await _listFromSource(
            source: sources[index],
            remotePath: remotePath,
            maxDepth: maxDepth,
            maxEntries: maxEntries,
            abort: aborts[index],
          ).timeout(const Duration(minutes: 1));
          if (!result.isCompleted) {
            result.complete(files);
            for (final abort in aborts) {
              if (!abort.isCompleted) abort.complete();
            }
          }
        } catch (_) {
          if (!aborts[index].isCompleted) aborts[index].complete();
          if (remaining == 1 && !result.isCompleted) {
            result.completeError(StateError('资料目录暂时无法读取，请重试'));
          }
        } finally {
          remaining--;
        }
      }());
    }
    return result.future;
  }

  Future<List<RemoteAssetFile>> _listFromSource({
    required AssetSourceConfig source,
    required String remotePath,
    required int maxDepth,
    required int maxEntries,
    required Completer<void> abort,
  }) async {
    final Uri? parsed = Uri.tryParse(source.testUrl.trim());
    if (parsed == null || !parsed.hasScheme || !parsed.hasAuthority) {
      throw ArgumentError.value(source.testUrl, 'source.testUrl');
    }
    final WebDavSettings credentials = _webDavSettings(parsed);
    final String username = credentials.username.trim();
    final WebDavStorageClient storage = WebDavStorageClient(
      config: WebDavConfig(
        baseUri: BoardGameRemoteLayout.normalizeBaseUri(parsed),
        username: username.isEmpty ? null : username,
        password: username.isEmpty ? null : credentials.password,
        timeout: requestTimeout,
      ),
      httpClient: _EntranceListClient(_client, abort),
    );

    final List<RemoteAssetFile> files = <RemoteAssetFile>[];
    final List<_RemoteDirectoryRequest> pending = <_RemoteDirectoryRequest>[
      _RemoteDirectoryRequest(path: remotePath, depth: 0),
    ];
    final Set<String> visited = <String>{};
    try {
      while (pending.isNotEmpty && files.length < maxEntries) {
        if (!accessAllowed) throw StateError('请先登录后使用知识库');
        if (abort.isCompleted) throw StateError('Directory read cancelled');
        final _RemoteDirectoryRequest request = pending.removeAt(0);
        if (!visited.add(request.path)) {
          continue;
        }
        final List<RemoteResource> entries = await storage.list(
          BoardGameRemoteLayout.assetPath(request.path),
        );
        for (final RemoteResource entry in entries) {
          final String childPath = _joinRemotePath(request.path, entry.name);
          if (entry.isCollection) {
            if (request.depth < maxDepth) {
              pending.add(
                _RemoteDirectoryRequest(
                  path: childPath,
                  depth: request.depth + 1,
                ),
              );
            }
            continue;
          }
          files.add(
            RemoteAssetFile(
              remotePath: childPath,
              name: entry.name,
              sourceId: source.id,
              etag: entry.etag,
            ),
          );
          if (files.length >= maxEntries) {
            break;
          }
        }
      }
      return List<RemoteAssetFile>.unmodifiable(files);
    } finally {
      // The injected client remains owned by RemoteAssetService.
      storage.close();
    }
  }

  String _joinRemotePath(String parent, String name) {
    final String normalizedParent = parent
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'/+$'), '');
    final String normalizedName = name.replaceAll('\\', '/').trim();
    if (normalizedName.isEmpty ||
        normalizedName.contains('/') ||
        normalizedName == '.' ||
        normalizedName == '..') {
      throw FormatException('Invalid WebDAV resource name: $name');
    }
    return '$normalizedParent/$normalizedName';
  }

  Future<File> _fileFor(String remotePath) async {
    final Directory base = await _cacheRoot();
    final String sanitized = remotePath.replaceAll('\\', '/');
    return File('${base.path}/$sanitized');
  }

  Future<Directory> _cacheRoot() async {
    final Directory support = await getApplicationSupportDirectory();
    final Directory dir = Directory('${support.path}/board_game_agent_cache');
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> _versionManifestFile() async {
    final Directory root = await _cacheRoot();
    return File('${root.path}/$_versionManifestFileName');
  }

  Future<Map<String, dynamic>> _loadVersionMap() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final source = prefs.getString('library.assetVersions.v1');
      return source == null ? {} : jsonDecode(source) as Map<String, dynamic>;
    }
    final File file = await _versionManifestFile();
    if (!await file.exists()) {
      return <String, dynamic>{};
    }
    try {
      final String source = await file.readAsString();
      return jsonDecode(source) as Map<String, dynamic>;
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _saveVersionMap(Map<String, dynamic> map) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString('library.assetVersions.v1', jsonEncode(map))) {
        throw StateError('Unable to save library versions');
      }
      return;
    }
    final File file = await _versionManifestFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(map), flush: true);
  }

  Future<void> _saveVersionInfo({
    required String remotePath,
    required String sourceId,
    required Map<String, String> headers,
  }) async {
    await _saveVersionRecord(remotePath, <String, dynamic>{
      'sourceId': sourceId,
      'etag': headers['etag'],
      'lastModified': headers['last-modified'],
      'contentLength': headers['content-length'],
    });
  }

  Future<void> _saveVersionProbe({
    required String remotePath,
    required Map<String, dynamic> probe,
  }) async {
    await _saveVersionRecord(remotePath, <String, dynamic>{
      'sourceId': probe['sourceId'],
      'etag': probe['etag'],
      'lastModified': probe['lastModified'],
      'contentLength': probe['contentLength'],
    });
  }

  Future<void> _saveVersionRecord(
    String remotePath,
    Map<String, dynamic> record,
  ) {
    final work = _versionWriteQueue.then((_) async {
      final Map<String, dynamic> map = await _loadVersionMap();
      map[remotePath] = record;
      await _saveVersionMap(map);
    });
    _versionWriteQueue = work.catchError((Object _) {});
    return work;
  }

  Future<Map<String, dynamic>?> _probeRemoteVersion({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) async {
    final result = await _firstResponse(sources, remotePath, 'HEAD');
    if (result != null) {
      final response = result.response;
      return <String, dynamic>{
        'sourceId': result.source.id,
        'etag': response.headers['etag'],
        'lastModified': response.headers['last-modified'],
        'contentLength': response.headers['content-length'],
      };
    }
    return null;
  }

  String _fingerprint(Map<String, dynamic> value) {
    return [
      value['etag'] ?? '',
      value['lastModified'] ?? '',
      value['contentLength'] ?? '',
    ].join('|');
  }

  Uri? _buildFileUri(AssetSourceConfig source, String remotePath) {
    if (!_isUsableRemotePath(remotePath)) {
      return null;
    }
    final Match? match = RegExp(
      r'^https?://([^/:]+)(?::(\d+))?(/.*)?$',
    ).firstMatch(source.testUrl);
    if (match == null) {
      return null;
    }
    final String host = match.group(1)!;
    final int? port = match.group(2) == null
        ? null
        : int.parse(match.group(2)!);
    final String basePath = (match.group(3) ?? '').replaceFirst(
      RegExp(r'/$'),
      '',
    );
    final String relativePath = BoardGameRemoteLayout.assetPath(remotePath);
    final String uriPath = '$basePath/$relativePath'.replaceAll('//', '/');
    return Uri(
      scheme: source.testUrl.startsWith('https://') ? 'https' : 'http',
      host: host,
      port: port,
      path: uriPath,
    );
  }

  bool _isUsableRemotePath(String remotePath) {
    final String normalized = remotePath.replaceAll('\\', '/').trim();
    return normalized.isNotEmpty &&
        !normalized.split('/').contains('..') &&
        !isOtherStoragePath(normalized);
  }

  bool _belongsTo(Uri target, String baseUrl) {
    final base = Uri.tryParse(baseUrl);
    if (base == null ||
        !['http', 'https'].contains(base.scheme) ||
        base.host.isEmpty ||
        target.origin != base.origin) {
      return false;
    }
    final root = base.path.endsWith('/') ? base.path : '${base.path}/';
    return target.path == base.path || target.path.startsWith(root);
  }

  WebDavSettings _webDavSettings(Uri target) {
    if (_resourceSettingsProvider != null) {
      return _resourceSettingsProvider(target);
    }
    final WebDavSettings? configured = _settingsProvider?.call();
    // A newly imported account must never authenticate unrelated data sources.
    if (configured != null && _belongsTo(target, configured.baseUrl)) {
      return configured;
    }
    return const WebDavSettings();
  }

  Future<http.Response> _request(
    String method,
    Uri target, {
    Completer<void>? abort,
  }) async {
    if (!accessAllowed) return http.Response('', 401);
    final requestAbort = Completer<void>();
    abort?.future.then((_) {
      if (!requestAbort.isCompleted) requestAbort.complete();
    });
    final request =
        http.AbortableRequest(method, target, abortTrigger: requestAbort.future)
          ..followRedirects = false
          ..headers.addAll(_headers(target));
    try {
      final response = await (() async => http.Response.fromStream(
        await _client.send(request),
      ))().timeout(requestTimeout);
      return accessAllowed ? response : http.Response('', 401);
    } finally {
      if (!requestAbort.isCompleted) requestAbort.complete();
    }
  }

  Map<String, String> _headers(Uri target) {
    final WebDavSettings settings = _webDavSettings(target);
    if (settings.username.trim().isEmpty || settings.password.isEmpty) {
      return const <String, String>{};
    }
    final String encoded = base64Encode(
      utf8.encode('${settings.username.trim()}:${settings.password}'),
    );
    return <String, String>{'Authorization': 'Basic $encoded'};
  }
}

/// The shared WebDAV parser keeps owning PROPFIND/XML. This transport adapter
/// only adds per-entrance cancellation; it never closes the shared HTTP client.
class _EntranceListClient extends http.BaseClient {
  _EntranceListClient(this.delegate, this.abort);
  final http.Client delegate;
  final Completer<void> abort;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request is! http.Request) {
      throw StateError('Unsupported directory request');
    }
    final cancellable =
        http.AbortableRequest(
            request.method,
            request.url,
            abortTrigger: abort.future,
          )
          ..followRedirects = false
          ..headers.addAll(request.headers)
          ..bodyBytes = request.bodyBytes;
    return delegate.send(cancellable);
  }

  @override
  void close() {}
}

class _RemoteAssetResponse {
  const _RemoteAssetResponse(this.source, this.response);
  final AssetSourceConfig source;
  final http.Response response;
}

class _RemoteDirectoryRequest {
  const _RemoteDirectoryRequest({required this.path, required this.depth});

  final String path;
  final int depth;
}
