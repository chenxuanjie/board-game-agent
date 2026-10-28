import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:board_game_agent/app/state/app_controller.dart';
import 'package:board_game_agent/features/assistant/services/ai_service.dart';
import 'package:board_game_agent/features/assistant/services/speech_service.dart';
import 'package:board_game_agent/features/assistant/services/tts_service.dart';
import 'package:board_game_agent/features/games/services/game_manifest_service.dart';
import 'package:board_game_agent/features/library/services/remote_asset_service.dart';
import 'package:board_game_agent/features/settings/services/preferences_service.dart';
import 'support/catalog_http_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'library rows are derived from SQL resource metadata without document downloads',
    () async {
      SharedPreferences.setMockInitialValues({});
      final directory = await Directory.systemTemp.createTemp('board-index-');
      final fixture = CatalogHttpFixture();
      final c = createController(fixture, directory);
      addTearDown(() async {
        c.dispose();
        await directory.delete(recursive: true);
      });
      await c.reloadGames();
      fixture.requests.clear();
      await c.refreshLibraryResources();
      expect(c.libraryLoadState, LibraryLoadState.success);
      expect(c.libraryResources.map((r) => r.id).toSet(), {
        'cabo-rules',
        'cabo-pdf',
      });
      expect(fixture.requests, isEmpty);
    },
  );
  test(
    'a restart restores an origin-scoped SQL snapshot and offline refresh preserves rows',
    () async {
      SharedPreferences.setMockInitialValues({});
      final directory = await Directory.systemTemp.createTemp(
        'board-index-offline-',
      );
      final firstFixture = CatalogHttpFixture();
      final first = createController(firstFixture, directory);
      await first.reloadGames();
      await first.refreshLibraryResources();
      first.dispose();
      final offline = CatalogHttpFixture()..offline = true;
      final second = createController(offline, directory);
      addTearDown(() async {
        second.dispose();
        await directory.delete(recursive: true);
      });
      await second.reloadGames();
      await second.refreshLibraryResources(force: true);
      expect(second.libraryLoadState, LibraryLoadState.failure);
      expect(second.libraryResources, hasLength(2));
      expect(second.games.single.id, 'cabo');
      expect(second.libraryLoadError, isNotNull);
    },
  );
}

AppController createController(
  CatalogHttpFixture fixture,
  Directory directory,
) => AppController(
  preferencesService: PreferencesService(),
  aiService: _NoAi(),
  gameManifestService: GameManifestService(),
  remoteAssetService: RemoteAssetService(
    client: fixture.client,
    cacheDirectory: directory,
    serviceOrigin: () => Uri.parse('https://api.test'),
  ),
  speechService: SpeechService(),
  ttsService: TtsService(),
);

class _NoAi extends Fake implements AiService {}
