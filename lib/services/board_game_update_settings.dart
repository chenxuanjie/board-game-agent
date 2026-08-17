import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:webdav_settings/webdav_settings.dart';

import '../models/asset_source_config.dart';
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

    final auth = await _loadAuth();
    return WebDavSettings(
      mode: ExternalStorageMode.webDav,
      baseUrl: BoardGameRemoteLayout.normalizeBaseUri(sourceUri).toString(),
      username: auth.$1,
      password: auth.$2,
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

  static Future<(String, String)> _loadAuth() async {
    try {
      final source = await rootBundle.loadString(
        'assets/storage_endpoints.json',
      );
      final json = jsonDecode(source);
      if (json is! Map) return ('', '');
      final auth = json['auth'];
      if (auth is! Map) return ('', '');
      final username = auth['username'];
      final password = auth['password'];
      return (
        username is String ? username.trim() : '',
        password is String ? password : '',
      );
    } catch (_) {
      return ('', '');
    }
  }
}
