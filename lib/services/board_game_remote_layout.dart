import 'package:webdav_settings/webdav_settings.dart';

/// Canonical WebDAV layout for the Board Game Agent app.
///
/// The shared WebDAV endpoint is rooted at `/friend/`. App-owned content then
/// lives below `apps/board_game_agent`, matching the Zheri layout.
final class BoardGameRemoteLayout {
  const BoardGameRemoteLayout._();

  static const String appRoot = 'apps/board_game_agent';
  static const String libraryRoot = '$appRoot/board-game-lib';
  static const String updateManifestPath = '$appRoot/updates/manifest.json';

  static String assetPath(String logicalPath) {
    final normalized = logicalPath
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'^/+'), '');
    if (normalized.isEmpty || normalized.split('/').contains('..')) {
      throw ArgumentError.value(logicalPath, 'logicalPath');
    }
    if (normalized == libraryRoot || normalized.startsWith('$libraryRoot/')) {
      return normalized;
    }
    return '$libraryRoot/$normalized';
  }

  static WebDavSettings normalizeSettings(WebDavSettings settings) {
    final raw = settings.baseUrl.trim();
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return settings;
    }
    final normalized = normalizeBaseUri(uri).toString();
    if (normalized == raw) return settings;
    return settings.copyWith(baseUrl: normalized);
  }

  static Uri normalizeBaseUri(Uri source) {
    final segments = source.path
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList();
    final friendIndex = segments.indexOf('friend');
    final rootSegments = friendIndex >= 0
        ? segments.take(friendIndex + 1).toList()
        : segments;
    final path = rootSegments.isEmpty ? '/' : '/${rootSegments.join('/')}/';
    return Uri(
      scheme: source.scheme,
      userInfo: source.userInfo,
      host: source.host,
      port: source.hasPort ? source.port : null,
      path: path,
    );
  }
}
