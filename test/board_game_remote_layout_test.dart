import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_settings/webdav_settings.dart';

import 'package:board_game_agent/features/library/models/asset_source_config.dart';
import 'package:board_game_agent/features/library/services/board_game_remote_layout.dart';

void main() {
  test(
    'migrates shipped source and secure endpoint while preserving custom servers and accounts',
    () {
      final old = AssetSourceConfig.fromMap({
        'id': 'cznas_dev',
        'name': 'cznas.dev',
        'address': r'\\cznas.dev\friend',
        'testUrl': 'https://cznas.dev:5006/friend/board-game-lib/',
      });
      expect(old.testUrl, BoardGameRemoteLayout.defaultBaseUrl);
      expect(old.name, '外网访问');
      final migrated = BoardGameRemoteLayout.migrateLegacySettings(
        const WebDavSettings(
          mode: ExternalStorageMode.webDav,
          baseUrl: 'https://cznas.dev:5006/friend/',
          username: 'existing-user',
          password: 'existing-secret',
        ),
      );
      expect(migrated.baseUrl, BoardGameRemoteLayout.defaultBaseUrl);
      expect(migrated.username, 'existing-user');
      expect(migrated.password, 'existing-secret');
      expect(
        BoardGameRemoteLayout.migrateLegacySettings(
          const WebDavSettings(baseUrl: 'https://my.example/friend/'),
        ).baseUrl,
        'https://my.example/friend/',
      );
      final custom = old.copyWith(testUrl: 'https://my.example/friend/');
      expect(
        AssetSourceConfig.decodeList(
          AssetSourceConfig.encodeList([custom]),
        ).single.testUrl,
        custom.testUrl,
      );
    },
  );
  test('uses the shared friend root and app-owned library prefix', () {
    expect(
      BoardGameRemoteLayout.normalizeBaseUri(
        Uri.parse('https://cznas.dev:5006/friend/board-game-lib/'),
      ).toString(),
      'https://cznas.dev:5006/friend/',
    );
    expect(
      BoardGameRemoteLayout.assetPath('assets/catalog.json'),
      'apps/board_game_agent/board-game-lib/assets/catalog.json',
    );
    expect(
      BoardGameRemoteLayout.assetPath(
        'apps/board_game_agent/board-game-lib/assets/catalog.json',
      ),
      'apps/board_game_agent/board-game-lib/assets/catalog.json',
    );
  });

  test('normalizes persisted legacy source settings', () {
    final source = AssetSourceConfig.fromMap({
      'id': 'legacy',
      'name': 'legacy',
      'address': r'\\cznas.dev\friend\board-game-lib',
      'testUrl': 'https://cznas.dev:5006/friend/board-game-lib/',
    });

    expect(source.address, r'\\cznas.dev\friend');
    expect(source.testUrl, 'https://cznas.dev:5006/friend/');
    expect(
      BoardGameRemoteLayout.normalizeSettings(
        const WebDavSettings(
          mode: ExternalStorageMode.webDav,
          baseUrl: 'https://cznas.dev:5006/friend/board-game-lib/',
          username: 'Shane',
          password: 'secret',
        ),
      ).baseUrl,
      'https://cznas.dev:5006/friend/',
    );
  });
}
