import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_settings/webdav_settings.dart';
import 'package:board_game_agent/features/library/services/board_game_remote_layout.dart';

void main() {
  test(
    'normalizes optional WebDAV configuration without changing credentials',
    () {
      final result = BoardGameRemoteLayout.normalizeSettings(
        const WebDavSettings(
          mode: ExternalStorageMode.webDav,
          baseUrl: 'https://my.example/friend/',
          username: 'user',
          password: 'secret',
        ),
      );
      expect(result.baseUrl, 'https://my.example/friend/');
      expect(result.username, 'user');
      expect(result.password, 'secret');
      expect(
        BoardGameRemoteLayout.updateManifestPath,
        'apps/board_game_agent/updates/manifest.json',
      );
    },
  );
}
