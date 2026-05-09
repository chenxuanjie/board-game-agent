import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path_provider/path_provider.dart';

import '../models/asset_source_config.dart';
import '../models/cached_asset.dart';

class RemoteAssetService {
  RemoteAssetService({http.Client? client})
    : _client =
          client ??
          IOClient(
            HttpClient()
              ..badCertificateCallback =
                  (X509Certificate cert, String host, int port) => true,
          );

  final http.Client _client;

  static const String _defaultUsername = 'Shane';
  static const String _defaultPassword = '1';
  static const String _versionManifestFileName = '_asset_versions.json';
  String? _username;
  String? _password;
  bool _authLoaded = false;

  Future<CachedAsset?> ensureCached({
    required List<AssetSourceConfig> sources,
    required String remotePath,
    bool forceRefresh = false,
    bool allowCachedFallback = true,
  }) async {
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
          return utf8.decode(response.bodyBytes);
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<String?> loadCachedOrBundledText({
    required String remotePath,
  }) async {
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
      return true;
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

  Future<String?> loadTextFromAny({
    required List<AssetSourceConfig> sources,
    required List<String> remotePaths,
  }) async {
    for (final String path in remotePaths) {
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
      await ensureCached(sources: sources, remotePath: remotePath);
    }
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
    final Map<String, dynamic> map = await _loadVersionMap();
    map[remotePath] = <String, dynamic>{
      'sourceId': sourceId,
      'etag': headers['etag'],
      'lastModified': headers['last-modified'],
      'contentLength': headers['content-length'],
    };
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
      value['sourceId'] ?? '',
      value['etag'] ?? '',
      value['lastModified'] ?? '',
      value['contentLength'] ?? '',
    ].join('|');
  }

  Uri? _buildFileUri(AssetSourceConfig source, String remotePath) {
    final Match? match = RegExp(
      r'^https?://([^/:]+)(?::(\d+))?(/.*)?$',
    ).firstMatch(source.testUrl);
    if (match == null) {
      return null;
    }
    final String host = match.group(1)!;
    final int? port = match.group(2) == null ? null : int.parse(match.group(2)!);
    final String basePath = (match.group(3) ?? '').replaceFirst(RegExp(r'/$'), '');
    final String relativePath = remotePath.startsWith('/')
        ? remotePath.substring(1)
        : remotePath;
    final String uriPath = '$basePath/$relativePath'.replaceAll('//', '/');
    return Uri(
      scheme: source.testUrl.startsWith('https://') ? 'https' : 'http',
      host: host,
      port: port,
      path: uriPath,
    );
  }

  Future<Map<String, String>> _headers() async {
    await _ensureAuthLoaded();
    final String encoded = base64Encode(
      utf8.encode('${_username ?? _defaultUsername}:${_password ?? _defaultPassword}'),
    );
    return <String, String>{'Authorization': 'Basic $encoded'};
  }

  Future<void> _ensureAuthLoaded() async {
    if (_authLoaded) {
      return;
    }
    _authLoaded = true;
    try {
      final String source = await rootBundle.loadString(
        'assets/storage_endpoints.json',
      );
      final Map<String, dynamic> json = jsonDecode(source) as Map<String, dynamic>;
      final Map<String, dynamic>? auth = json['auth'] as Map<String, dynamic>?;
      final String? username = auth?['username'] as String?;
      final String? password = auth?['password'] as String?;
      if (username != null && username.trim().isNotEmpty) {
        _username = username.trim();
      }
      if (password != null && password.isNotEmpty) {
        _password = password;
      }
      print('[assets] auth loaded for remote library: ${_username ?? _defaultUsername}');
    } catch (_) {
      _username = _defaultUsername;
      _password = _defaultPassword;
      print('[assets] auth fallback in use: $_defaultUsername');
    }
  }
}
