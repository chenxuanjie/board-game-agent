import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_client/app_client.dart';
import 'package:app_identity/app_identity.dart';
import 'package:board_game_agent/app/state/app_controller.dart';
import 'package:board_game_agent/core/localization/app_language.dart';
import 'package:board_game_agent/features/assistant/services/ai_service.dart';
import 'package:board_game_agent/features/assistant/services/conversation_store.dart';
import 'package:board_game_agent/features/assistant/services/speech_service.dart';
import 'package:board_game_agent/features/assistant/services/tts_service.dart';
import 'package:board_game_agent/features/community/services/board_public_sync.dart';
import 'package:board_game_agent/features/games/services/game_manifest_service.dart';
import 'package:board_game_agent/features/identity/services/account_service.dart';
import 'package:board_game_agent/features/identity/services/board_personal_store.dart';
import 'package:board_game_agent/features/library/services/remote_asset_service.dart';
import 'package:board_game_agent/features/settings/services/preferences_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:powersync/powersync.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Harness h;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    h = await _Harness.open();
  });
  tearDown(() => h.close());

  test('collection and preference changes skip chat version scans', () async {
    final store = h.store;
    final scans = store.conversationReads;
    await store.addFavorite('cabo');
    await store.setPreference('nickname', 'collections-only');
    await _until(
      () =>
          h.app.favoriteCount == 1 &&
          h.service.displayName == 'collections-only',
    );
    expect(store.conversationReads, scans);
    await store.loadConversationChanges(); // prepare actual session baselines
    final before = store.conversationReads;
    await store.saveConversationChanges({'chat': _session('first')}, {});
    await _until(() => h.app.conversations.any((c) => c.id == 'chat'));
    expect(store.conversationReads, greaterThan(before));
    final checkpointReads = store.conversationReads;
    await store.saveConversationChanges({
      'chat': {
        ..._session('first'),
        'lastRun': {'id': 'local-checkpoint'},
      },
    }, {});
    await _until(() => store.conversationReads > checkpointReads);
    final reads = store.conversationReads;
    await store.setPreference('nickname', 'still-no-chat-scan');
    await _until(() => h.service.displayName == 'still-no-chat-scan');
    expect(store.conversationReads, reads);
  });

  test(
    'chat invalidation during a collection refresh survives the follow-up',
    () async {
      final store = h.store;
      await store.loadConversationChanges();
      final hold = store.holdFavorites();
      await store.setPreference('nickname', 'held-collection');
      await hold.entered.future.timeout(const Duration(seconds: 3));
      await store.saveConversationChanges({'chat': _session('late chat')}, {});
      await Future<void>.delayed(const Duration(milliseconds: 400));
      hold.release.complete();
      await _until(() => h.app.conversations.any((c) => c.id == 'chat'));
      expect(
        h.app.conversations
            .singleWhere((c) => c.id == 'chat')
            .messages
            .single
            .text,
        'late chat',
      );
    },
  );

  test(
    'a change arriving during projection is applied without another notification',
    () async {
      final store = h.store;
      final hold = store.holdFavorites();
      await store.setPreference('nickname', 'first');
      await hold.entered.future.timeout(const Duration(seconds: 3));
      await store.addFavorite('cabo');
      await Future<void>.delayed(const Duration(milliseconds: 450));
      expect(await store.records('favorites'), hasLength(1));
      expect(h.app.favoriteCount, 0); // captured before the new database row
      hold.release.complete();
      await _until(() => h.app.favoriteCount == 1);
      final reads = store.favoriteReads;
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(
        store.favoriteReads,
        reads,
      ); // follow-up settles rather than looping
      expect(store.maxConcurrentReads, 1);
    },
  );

  test(
    'sustained notifications do not postpone the pending projection forever',
    () async {
      final store = h.store;
      final hold = store.holdFavorites();
      // Writes every 50 ms outlast the 250 ms coalescing interval.
      var writesFinished = false;
      final writes = () async {
        for (var i = 0; i < 12; i++) {
          await store.setPreference('nickname', 'burst-$i');
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        writesFinished = true;
      }();
      await hold.entered.future.timeout(const Duration(seconds: 3));
      expect(writesFinished, isFalse);
      await writes;
      await store.addFavorite('cabo');
      hold.release.complete();
      await _until(
        () => h.app.favoriteCount == 1 && h.service.displayName == 'burst-11',
      );
      expect(store.maxConcurrentReads, 1);
    },
  );

  test(
    'a failed final projection retries even if no further database change arrives',
    () async {
      final store = h.store;
      final hold = store.holdFavorites()..fail = true;
      await store.setPreference('nickname', 'retry');
      await hold.entered.future.timeout(const Duration(seconds: 3));
      await store.addFavorite('cabo');
      await Future<void>.delayed(const Duration(milliseconds: 450));
      hold.release.complete();
      await _until(
        () => h.app.favoriteCount == 1 && h.service.displayName == 'retry',
      );
      expect(store.failures, 1);
      expect(store.maxConcurrentReads, 1);
    },
  );

  test('pending local writes do not lose a later refresh intent', () async {
    final store = h.store;
    final writing = _Hold();
    store.writeHold = writing;
    final saving = h.app.setVoiceReplyEnabled(true);
    await writing.entered.future.timeout(const Duration(seconds: 3));
    await store.addFavorite('cabo');
    await Future<void>.delayed(const Duration(milliseconds: 450));
    writing.release.complete();
    await saving;
    await _until(() => h.app.favoriteCount == 1);
  });

  test(
    'paused notifications are retained and resume projects the latest rows',
    () async {
      final store = h.store;
      h.service.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final reads = store.favoriteReads;
      await store.addFavorite('cabo');
      await store.setPreference('nickname', 'background');
      await Future<void>.delayed(const Duration(milliseconds: 450));
      expect(store.favoriteReads, reads);
      expect(h.app.favoriteCount, 0);
      h.service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await _until(
        () => h.app.favoriteCount == 1 && h.service.displayName == 'background',
      );
    },
  );

  test(
    'an obsolete finally cannot overwrite or cancel a new account refresh',
    () async {
      final old = h.store;
      final hold = old.holdFavorites();
      await old.setPreference('nickname', 'old');
      await hold.entered.future.timeout(const Duration(seconds: 3));
      final nickname = _Hold();
      old.preferenceHold = nickname;
      hold.release.complete();
      await nickname.entered.future.timeout(const Duration(seconds: 3));
      // The controller projection is complete; only the old nickname read waits.
      await h.service.signOut();
      await h.login('b' * 64);
      final current = h.store;
      await current.addFavorite('scout');
      await current.setPreference('nickname', 'new');
      nickname.release.complete();
      await _until(
        () => h.app.favoriteCount == 1 && h.service.displayName == 'new',
      );
      expect(h.app.identityUserId, h.service.currentAccountScope);
      expect((await current.records('favorites')).single['game_slug'], 'scout');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(h.service.displayName, 'new');
    },
  );
}

Future<void> _until(bool Function() condition) async {
  final deadline = Stopwatch()..start();
  while (!condition()) {
    if (deadline.elapsed > const Duration(seconds: 4)) {
      fail('Personal projection did not converge');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

class _Hold {
  final entered = Completer<void>(), release = Completer<void>();
  bool fail = false;
}

class _SlowStore extends BoardPersonalStore {
  _SlowStore({required super.database, required super.datasetId});
  _Hold? favoriteHold, preferenceHold, writeHold;
  final holds = <_Hold>[];
  int favoriteReads = 0,
      concurrentReads = 0,
      maxConcurrentReads = 0,
      failures = 0;
  int conversationReads = 0;
  @override
  Future<({Map<String, dynamic> updated, Set<String> deleted})>
  loadConversationChanges() {
    conversationReads++;
    return super.loadConversationChanges();
  }

  _Hold holdFavorites() {
    final hold = _Hold();
    holds.add(hold);
    return favoriteHold = hold;
  }

  @override
  Future<List<Map<String, dynamic>>> loadCollection(String table) async {
    if (table != 'favorites') return super.loadCollection(table);
    favoriteReads++;
    concurrentReads++;
    if (concurrentReads > maxConcurrentReads) {
      maxConcurrentReads = concurrentReads;
    }
    try {
      final rows = await super.loadCollection(table);
      final hold = favoriteHold;
      favoriteHold = null;
      if (hold != null) {
        hold.entered.complete();
        await hold.release.future;
        if (hold.fail) {
          failures++;
          throw StateError('Injected local projection read failure');
        }
      }
      return rows;
    } finally {
      concurrentReads--;
    }
  }

  @override
  Future<Map<String, dynamic>> preferences() async {
    final result = await super.preferences();
    final hold = preferenceHold;
    preferenceHold = null;
    if (hold != null) {
      holds.add(hold);
      hold.entered.complete();
      await hold.release.future;
    }
    return result;
  }

  @override
  Future<void> setPreference(String key, Object value) async {
    final hold = writeHold;
    writeHold = null;
    if (hold != null) {
      holds.add(hold);
      hold.entered.complete();
      await hold.release.future;
    }
    await super.setPreference(key, value);
  }

  Future<void> addFavorite(String slug) => database.execute(
    'INSERT INTO favorites(id,dataset_id,game_slug,created_at) VALUES(?,?,?,?)',
    [slug, datasetId, slug, '2026-11-03T00:00:00Z'],
  );

  @override
  Future<void> connect(
    BoardSyncConnector connector, {
    HttpClientFactory? httpClient,
  }) async {
    // Real SQLite/watch/projection; no NAS or external PowerSync transport.
  }
}

Map<String, dynamic> _session(String content) => {
  'id': 'chat',
  'title': 'chat',
  'scope': 'global',
  'opened': true,
  'createdAt': '2026-11-03T00:00:00Z',
  'updatedAt': '2026-11-03T00:01:00Z',
  'messages': [
    {
      'id': 'm',
      'role': 'assistant',
      'text': content,
      'timestamp': '2026-11-03T00:01:00Z',
      'state': 'complete',
    },
  ],
};

class _Harness {
  _Harness(this.directory, this.app);
  final Directory directory;
  final AppController app;
  late AccountService service;
  final stores = <_SlowStore>[];
  _SlowStore get store => stores.last;
  String user = 'a' * 64;

  static Future<_Harness> open() async {
    final directory = await Directory.systemTemp.createTemp(
      'account-projection-',
    );
    final app = AppController(
      preferencesService: PreferencesService(),
      aiService: _Ai(),
      gameManifestService: GameManifestService(),
      remoteAssetService: RemoteAssetService(),
      speechService: _Speech(),
      ttsService: _Tts(),
      conversationStore: const ConversationStore(browserStorage: true),
    );
    final h = _Harness(directory, app);
    h.service = AccountService(
      controller: app,
      savedLoginStorage: _MemoryStorage(),
      sessionStoreFactory: (_) => _MemoryStorage(),
      httpClientFactory: () => MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          h.user = (jsonDecode(request.body) as Map)['account'] as String;
        }
        if (request.url.path.endsWith('/logout')) {
          return http.Response('{}', 200);
        }
        return http.Response(
          jsonEncode({
            'app_id': 'board_game_agent',
            'user_id': h.user,
            'display_name': 'Reader',
            'access_token': 'fixture-access',
            'refresh_token': 'fixture-refresh',
            'dataset_id': 'dataset-${h.user}',
          }),
          200,
        );
      }),
      personalStoreFactory: (scope, dataset) async {
        final db = PowerSyncDatabase(
          schema: boardPersonalSchema,
          path: '${directory.path}/${h.stores.length}.sqlite',
        );
        await db.initialize();
        final store = _SlowStore(database: db, datasetId: dataset);
        h.stores.add(store);
        return store;
      },
      publicSyncFactory:
          ({
            required client,
            required active,
            required refresh,
            required refreshPublications,
            onStatusChanged,
          }) async => _PublicSync(),
    );
    await h.service.configureService('https://projection.example.test');
    await h.login(h.user);
    return h;
  }

  Future<void> login(String user) async {
    await service.signIn(account: user, password: 'fixture');
    expect(service.isSignedIn, isTrue);
    expect(service.error, isNull);
    // Allow the six initial table-watch snapshots and their projection to settle.
    await Future<void>.delayed(const Duration(milliseconds: 650));
  }

  Future<void> close() async {
    for (final store in stores) {
      for (final hold in [...store.holds, ?store.preferenceHold]) {
        if (!hold.release.isCompleted) hold.release.complete();
      }
    }
    await service.signOut();
    await service.clearConfiguration();
    service.dispose();
    await app.disposeServices();
    app.dispose();
    for (final store in stores) {
      await store.close();
    }
    await directory.delete(recursive: true);
  }
}

class _MemoryStorage implements IdentitySessionStorage, RefreshSessionStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async => value = next;
  @override
  Future<void> delete() async => value = null;
}

class _Ai extends Fake implements AiService {
  @override
  void dispose() {}
}

class _Speech extends SpeechService {
  @override
  Future<void> cancelListening() async {}
}

class _Tts extends TtsService {
  @override
  Future<void> stop() async {}
  @override
  Future<void> initialize(AppLanguage language) async {}
}

class _PublicSync extends Fake implements BoardPublicSync {
  @override
  String? get error => null;
  @override
  Future<void> start() async {}
  @override
  Future<void> close() async {}
  @override
  Future<void> setForeground(bool enabled) async {}
}
