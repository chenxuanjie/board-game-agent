import 'package:webdav_settings/webdav_settings.dart';

import '../models/asset_source_config.dart';
import 'board_game_remote_credentials.dart';
import 'board_game_remote_layout.dart';

class BoardGameUpdateSettingsLoader {
  const BoardGameUpdateSettingsLoader._();

  static Future<WebDavSettings> load({
    List<AssetSourceConfig> sources = AssetSourceConfig.defaults,
  }) async {
    final source = _selectSource(sources);
    final sourceUri = Uri.tryParse(source.testUrl);
    if (sourceUri == null || !sourceUri.hasScheme || !sourceUri.hasAuthority) {
      return const WebDavSettings();
    }

    return WebDavSettings(
      mode: ExternalStorageMode.webDav,
      baseUrl: BoardGameRemoteLayout.normalizeBaseUri(sourceUri).toString(),
      username: BoardGameRemoteCredentials.username,
      password: BoardGameRemoteCredentials.password,
    );
  }

  static AssetSourceConfig _selectSource(List<AssetSourceConfig> sources) {
    for (final source in sources) {
      final uri = Uri.tryParse(source.testUrl);
      if (uri?.host.toLowerCase() == 'cznas.dev') return source;
    }
    for (final source in sources) {
      final uri = Uri.tryParse(source.testUrl);
      if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
        return source;
      }
    }
    return const AssetSourceConfig(
      id: 'none',
      name: 'none',
      address: '',
      testUrl: '',
    );
  }
}
