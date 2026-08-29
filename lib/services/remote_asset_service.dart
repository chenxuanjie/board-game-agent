import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webdav_storage/webdav_storage.dart';

import '../models/asset_source_config.dart';
import '../models/cached_asset.dart';
import '../models/game_resource.dart';
import '../models/remote_asset_file.dart';
import 'board_game_remote_layout.dart';
import 'board_game_remote_credentials.dart';

class RemoteAssetService {
  RemoteAssetService({http.Client? client})
    : _client =
          client ??
          (kIsWeb
              ? http.Client()
              : IOClient(
                  HttpClient()
                    ..badCertificateCallback =
                        (X509Certificate cert, String host, int port) => true,
                ));

  final http.Client _client;

  static const String _versionManifestFileName = '_asset_versions.json';

  Future<CachedAsset?> ensureCached({
    required List<AssetSourceConfig> sources,
    required String remotePath,
    bool forceRefresh = false,
    bool allowCachedFallback = true,
  }) async {
    if (kIsWeb || !_isUsableRemotePath(remotePath)) {
      return null;
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

    final Map<String, String> headers = await _headers();

    for (final source in sources) {
      final Uri? uri = _buildFileUri(source, remotePath);
      if (uri == null) {
        continue;
      }
      try {
        final http.Response response = await _client
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 6));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          await localFile.parent.create(recursive: true);
          await localFile.writeAsBytes(response.bodyBytes, flush: true);
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
      } catch (_) {
        continue;
      }
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
    final Map<String, String> headers = await _headers();
    for (final source in sources) {
      final Uri? uri = _buildFileUri(source, remotePath);
      if (uri == null) {
        continue;
      }
      try {
        final http.Response response = await _client
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 8));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response.bodyBytes;
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<String?> loadCachedOrBundledText({required String remotePath}) async {
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
    if (kIsWeb || !_isUsableRemotePath(remotePath)) {
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
    return File(asset.localPath).readAsString();
  }

  /// Loads a cached or remote file as bytes for an AI file input.
  ///
  /// On Web, private text files can still be fetched through the browser
  /// client. Binary files require a public URL or a same-origin gateway.
  Future<List<int>?> loadBytes({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) async {
    if (!_isUsableRemotePath(remotePath)) {
      return null;
    }
    final CachedAsset? asset = await ensureCached(
      sources: sources,
      remotePath: remotePath,
    );
    if (asset != null && asset.exists && !kIsWeb) {
      return File(asset.localPath).readAsBytes();
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
    if (sources.isEmpty) {
      return const <RemoteAssetFile>[];
    }
    if (maxDepth < 0) {
      throw ArgumentError.value(maxDepth, 'maxDepth');
    }
    if (maxEntries <= 0) {
      throw ArgumentError.value(maxEntries, 'maxEntries');
    }

    Object? lastError;
    for (final AssetSourceConfig source in sources) {
      try {
        final List<RemoteAssetFile> files = await _listFromSource(
          source: source,
          remotePath: remotePath,
          maxDepth: maxDepth,
          maxEntries: maxEntries,
        );
        debugPrint(
          '[assets] listed ${files.length} files below $remotePath from ${source.id}',
        );
        return files;
      } catch (error) {
        lastError = error;
        debugPrint('[assets] list failed for ${source.id}: $error');
      }
    }

    if (lastError != null) {
      throw lastError;
    }
    return const <RemoteAssetFile>[];
  }

  Future<List<RemoteAssetFile>> _listFromSource({
    required AssetSourceConfig source,
    required String remotePath,
    required int maxDepth,
    required int maxEntries,
  }) async {
    final Uri? parsed = Uri.tryParse(source.testUrl.trim());
    if (parsed == null || !parsed.hasScheme || !parsed.hasAuthority) {
      throw ArgumentError.value(source.testUrl, 'source.testUrl');
    }
    final WebDavStorageClient storage = WebDavStorageClient(
      config: WebDavConfig(
        baseUri: BoardGameRemoteLayout.normalizeBaseUri(parsed),
        username: BoardGameRemoteCredentials.username,
        password: BoardGameRemoteCredentials.password,
        timeout: const Duration(seconds: 8),
      ),
      httpClient: _client,
    );

    final List<RemoteAssetFile> files = <RemoteAssetFile>[];
    final List<_RemoteDirectoryRequest> pending = <_RemoteDirectoryRequest>[
      _RemoteDirectoryRequest(path: remotePath, depth: 0),
    ];
    final Set<String> visited = <String>{};
    try {
      while (pending.isNotEmpty && files.length < maxEntries) {
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
  ) async {
    final Map<String, dynamic> map = await _loadVersionMap();
    map[remotePath] = record;
    await _saveVersionMap(map);
  }

  Future<Map<String, dynamic>?> _probeRemoteVersion({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) async {
    final Map<String, String> headers = await _headers();
    for (final source in sources) {
      final Uri? uri = _buildFileUri(source, remotePath);
      if (uri == null) {
        continue;
      }
      try {
        final http.Response response = await _client
            .head(uri, headers: headers)
            .timeout(const Duration(seconds: 8));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return <String, dynamic>{
            'sourceId': source.id,
            'etag': response.headers['etag'],
            'lastModified': response.headers['last-modified'],
            'contentLength': response.headers['content-length'],
          };
        }
      } catch (_) {
        continue;
      }
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

  Future<Map<String, String>> _headers() async {
    final String encoded = base64Encode(
      utf8.encode(
        '${BoardGameRemoteCredentials.username}:${BoardGameRemoteCredentials.password}',
      ),
    );
    return <String, String>{'Authorization': 'Basic $encoded'};
  }
}

class _RemoteDirectoryRequest {
  const _RemoteDirectoryRequest({required this.path, required this.depth});

  final String path;
  final int depth;
}
