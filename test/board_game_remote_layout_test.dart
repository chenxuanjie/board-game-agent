import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_settings/webdav_settings.dart';

import 'package:board_game_agent/models/asset_source_config.dart';
import 'package:board_game_agent/services/board_game_remote_layout.dart';

void main() {
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
