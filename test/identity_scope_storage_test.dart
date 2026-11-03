import 'support/catalog_fixture.dart';
import 'dart:async';
import 'dart:io';
import 'package:powersync/powersync.dart';

import 'package:app_ai_client/app_ai_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:board_game_agent/features/games/models/game_vote_record.dart';

import 'package:board_game_agent/app/state/app_controller.dart';
import 'package:board_game_agent/core/localization/app_language.dart';
import 'package:board_game_agent/core/models/app_activity.dart';
import 'package:board_game_agent/core/theme/color_scheme_option.dart';
import 'package:board_game_agent/features/assistant/models/ai_answer_mode.dart';
import 'package:board_game_agent/features/assistant/models/ai_api_config.dart';
import 'package:board_game_agent/features/assistant/models/chat_message.dart';
import 'package:board_game_agent/features/assistant/models/answer_source.dart';
import 'package:board_game_agent/features/assistant/models/board_game_ai_answer.dart';
import 'package:board_game_agent/features/assistant/services/ai_service.dart';
import 'package:board_game_agent/features/assistant/services/ai_run_telemetry.dart';
import 'package:board_game_agent/features/assistant/services/responses_rules_workflow.dart';
import 'package:board_game_agent/features/assistant/services/conversation_store.dart';
import 'package:board_game_agent/features/assistant/services/speech_service.dart';
import 'package:board_game_agent/features/assistant/services/tts_service.dart';
import 'package:board_game_agent/features/games/models/daily_recommendation_record.dart';
import 'package:board_game_agent/features/games/models/favorite_game_record.dart';
import 'package:board_game_agent/features/games/models/game_info.dart';
import 'package:board_game_agent/features/games/models/recent_game_record.dart';
import 'package:board_game_agent/features/games/services/game_vote_service.dart';
import 'package:board_game_agent/features/games/services/remote_game_vote_store.dart';
import 'package:board_game_agent/features/library/models/asset_source_config.dart';
import 'package:board_game_agent/features/library/models/cached_asset.dart';
import 'package:board_game_agent/features/library/services/remote_asset_service.dart';
import 'package:board_game_agent/features/settings/services/preferences_service.dart';
import 'package:board_game_agent/features/identity/services/board_personal_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'gallery positions restore per account and survive reorder and missing images',
    () async {
      final app = await _app();
      final game = app.games.first;
      const paths = ['images/one.jpg', 'images/two.jpg', 'images/three.jpg'];
      await app.rememberGameGalleryImage(game, paths[1]);
      await app.switchIdentityScope('a');
      expect(app.gameGalleryIndex(game, paths), 0);
      await app.rememberGameGalleryImage(game, paths[2]);
      await app.switchIdentityScope('b');
      expect(app.gameGalleryIndex(game, paths), 0);
      await app.rememberGameGalleryImage(game, paths[1]);
      await app.switchIdentityScope('a');
      expect(app.gameGalleryIndex(game, paths), 2);
      await app.switchIdentityScope(null);
      expect(app.gameGalleryIndex(game, paths), 1);
      final restored = await _app();
      await restored.switchIdentityScope('a');
      expect(restored.gameGalleryIndex(game, paths), 2);
      expect(
        restored.gameGalleryIndex(game, [paths[1], paths[2], paths[0]]),
        1,
      );
      expect(restored.gameGalleryIndex(game, paths.take(2).toList()), 0);
    },
  );
  test('guest never displays legacy anonymous public counters', () async {
    final app = await _app();
    final slug = app.games.first.slug;
    final prefs = PreferencesService();
    await prefs.saveGameVoteCache(
      GameVoteCache(
        ballot: GameVoteBallot(
          deviceId: '0123456789abcdef0123456789abcdef',
          games: [slug],
        ),
        remoteCounts: {
          'legacy-anonymous': {slug: 99},
        },
        lastScope: 'legacy-anonymous',
      ).encode(),
    );
    await prefs.saveFavoriteRankingCache(
      GameVoteCache(
        ballot: GameVoteBallot(
          deviceId: '0123456789abcdef0123456789abcdef',
          games: [],
          namespace: GameVoteBallot.favoritesNamespace,
        ),
        remoteCounts: {
          'legacy-anonymous': {slug: 99},
        },
        lastScope: 'legacy-anonymous',
      ).encode(),
    );
    await app.gameVotes.reload();
    expect(app.gameVotes.count(slug), 1);
    expect(app.gameVotes.hasCachedRemoteCounts, isFalse);
    await app.refreshFavoriteRankings();
    expect(app.favoriteStatistics.count(slug), 0);
    expect(app.favoriteStatistics.hasCachedRemoteCounts, isFalse);
  });

  test('legacy personal preferences belong exclusively to guest', () async {
    SharedPreferences.setMockInitialValues({
      'recent_searches_v1': ['legacy guest search'],
      'selected_conversation_id': 'global',
    });
    final guest = PreferencesService();
    final a = guest.forIdentityScope('stable-a');
    final b = guest.forIdentityScope('stable-b');
    expect(await a.loadRecentSearches(), isEmpty);
    expect(await a.loadSelectedConversationId(), isNull);
    await a.saveRecentSearches(['a search']);
    await b.saveRecentSearches(['b search']);
    expect(await guest.loadRecentSearches(), ['legacy guest search']);
    expect(await a.loadRecentSearches(), ['a search']);
    expect(await b.loadRecentSearches(), ['b search']);
    expect(await guest.loadSelectedConversationId(), 'global');
    expect(await a.forIdentityScope(null).loadRecentSearches(), [
      'legacy guest search',
    ]);
  });

  test(
    'personal collections, selections and ballot caches isolate each scope',
    () async {
      final scopes = [null, 'stable-a', 'stable-b'];
      for (final id in scopes) {
        final prefs = PreferencesService(identityUserId: id);
        final label = id ?? 'guest';
        await prefs.saveFavoriteGames([
          FavoriteGameRecord(gameSlug: label, createdAt: DateTime.utc(2026)),
        ]);
        await prefs.saveRecentGames([
          RecentGameRecord(gameSlug: label, viewedAt: DateTime.utc(2026)),
        ]);
        await prefs.saveActivities([
          AppActivity(
            id: label,
            kind: AppActivityKind.info,
            title: label,
            message: label,
            createdAt: DateTime.utc(2026),
          ),
        ]);
        await prefs.saveDailyRecommendations([
          DailyRecommendationRecord(date: '2026-10-04', gameIds: [label]),
        ]);
        await prefs.saveSelectedConversationId(label);
        await prefs.saveNationalDayGameSlugs([label]);
        await prefs.saveGameVoteCache('vote-$label');
        await prefs.saveFavoriteRankingCache('favorite-$label');
        await prefs.drainPersonalWrites();
      }
      for (final id in scopes) {
        final prefs = PreferencesService(identityUserId: id);
        final label = id ?? 'guest';
        expect((await prefs.loadFavoriteGames()).single.gameSlug, label);
        expect((await prefs.loadRecentGames()).single.gameSlug, label);
        expect((await prefs.loadActivities()).single.id, label);
        expect((await prefs.loadDailyRecommendations()).single.gameIds, [
          label,
        ]);
        expect(await prefs.loadSelectedConversationId(), label);
        expect(await prefs.loadNationalDayGameSlugs(), [label]);
        expect(await prefs.loadGameVoteCache(), 'vote-$label');
        expect(await prefs.loadFavoriteRankingCache(), 'favorite-$label');
      }
    },
  );

  test('AI credentials and theme remain global', () async {
    final guest = PreferencesService();
    final a = guest.forIdentityScope('a');
    final config = AiApiConfig.defaultOpenAi.copyWith(model: 'gpt-5.6-luna');
    await guest.saveAiApiConfig(config);
    await guest.saveColorScheme(ColorSchemeOption.spatialCinema);
    expect((await a.loadAiApiConfig()).toJson(), config.toJson());
    expect(await a.loadColorScheme(), ColorSchemeOption.spatialCinema);
    await a.saveColorScheme(ColorSchemeOption.spatialCinema);
    expect(await guest.loadColorScheme(), ColorSchemeOption.spatialCinema);
  });

  for (final browser in [false, true]) {
    test(
      '${browser ? 'browser' : 'native'} conversation snapshots isolate accounts and retain guest path',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'identity-scope-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final guest = ConversationStore(
          directory: directory,
          browserStorage: browser,
        );
        final a = guest.forIdentityScope('../a/测试');
        final b = guest.forIdentityScope('b');
        await guest.save('{"guest":true}');
        expect(await a.load(), isNull);
        await a.save('{"account":"a"}');
        await b.save('{"account":"b"}');
        await a.save('{"account":"a-updated"}');
        expect(await guest.load(), '{"guest":true}');
        expect(await a.load(), '{"account":"a-updated"}');
        expect(await b.load(), '{"account":"b"}');
        if (!browser) {
          expect(
            await File(
              '${directory.path}/chat_conversations.json',
            ).readAsString(),
            '{"guest":true}',
          );
          final accountFolders = await Directory(
            '${directory.path}/personal_v1',
          ).list().toList();
          expect(accountFolders, hasLength(2));
          for (final folder in accountFolders) {
            expect(
              folder.uri.pathSegments.where((s) => s.isNotEmpty).last,
              matches(RegExp(r'^[a-f0-9]{64}$')),
            );
          }
        }
      },
    );
  }

  test('scope rejects empty IDs and preserves exact stable identity', () {
    expect(() => PreferencesService(identityUserId: '  '), throwsArgumentError);
    expect(
      PreferencesService.identityStorageId('A'),
      isNot(PreferencesService.identityStorageId('a')),
    );
    expect(
      PreferencesService.identityStorageId(' a'),
      isNot(PreferencesService.identityStorageId('a')),
    );
  });

  test(
    'controller switches guest A B guest without adopting personal data',
    () async {
      final app = await _app(ai: _RecordingAi());
      await app.saveAiApiConfig(
        app.aiApiConfig.copyWith(model: 'gpt-5.6-luna'),
      );
      app.openGlobalAssistant();
      await app.sendPrompt('guest question', useGlobalMode: true);
      await app.recordSearch('guest search');
      await app.recordRecentlyViewed(app.games.first);
      await app.toggleFavorite(app.games.first);
      final guestConversation = app.selectedConversationId;
      app.setAiRunExpandedForContext(useGlobalMode: true, expanded: true);
      await app.switchIdentityScope('a');
      expect(app.identityUserId, 'a');
      expect(app.favoriteCount, 0);
      expect(app.searchHistory, isEmpty);
      expect(app.recentGameRecords, isEmpty);
      expect(app.activities, isEmpty);
      expect(app.conversations, isEmpty);
      expect(app.selectedConversationId, isNull);
      expect(app.aiRunExpandedForContext(useGlobalMode: true), isNull);
      expect(app.aiRunEventsForContext(useGlobalMode: true), isEmpty);
      await app.recordSearch('a search');
      await app.createConversation(useGlobalMode: true);
      await app.sendPrompt('account A question', useGlobalMode: true);
      final aConversation = app.selectedConversationId;
      await app.switchIdentityScope('b');
      expect(app.searchHistory, isEmpty);
      expect(app.conversations, isEmpty);
      await app.recordSearch('b search');
      await app.switchIdentityScope('a');
      expect(app.searchHistory.single.query, 'a search');
      expect(app.selectedConversationId, aConversation);
      await app.switchIdentityScope(null);
      expect(app.favoriteCount, 1);
      expect(app.searchHistory.single.query, 'guest search');
      expect(app.recentGameRecords, hasLength(1));
      expect(app.selectedConversationId, guestConversation);
    },
  );

  test(
    'transition drains a queued personal write and rejects new mutations',
    () async {
      final prefs = _HeldPreferences();
      final app = await _app(preferences: prefs);
      final write = app.recordSearch('old guest write');
      await prefs.started.future;
      final switchScope = app.switchIdentityScope('a');
      expect(app.isSwitchingIdentityScope, isTrue);
      expect(await app.recordSearch('during transition'), isFalse);
      expect(await app.toggleFavorite(app.games.first), isFalse);
      prefs.release.complete();
      expect(await write, isTrue);
      await switchScope;
      expect(app.searchHistory, isEmpty);
      expect(await PreferencesService().loadRecentSearches(), [
        'old guest write',
      ]);
      expect(
        await PreferencesService(identityUserId: 'a').loadRecentSearches(),
        isEmpty,
      );
    },
  );

  test(
    'cancel abort-ignoring stream and buffered delta before next account',
    () async {
      final ai = _StreamingAi();
      final app = await _app(ai: ai);
      await app.saveAiApiConfig(
        app.aiApiConfig.copyWith(model: 'gpt-5.6-luna'),
      );
      app.openGlobalAssistant();
      final send = app.sendPrompt('guest question', useGlobalMode: true);
      await ai.started.future;
      ai.events.add(const BoardGameAiStreamEvent(delta: 'old buffered delta'));
      await Future<void>.delayed(Duration.zero);
      await app.switchIdentityScope('a');
      await send;
      expect(ai.aborted, isTrue);
      ai.events.add(const BoardGameAiStreamEvent(delta: 'late old output'));
      await ai.events.close();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(app.conversations, isEmpty);
      expect(app.activities, isEmpty);
      expect(app.aiRunEventsForContext(useGlobalMode: true), isEmpty);
      expect(
        await ConversationStore(
          browserStorage: true,
          identityUserId: 'a',
        ).load(),
        isNull,
      );
    },
  );

  test(
    'speech callbacks from an old account cannot update the next account',
    () async {
      final speech = _Speech();
      final app = await _app(speech: speech);
      final recognized = <String>[];
      await app.startListening(onRecognizedText: recognized.add);
      speech.result!('guest words');
      expect(recognized, ['guest words']);
      await app.switchIdentityScope('a');
      speech.result!('stale words');
      speech.level!(12);
      expect(recognized, ['guest words']);
      expect(app.isListening, isFalse);
      expect(app.speechLevel, 0);
      expect(speech.cancels, greaterThanOrEqualTo(2));
    },
  );

  test(
    'identity transition still drains delayed provider cancellation before reloading',
    () async {
      final cleanup = Completer<void>();
      var cancellations = 0;
      final ai = _StreamingAi(
        onCancel: () {
          cancellations++;
          return cleanup.future;
        },
      );
      final app = await _app(ai: ai);
      await app.saveAiApiConfig(
        app.aiApiConfig.copyWith(model: 'gpt-5.6-luna'),
      );
      final response = app.sendPrompt(
        'guest pending cleanup',
        useGlobalMode: true,
      );
      await ai.started.future;
      var switched = false;
      final transition = app
          .switchIdentityScope('a')
          .then((_) => switched = true);
      await response;
      await Future<void>.delayed(Duration.zero);
      expect(cancellations, 1);
      expect(switched, isFalse);
      expect(app.identityUserId, isNull);
      expect(app.isSwitchingIdentityScope, isTrue);
      expect(await app.recordSearch('blocked during cleanup'), isFalse);
      cleanup.complete();
      await transition;
      expect(app.identityUserId, 'a');
      expect(app.conversations, isEmpty);
      expect(app.searchHistory, isEmpty);
      expect(app.isSwitchingIdentityScope, isFalse);
    },
  );

  test(
    'account ballots stay local and guest remote provider returns on logout',
    () async {
      final prefs = PreferencesService();
      var remoteRequests = 0;
      final votes = GameVoteService(
        preferences: prefs,
        remoteProvider: () {
          remoteRequests++;
          return null;
        },
      );
      final app = await _app(
        preferences: prefs,
        votes: votes,
        favoriteProvider: () {
          remoteRequests++;
          return null;
        },
      );
      await app.switchIdentityScope('a');
      expect(app.anonymousReactionPublishingEnabled, isFalse);
      expect(app.identityReactionSyncNotice, isNotNull);
      await app.gameVotes.load();
      final game = app.games.first;
      await app.gameVotes.toggle(game.slug);
      await app.gameVotes.sync();
      await app.toggleFavorite(game);
      await app.favoriteStatistics.sync();
      expect(app.gameVotes.status, GameVoteSyncStatus.localOnly);
      expect(app.favoriteStatistics.status, GameVoteSyncStatus.localOnly);
      expect(remoteRequests, 0);
      await app.switchIdentityScope('b');
      await app.gameVotes.load();
      expect(app.gameVotes.hasVoted(game.slug), isFalse);
      expect(app.favoriteCount, 0);
      await app.switchIdentityScope(null);
      await app.gameVotes.sync();
      expect(app.gameVotes.hasVoted(game.slug), isFalse);
      expect(app.anonymousReactionPublishingEnabled, isTrue);
      expect(remoteRequests, greaterThan(0));
    },
  );

  test(
    'concurrent transitions serialize and end in the requested final scope',
    () async {
      final app = await _app();
      await Future.wait([
        app.switchIdentityScope('a'),
        app.switchIdentityScope('b'),
      ]);
      expect(app.identityUserId, 'b');
      expect(app.isSwitchingIdentityScope, isFalse);
    },
  );

  test(
    'local answer failure blocks update and reload, then a retry survives reconstruction',
    () async {
      final faults = _StoreFaults();
      final ai = _SavingAi(onStart: () => faults.failWrites = true);
      final app = await _app(store: _FaultStore(faults), ai: ai);
      addTearDown(() => faults.failWrites = false);
      app.openGlobalAssistant();
      await app.saveAiApiConfig(
        app.aiApiConfig.copyWith(model: 'gpt-5.6-luna'),
      );
      await app.sendPrompt('必须留存的提问', useGlobalMode: true);
      expect(ai.calls, 1);
      await expectLater(
        app.prepareForAppUpdate(),
        throwsA(isA<ConversationSaveException>()),
      );
      expect(app.hasUnsavedConversations, isTrue);
      expect(app.conversationSaveError, isNotNull);
      final before = app
          .messagesForContext(useGlobalMode: true)
          .map((message) => message.text)
          .toList();
      expect(await app.reloadServicePersonalState(), isFalse);
      expect(
        app
            .messagesForContext(useGlobalMode: true)
            .map((message) => message.text)
            .toList(),
        before,
      );
      faults.failWrites = false;
      await app.prepareForAppUpdate();
      expect(app.hasUnsavedConversations, isFalse);
      expect(app.conversationSaveError, isNull);
      expect(faults.snapshots[null], contains('已保存的回答'));
      final restored = await _app(store: _FaultStore(faults));
      await restored.initialize();
      expect(
        restored
            .messagesForContext(useGlobalMode: true)
            .map((message) => message.text),
        containsAll(['必须留存的提问', '已保存的回答']),
      );
    },
  );

  test(
    'failed user commit never starts a model and remains recoverable',
    () async {
      final faults = _StoreFaults()..failWrites = true;
      final ai = _SavingAi();
      final app = await _app(store: _FaultStore(faults), ai: ai);
      addTearDown(() => faults.failWrites = false);
      app.openGlobalAssistant();
      await app.saveAiApiConfig(
        app.aiApiConfig.copyWith(model: 'gpt-5.6-luna'),
      );
      await app.sendPrompt('尚未提交的问题', useGlobalMode: true);
      expect(ai.calls, 0);
      expect(app.messagesForContext(useGlobalMode: true).first.text, '尚未提交的问题');
      expect(
        app.messagesForContext(useGlobalMode: true).last.text,
        contains('未发送给模型'),
      );
      await expectLater(
        app.prepareForAppUpdate(),
        throwsA(isA<ConversationSaveException>()),
      );
      faults.failWrites = false;
      await app.retryMessage(
        app.messagesForContext(useGlobalMode: true).last,
        useGlobalMode: true,
      );
      await app.prepareForAppUpdate();
      expect(ai.calls, 1);
      expect(
        app
            .messagesForContext(useGlobalMode: true)
            .where((message) => message.role == ChatRole.user),
        hasLength(1),
      );
      expect(app.conversationSaveError, isNull);
    },
  );

  test(
    'model invocation waits for acknowledgement of the durable user input',
    () async {
      final store = _HeldConversationStore();
      final ai = _SavingAi(
        onStart: () => expect(store.value, contains('先本机提交')),
      );
      final app = await _app(store: store, ai: ai);
      app.openGlobalAssistant();
      await app.saveAiApiConfig(
        app.aiApiConfig.copyWith(model: 'gpt-5.6-luna'),
      );
      final send = app.sendPrompt('先本机提交', useGlobalMode: true);
      await store.started.future;
      expect(ai.calls, 0);
      await expectLater(app.prepareForAppUpdate(), throwsStateError);
      store.release.complete();
      await send;
      expect(ai.calls, 1);
      await app.prepareForAppUpdate();
    },
  );

  test(
    'real SQLite rollback blocks update, and pending offline uploads do not block retry',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'board-durability-test-',
      );
      final db = PowerSyncDatabase(
        schema: boardPersonalSchema,
        path: '${directory.path}/personal.sqlite',
      );
      await db.initialize();
      final store = BoardPersonalStore(
        database: db,
        datasetId: 'personal-board-test',
      );
      addTearDown(() async {
        await store.close();
        await directory.delete(recursive: true);
      });
      final ai = _SavingAi(
        onStart: () async {
          expect(
            (await store.records(
              'messages',
            )).where((row) => row['role'] == 'user'),
            hasLength(1),
          );
          await db.execute(
            "CREATE TRIGGER fail_answer_write INSTEAD OF INSERT ON messages WHEN NEW.role = 'assistant' AND NEW.content <> '' BEGIN SELECT RAISE(ABORT, 'injected local rollback'); END",
          );
        },
      );
      final app = await _app(ai: ai);
      await app.switchIdentityScope('sqlite-user', personalStore: store);
      app.openGlobalAssistant();
      await app.saveAiApiConfig(
        app.aiApiConfig.copyWith(model: 'gpt-5.6-luna'),
      );
      await app.sendPrompt('真实事务提问', useGlobalMode: true);
      await expectLater(
        app.prepareForAppUpdate(),
        throwsA(isA<ConversationSaveException>()),
      );
      expect(
        (await store.records('messages')).map((row) => row['content']),
        isNot(contains('已保存的回答')),
      );
      await db.execute('DROP TRIGGER fail_answer_write');
      await app.retryConversationSave();
      await app.prepareForAppUpdate();
      expect(
        (await store.records('messages')).map((row) => row['content']),
        contains('已保存的回答'),
      );
      expect(
        await db.getCrudBatch(),
        isNotNull,
      ); // no network/upload acknowledgement
      final restored = await _app();
      await restored.switchIdentityScope('sqlite-user', personalStore: store);
      expect(
        restored
            .messagesForContext(useGlobalMode: true)
            .map((message) => message.text),
        containsAll(['真实事务提问', '已保存的回答']),
      );
    },
  );

  test(
    'oversized UTF-8 and invalid input are rejected before SQLite or a model request',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'board-input-validation-test-',
      );
      final db = PowerSyncDatabase(
        schema: boardPersonalSchema,
        path: '${directory.path}/personal.sqlite',
      );
      await db.initialize();
      final store = BoardPersonalStore(
        database: db,
        datasetId: 'personal-board-test',
      );
      addTearDown(() async {
        await store.close();
        await directory.delete(recursive: true);
      });
      final ai = _SavingAi();
      final app = await _app(ai: ai);
      await app.switchIdentityScope('sqlite-user', personalStore: store);
      app.openGlobalAssistant();
      await app.saveAiApiConfig(
        app.aiApiConfig.copyWith(model: 'gpt-5.6-luna'),
      );
      for (final prompt in ['x' * 500000, '中' * 170000, 'invalid\u0000text']) {
        expect(await app.sendPrompt(prompt, useGlobalMode: true), isFalse);
        expect(app.lastPromptSaveError, isNotNull);
      }
      expect(ai.calls, 0);
      expect(app.messagesForContext(useGlobalMode: true), isEmpty);
      expect(await store.records('messages'), isEmpty);
      await app.sendPrompt('可以正常保存', useGlobalMode: true);
      await app.prepareForAppUpdate();
      expect(ai.calls, 1);
      expect(app.lastPromptSaveError, isNull);
    },
  );

  test(
    'service disposal reports local durability failure and still releases AI',
    () async {
      final faults = _StoreFaults();
      final ai = _SavingAi(onStart: () => faults.failWrites = true);
      final app = await _app(store: _FaultStore(faults), ai: ai);
      addTearDown(() => faults.failWrites = false);
      app.openGlobalAssistant();
      await app.saveAiApiConfig(
        app.aiApiConfig.copyWith(model: 'gpt-5.6-luna'),
      );
      await app.sendPrompt('退出前尚未保存', useGlobalMode: true);
      await expectLater(
        app.disposeServices(),
        throwsA(isA<ConversationSaveException>()),
      );
      expect(ai.disposed, isTrue);
      faults.failWrites = false;
      await app.retryConversationSave();
      expect(faults.snapshots[null], contains('已保存的回答'));
    },
  );

  test(
    'failed conversation drain keeps old scope locked and supports retry',
    () async {
      final faults = _StoreFaults()..failWrites = true;
      final app = await _app(store: _FaultStore(faults), ai: _RecordingAi());
      app.openGlobalAssistant();
      await app.saveAiApiConfig(
        app.aiApiConfig.copyWith(model: 'gpt-5.6-luna'),
      );
      await app.sendPrompt('必须保存的真实提问', useGlobalMode: true);
      await expectLater(app.switchIdentityScope('a'), throwsStateError);
      expect(app.identityUserId, isNull);
      expect(app.isSwitchingIdentityScope, isTrue);
      expect(await app.recordSearch('blocked'), isFalse);
      faults.failWrites = false;
      await app.switchIdentityScope('a');
      expect(app.identityUserId, 'a');
      expect(app.isSwitchingIdentityScope, isFalse);
      expect(faults.snapshots[null], contains('global'));
      expect(app.conversations, isEmpty);
    },
  );

  test(
    'failed target reload clears old personal state and supports another scope',
    () async {
      final faults = _StoreFaults()..failReadScope = 'a';
      final app = await _app(store: _FaultStore(faults));
      await app.recordSearch('guest secret');
      app.openGlobalAssistant();
      await expectLater(app.switchIdentityScope('a'), throwsStateError);
      expect(app.isSwitchingIdentityScope, isTrue);
      expect(app.searchHistory, isEmpty);
      expect(app.conversations, isEmpty);
      expect(app.selectedConversationId, isNull);
      await app.switchIdentityScope('b');
      expect(app.identityUserId, 'b');
      expect(app.isSwitchingIdentityScope, isFalse);
      expect(app.searchHistory, isEmpty);
    },
  );

  test(
    'provider session identifiers cannot reuse another account context',
    () async {
      final ai = _RecordingAi();
      final app = await _app(ai: ai);
      await app.saveAiApiConfig(
        app.aiApiConfig.copyWith(model: 'gpt-5.6-luna'),
      );
      await app.switchIdentityScope('a');
      await app.sendPrompt('A question', useGlobalMode: true);
      await app.switchIdentityScope('b');
      await app.sendPrompt('B question', useGlobalMode: true);
      await app.switchIdentityScope(null);
      await app.sendPrompt('guest question', useGlobalMode: true);
      expect(ai.ids.toSet(), hasLength(3));
      expect(
        ai.ids[0],
        'conversation:personal_v1:${PreferencesService.identityStorageId('a')}:global',
      );
      expect(
        ai.ids[1],
        'conversation:personal_v1:${PreferencesService.identityStorageId('b')}:global',
      );
      expect(ai.ids[2], 'global');
    },
  );

  test(
    'real Responses workflow isolates compaction and persisted telemetry by scope',
    () async {
      final client = _ResponsesClient();
      final telemetry = InMemoryAiRunTelemetrySink();
      final workflow = ResponsesRulesWorkflow(
        responsesClient: client,
        telemetrySink: telemetry,
      );
      final app = await _app(ai: _WorkflowAi(workflow));
      await app.saveAiApiConfig(
        app.aiApiConfig.copyWith(model: 'gpt-5.6-luna'),
      );
      await app.sendPrompt('你好', useGlobalMode: true);
      await app.switchIdentityScope('a');
      await app.sendPrompt('你好', useGlobalMode: true);
      await app.switchIdentityScope('b');
      await app.sendPrompt('你好', useGlobalMode: true);
      await app.switchIdentityScope('a');
      await app.sendPrompt('你好', useGlobalMode: true);
      expect(client.requests, hasLength(4));
      for (final request in client.requests.take(3)) {
        expect(
          request.input.whereType<ResponsesRawInput>().where(
            (item) => item.value['type'] == 'compaction',
          ),
          isEmpty,
        );
      }
      expect(
        client.requests.last.input
            .whereType<ResponsesRawInput>()
            .where((item) => item.value['type'] == 'compaction')
            .single
            .value['id'],
        'cmp-2',
      );
      expect(telemetry.recent, hasLength(4));
      expect(telemetry.recent[0].contextKey, startsWith('global|'));
      expect(
        telemetry.recent[1].contextKey,
        startsWith(
          'conversation:personal_v1:${PreferencesService.identityStorageId('a')}:global|',
        ),
      );
      expect(
        telemetry.recent[2].contextKey,
        startsWith(
          'conversation:personal_v1:${PreferencesService.identityStorageId('b')}:global|',
        ),
      );
      expect(telemetry.recent[3].contextKey, telemetry.recent[1].contextKey);
      final ledger = SharedPreferencesAiRunTelemetrySink();
      await Future.wait(telemetry.recent.map(ledger.record));
      expect(
        (await ledger.load()).single['contextKey'],
        telemetry.recent[0].contextKey,
      );
      final aLedger = await ledger.load(identityUserId: 'a');
      final bLedger = await ledger.load(identityUserId: 'b');
      expect(aLedger, hasLength(2));
      expect(
        aLedger.every(
          (entry) => entry['contextKey'] == telemetry.recent[1].contextKey,
        ),
        isTrue,
      );
      expect(bLedger.single['contextKey'], telemetry.recent[2].contextKey);
    },
  );

  test(
    'seasonal list services reset without reusing another account list',
    () async {
      final app = await _app();
      await app.nationalDayList.load();
      await app.nationalDayList.save([app.games.first.slug]);
      await app.switchIdentityScope('a');
      await app.nationalDayList.load();
      expect(app.nationalDayList.slugs, hasLength(3));
      await app.switchIdentityScope(null);
      await app.nationalDayList.load();
      expect(app.nationalDayList.slugs, [app.games.first.slug]);
    },
  );
}

Future<AppController> _app({
  PreferencesService? preferences,
  AiService? ai,
  _Speech? speech,
  GameVoteService? votes,
  ConversationStore? store,
  RemoteGameVoteStore? Function()? favoriteProvider,
}) async {
  final app = AppController(
    preferencesService: preferences ?? PreferencesService(),
    aiService: ai ?? _UnusedAi(),
    gameManifestService: FixtureGameManifestService(),
    remoteAssetService: _NoNetwork(),
    speechService: speech ?? _Speech(),
    ttsService: _Tts(),
    conversationStore: store ?? const ConversationStore(browserStorage: true),
    gameVotes: votes,
    favoriteRemoteProvider: favoriteProvider,
  );
  addTearDown(() async {
    await app.disposeServices();
    app.dispose();
  });
  await app.reloadGames();
  return app;
}

class _HeldPreferences extends PreferencesService {
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> saveSearchHistory(records) async {
    started.complete();
    await release.future;
    await super.saveSearchHistory(records);
  }
}

class _UnusedAi extends Fake implements AiService {
  @override
  void dispose() {}
}

class _StreamingAi extends _UnusedAi {
  _StreamingAi({FutureOr<void> Function()? onCancel})
    : events = StreamController<BoardGameAiStreamEvent>(onCancel: onCancel);
  final StreamController<BoardGameAiStreamEvent> events;
  final started = Completer<void>();
  bool aborted = false;
  @override
  Stream<BoardGameAiStreamEvent> streamReply({
    required String prompt,
    required AppLanguage language,
    required GameInfo game,
    required AiAnswerMode answerMode,
    required bool useGlobalMode,
    required AiApiConfig config,
    required List<AssetSourceConfig> assetSourceConfigs,
    required RemoteAssetService remoteAssetService,
    required List<ChatMessage> conversationHistory,
    String? conversationId,
    bool useCurrentGameKnowledge = false,
    Future<void>? abortTrigger,
  }) {
    started.complete();
    abortTrigger?.then((_) => aborted = true);
    return events.stream;
  }
}

class _RecordingAi extends _UnusedAi {
  final ids = <String?>[];
  @override
  Stream<BoardGameAiStreamEvent> streamReply({
    required String prompt,
    required AppLanguage language,
    required GameInfo game,
    required AiAnswerMode answerMode,
    required bool useGlobalMode,
    required AiApiConfig config,
    required List<AssetSourceConfig> assetSourceConfigs,
    required RemoteAssetService remoteAssetService,
    required List<ChatMessage> conversationHistory,
    String? conversationId,
    bool useCurrentGameKnowledge = false,
    Future<void>? abortTrigger,
  }) {
    ids.add(conversationId);
    return const Stream<BoardGameAiStreamEvent>.empty();
  }
}

class _ResponsesClient implements ResponsesAiClient {
  final requests = <ResponsesRequest>[];
  @override
  Future<ResponsesResponse> complete(
    ResponsesRequest request, {
    Future<void>? abortTrigger,
  }) async {
    requests.add(request);
    return ResponsesResponse(
      text: '你好',
      model: 'gpt-5.6-luna',
      outputItems: [
        ResponsesRawInput({
          'type': 'compaction',
          'id': 'cmp-${requests.length}',
          'encrypted_content': 'opaque-${requests.length}',
        }),
      ],
    );
  }

  @override
  Stream<ResponsesStreamEvent> stream(
    ResponsesRequest request, {
    Future<void>? abortTrigger,
  }) async* {
    yield ResponsesStreamEvent.completed(await complete(request));
  }

  @override
  void close() {}
}

class _WorkflowAi extends _UnusedAi {
  _WorkflowAi(this.workflow);
  final ResponsesRulesWorkflow workflow;
  @override
  void dispose() => workflow.close();
  @override
  Stream<BoardGameAiStreamEvent> streamReply({
    required String prompt,
    required AppLanguage language,
    required GameInfo game,
    required AiAnswerMode answerMode,
    required bool useGlobalMode,
    required AiApiConfig config,
    required List<AssetSourceConfig> assetSourceConfigs,
    required RemoteAssetService remoteAssetService,
    required List<ChatMessage> conversationHistory,
    String? conversationId,
    bool useCurrentGameKnowledge = false,
    Future<void>? abortTrigger,
  }) => workflow.streamReply(
    prompt: prompt,
    language: language,
    game: game,
    answerMode: answerMode,
    useGlobalMode: useGlobalMode,
    config: config,
    assetSourceConfigs: assetSourceConfigs,
    remoteAssetService: remoteAssetService,
    conversationHistory: conversationHistory,
    conversationId: conversationId,
    useCurrentGameKnowledge: useCurrentGameKnowledge,
    abortTrigger: abortTrigger,
  );
}

class _StoreFaults {
  bool failWrites = false;
  String? failReadScope;
  final snapshots = <String?, String>{};
}

class _FaultStore extends ConversationStore {
  _FaultStore(this.faults, {super.identityUserId});
  final _StoreFaults faults;
  @override
  ConversationStore forIdentityScope(
    String? userId, {
    BoardPersonalStore? store,
  }) => _FaultStore(faults, identityUserId: userId);
  @override
  Future<String?> load() async {
    if (identityUserId != null && identityUserId == faults.failReadScope) {
      throw StateError('injected read failure');
    }
    return faults.snapshots[identityUserId];
  }

  @override
  Future<void> save(String payload) async {
    if (faults.failWrites) throw StateError('injected write failure');
    faults.snapshots[identityUserId] = payload;
  }
}

class _Speech extends SpeechService {
  ValueChanged<String>? result;
  ValueChanged<double>? level;
  int cancels = 0;
  @override
  Future<bool> reinitialize({VoidCallback? onListeningStopped}) async => true;
  @override
  Future<bool> startListening({
    required AppLanguage language,
    required ValueChanged<String> onResult,
    required VoidCallback onListeningStopped,
    ValueChanged<double>? onSoundLevel,
  }) async {
    result = onResult;
    level = onSoundLevel;
    return true;
  }

  @override
  Future<void> cancelListening() async {
    cancels++;
  }
}

class _Tts extends TtsService {
  @override
  bool get isAvailable => false;
  @override
  Future<void> stop() async {}
}

class _NoNetwork extends RemoteAssetService {
  @override
  Future<File?> cachedFileFor(String path) async => null;
  @override
  Future<CachedAsset?> ensureCached({
    required List<AssetSourceConfig> sources,
    required String remotePath,
    bool forceRefresh = false,
    bool allowCachedFallback = true,
  }) async => null;
  @override
  Future<String?> fetchRemoteText({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) async => null;
}

class _HeldConversationStore extends ConversationStore {
  final started = Completer<void>();
  final release = Completer<void>();
  String? value;
  @override
  ConversationStore forIdentityScope(
    String? userId, {
    BoardPersonalStore? store,
  }) => this;
  @override
  Future<String?> load() async => value;
  @override
  Future<void> save(String payload) async {
    if (!started.isCompleted) started.complete();
    await release.future;
    value = payload;
  }
}

class _SavingAi extends _UnusedAi {
  _SavingAi({this.onStart});
  final FutureOr<void> Function()? onStart;
  int calls = 0;
  bool disposed = false;
  @override
  Stream<BoardGameAiStreamEvent> streamReply({
    required String prompt,
    required AppLanguage language,
    required GameInfo game,
    required AiAnswerMode answerMode,
    required bool useGlobalMode,
    required AiApiConfig config,
    required List<AssetSourceConfig> assetSourceConfigs,
    required RemoteAssetService remoteAssetService,
    required List<ChatMessage> conversationHistory,
    String? conversationId,
    bool useCurrentGameKnowledge = false,
    Future<void>? abortTrigger,
  }) async* {
    calls++;
    await onStart?.call();
    yield BoardGameAiStreamEvent(
      answer: BoardGameAiAnswer(
        text: '已保存的回答',
        source: AnswerSource.generalAdvice,
      ),
      isDone: true,
    );
  }

  @override
  void dispose() => disposed = true;
}
