import 'dart:convert';
import 'dart:io';

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

    for (final source in sources) {
      final Uri? uri = _buildFileUri(source, remotePath);
      if (uri == null) {
        continue;
      }
      try {
        final http.Response response = await _client
            .get(uri, headers: _headers())
            .timeout(const Duration(seconds: 6));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          await localFile.parent.create(recursive: true);
          await localFile.writeAsBytes(response.bodyBytes, flush: true);
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

  Map<String, String> _headers() {
    final String encoded = base64Encode(
      utf8.encode('$_defaultUsername:$_defaultPassword'),
    );
    return <String, String>{'Authorization': 'Basic $encoded'};
  }
}
