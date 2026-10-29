import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:board_game_agent/app/state/app_controller.dart';
import 'package:board_game_agent/features/assistant/services/ai_service.dart';
import 'package:board_game_agent/features/assistant/services/speech_service.dart';
import 'package:board_game_agent/features/assistant/services/tts_service.dart';
import 'package:board_game_agent/features/games/services/game_manifest_service.dart';
import 'package:board_game_agent/features/library/services/remote_asset_service.dart';
import 'package:board_game_agent/features/settings/services/preferences_service.dart';
import 'package:board_game_agent/ui/shared/library_update_review.dart';
import 'support/catalog_http_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late CatalogHttpFixture fixture;
  late RemoteAssetService remote;
  late AppController controller;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('board-library-flow-');
    fixture = CatalogHttpFixture();
    remote = RemoteAssetService(
      client: fixture.client,
      cacheDirectory: directory,
      serviceOrigin: () => Uri.parse('https://api.test'),
    );
    controller = createController(remote);
    await controller.reloadGames();
  });
  tearDown(() async {
    controller.dispose();
    await directory.delete(recursive: true);
  });
  test(
    'published metadata updates games and document lists without downloading documents',
    () async {
      await controller.refreshLibraryResources();
      fixture.requests.clear();
      fixture.put('cabo', title: '新的卡波', text: 'new rules', bump: true);
      await controller.checkForLibraryUpdates();
      expect(controller.games.single.title, '新的卡波');
      expect(controller.libraryResources, hasLength(2));
      expect(controller.lastLibraryUpdate!.changedGameTitles, ['新的卡波']);
      expect(controller.libraryUpdateError, isNull);
      expect(
        fixture.requests.any((r) => r.url.path.contains('/content')),
        isFalse,
      );
      expect(
        fixture.requests.any((r) => r.url.path.endsWith('.json')),
        isFalse,
      );
    },
  );
  test(
    'publication failure retains cache and a retry applies the target',
    () async {
      fixture.put('cabo', title: 'Published', bump: true);
      fixture.offline = true;
      await expectLater(
        controller.refreshPublishedLibrary(knownRevision: 2),
        throwsStateError,
      );
      expect(remote.catalog!.revision, 1);
      fixture.offline = false;
      await controller.refreshPublishedLibrary(knownRevision: 2);
      expect(remote.catalog!.revision, 2);
      expect(controller.games.single.title, 'Published');
      expect(
        fixture.requests.any((r) => r.url.path.endsWith('/changes')),
        isTrue,
      );
      expect(
        fixture.requests.any((r) => r.url.path.contains('/content')),
        isFalse,
      );
    },
  );
  test('new publication arriving during a check is not lost', () async {
    fixture.gate = Completer<void>();
    final first = controller.checkForLibraryUpdatesQuick(knownRevision: 1);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    fixture.put('cabo', title: 'Concurrent', bump: true);
    final next = controller.refreshPublishedLibrary(knownRevision: 2);
    fixture.gate!.complete();
    await Future.wait([first, next]);
    expect(remote.catalog!.revision, 2);
    expect(controller.games.single.title, 'Concurrent');
  });
  test(
    'an unpublished edition disappears atomically without retaining bundled cards',
    () async {
      fixture.remove('cabo');
      await controller.checkForLibraryUpdates();
      expect(controller.games, isEmpty);
      expect(controller.libraryResources, isEmpty);
      expect(controller.gameCatalogLoadState, LibraryLoadState.empty);
    },
  );
  test(
    'bad metadata preserves cards, the current revision and a retryable failure',
    () async {
      fixture.put('cabo', title: 'Broken', bump: true);
      fixture.editions['cabo']!['locales'] = {};
      await controller.checkForLibraryUpdates();
      expect(controller.games.single.title, 'cabo');
      expect(remote.catalog!.revision, 1);
      expect(controller.libraryUpdateError, isNotNull);
      fixture.editions['cabo']!['locales'] = {
        'en': {'title': 'Recovered'},
      };
      await controller.checkForLibraryUpdates();
      expect(controller.games.single.title, 'Recovered');
      expect(controller.libraryUpdateError, isNull);
    },
  );
  test(
    'repeated checks coalesce and a requested final pass completes after the active read',
    () async {
      fixture.gate = Completer<void>();
      fixture.requests.clear();
      final a = controller.checkForLibraryUpdatesQuick();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final b = controller.checkForLibraryUpdates();
      expect(controller.checkingLibraryUpdate, isTrue);
      fixture.gate!.complete();
      await Future.wait([a, b]);
      expect(controller.checkingLibraryUpdate, isFalse);
      expect(
        fixture.requests.every((r) => r.url.path.endsWith('/revision')),
        isTrue,
      );
      expect(fixture.requests.length, inInclusiveRange(1, 2));
    },
  );
  test(
    'availability uses a revision probe rather than downloading a JSON file',
    () async {
      controller.configureApplicationLibrary(Uri.parse('https://api.test'));
      fixture.requests.clear();
      await controller.refreshAssetAccessStatus();
      await controller.checkForLibraryUpdates();
      expect(
        fixture.requests.every((r) => !r.url.path.endsWith('.json')),
        isTrue,
      );
      expect(
        fixture.requests.where((r) => r.url.path.endsWith('/revision')),
        isNotEmpty,
      );
      expect(controller.games.single.id, 'cabo');
    },
  );
  test(
    'changing the configured service clears old visible metadata before the next result',
    () {
      controller.configureApplicationLibrary(Uri.parse('https://other.test'));
      expect(controller.games, isEmpty);
      expect(controller.libraryResources, isEmpty);
      expect(controller.lastLibraryUpdate, isNull);
    },
  );
  testWidgets(
    'update review reports applied metadata and stays usable on a narrow large-text screen',
    (tester) async {
      fixture.put('cabo', title: '新的卡波', bump: true);
      await tester.runAsync(() => controller.checkForLibraryUpdates());
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2),
            ),
            child: LibraryUpdateReview(controller: controller, fullPage: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('当前资料已是最新。'), findsOneWidget);
      expect(find.text('新的卡波'), findsOneWidget);
      expect(find.text('关闭'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

AppController createController(RemoteAssetService remote) => AppController(
  preferencesService: PreferencesService(),
  aiService: _NoAi(),
  gameManifestService: GameManifestService(),
  remoteAssetService: remote,
  speechService: SpeechService(),
  ttsService: TtsService(),
);

class _NoAi extends Fake implements AiService {}
