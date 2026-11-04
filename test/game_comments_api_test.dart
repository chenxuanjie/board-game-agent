import 'dart:async';
import 'dart:convert';
import 'package:app_client/app_client.dart';
import 'package:board_game_agent/features/community/services/game_comments_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/failing_preferences_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  AppJsonClient client(Future<http.Response> Function(http.Request) handler) =>
      AppJsonClient(
        Uri.parse('https://api.test'),
        applicationId: 'board_game_agent',
        client: MockClient(handler),
      );
  test('failed drafts retry actual content after scope invalidation', () async {
    final store = FailingPreferencesStore()..install();
    store.reject = (key) => key.contains('.draft.');
    var active = true;
    final api = client((_) async => throw StateError('No network expected'));
    addTearDown(api.close);
    final service = GameCommentsService(
      client: api,
      scope: 'alice',
      isActive: () => active,
      displayName: () => 'Alice',
    );
    addTearDown(service.dispose);
    await expectLater(
      service.saveDraft('cabo', null, {'text': '不能丢失的草稿'}),
      throwsStateError,
    );
    expect((await service.readDraft('cabo', null))!['text'], '不能丢失的草稿');
    active = false;
    for (var attempt = 0; attempt < 2; attempt++) {
      await expectLater(service.drain(), throwsStateError);
    }
    expect(await store.getAll(), isEmpty);
    store.reject = (_) => false;
    await service.drain();
    final saved = await store.getAll();
    expect(saved.values.single, contains('不能丢失的草稿'));
    final writes = store.attempts.length;
    await service.drain();
    expect(store.attempts, hasLength(writes));
    await expectLater(
      service.saveDraft('cabo', null, {'text': '迟到的旧页面'}),
      throwsStateError,
    );
    expect(await store.getAll(), saved);
  });

  test(
    'a successful unrelated write cannot hide another failed draft',
    () async {
      final store = FailingPreferencesStore()..install();
      store.reject = (key) => key.contains('.cabo.');
      store.throwOnRejection = false;
      final api = client((_) async => throw StateError('No network expected'));
      addTearDown(api.close);
      final service = GameCommentsService(
        client: api,
        scope: 'alice',
        isActive: () => true,
        displayName: () => '',
      );
      addTearDown(service.dispose);
      await expectLater(
        service.saveDraft('cabo', null, {'text': 'A'}),
        throwsStateError,
      );
      await service.saveDraft('scout', null, {'text': 'B'});
      await expectLater(service.drain(), throwsStateError);
      store.reject = (_) => false;
      await service.drain();
      expect(
        (await store.getAll()).values,
        containsAll(['{"text":"A"}', '{"text":"B"}']),
      );
      // A failed deletion is a pending tombstone, not an absent intent.
      store.reject = (_) => true;
      await expectLater(
        service.saveDraft('cabo', null, null),
        throwsStateError,
      );
      expect(await service.readDraft('cabo', null), isNull);
      await expectLater(service.drain(), throwsStateError);
      store.reject = (_) => false;
      await service.drain();
      expect((await store.getAll()).values, ['{"text":"B"}']);
    },
  );

  test(
    'handoff waits for accepted edits and saves the newest queued value',
    () async {
      final store = FailingPreferencesStore()..install();
      final entered = Completer<void>(), release = Completer<void>();
      store.beforeWrite = (_) async {
        if (!entered.isCompleted) {
          entered.complete();
          await release.future;
        }
      };
      var active = true;
      final api = client((_) async => throw StateError('No network expected'));
      addTearDown(api.close);
      final service = GameCommentsService(
        client: api,
        scope: 'old-account',
        isActive: () => active,
        displayName: () => '',
      );
      addTearDown(service.dispose);
      final first = service.saveDraft('cabo', null, {'text': 'first'});
      await entered.future;
      final last = service.saveDraft('cabo', null, {'text': 'latest'});
      await Future<void>.delayed(Duration.zero);
      active = false;
      var drained = false;
      final handoff = service.drain().then((_) => drained = true);
      await Future<void>.delayed(Duration.zero);
      expect(drained, isFalse);
      release.complete();
      await Future.wait([first, last, handoff]);
      final saved = await store.getAll();
      expect(saved.keys.single, contains('old-account.draft'));
      expect(saved.values.single, '{"text":"latest"}');
    },
  );
  test(
    'failed acknowledgement persistence retries locally without resending',
    () async {
      final store = FailingPreferencesStore()..install();
      var posts = 0;
      final api = client((request) async {
        posts++;
        final command = jsonDecode(request.body) as Map;
        store.reject = (_) => true;
        return http.Response(
          jsonEncode({'id': command['id'], 'status': 'applied'}),
          200,
        );
      });
      addTearDown(api.close);
      final service = GameCommentsService(
        client: api,
        scope: 'alice',
        uid: 'alice',
        token: () async => 'token',
        isActive: () => true,
        displayName: () => '',
      );
      addTearDown(service.dispose);
      final id = await service.publish(game: 'cabo', text: '本地持久命令');
      await service.synchronize();
      expect(service.pendingIds, contains(id));
      await expectLater(service.drain(), throwsStateError);
      store.reject = (_) => false;
      await service.drain();
      expect(posts, 1);
      final persisted =
          jsonDecode((await store.getAll()).values.single as String) as Map;
      expect((persisted['commands'] as List).single['id'], id);
    },
  );
  test(
    'updates during a read queue a fresh snapshot; watchers are reference counted',
    () async {
      final started = Completer<void>(), first = Completer<http.Response>();
      var reads = 0;
      final api = client((r) async {
        reads++;
        if (reads == 1) {
          started.complete();
          return first.future;
        }
        return http.Response(
          jsonEncode({'comments': [], 'next_cursor': null}),
          200,
        );
      });
      addTearDown(api.close);
      final service = GameCommentsService(
        client: api,
        scope: 'public',
        isActive: () => true,
        displayName: () => '',
      );
      addTearDown(service.dispose);
      service.watchGame('cabo');
      service.watchGame('cabo');
      final initial = service.synchronize();
      await started.future;
      final update = service.refreshGames(['cabo', 'unwatched']);
      expect(reads, 1);
      first.complete(
        http.Response(jsonEncode({'comments': [], 'next_cursor': null}), 200),
      );
      await Future.wait([initial, update]);
      expect(reads, 2);
      service.unwatchGame('cabo');
      await service.refreshGames(['cabo']);
      expect(reads, 3);
      service.unwatchGame('cabo');
      await service.refreshGames(['cabo']);
      expect(reads, 3);
      expect(service.watchedGames, isEmpty);
    },
  );
  test(
    'guests read public comments without identity; writes require login',
    () async {
      final api = client((r) async {
        expect(r.headers['Authorization'], isNull);
        expect(r.url.path, '/v1/apps/board_game_agent/community/comments/cabo');
        return http.Response(
          jsonEncode({'comments': [], 'next_cursor': null}),
          200,
        );
      });
      addTearDown(api.close);
      final service = GameCommentsService(
        client: api,
        scope: 'public',
        isActive: () => true,
        displayName: () => '',
      );
      addTearDown(service.dispose);
      service.watchGame('cabo');
      await service.synchronize();
      expect(service.error, isNull);
      expect(service.readOnly, isTrue);
      await expectLater(
        service.publish(game: 'cabo', text: 'text'),
        throwsStateError,
      );
    },
  );
  test(
    'lost response retains command across restart and retries same ID without claimed actor',
    () async {
      final id = GameCommentsService.newId();
      final seen = <String>[];
      var fail = true;
      final api = client((r) async {
        expect(r.headers['Authorization'], 'Bearer token');
        if (r.method == 'POST') {
          final command = jsonDecode(r.body) as Map;
          expect(command.keys, isNot(contains('user_id')));
          expect(command.keys, isNot(contains('uid')));
          seen.add(command['id'] as String);
          if (fail) throw http.ClientException('lost acknowledgement');
          return http.Response(
            jsonEncode({'id': command['id'], 'status': 'applied'}),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'comments': [
              {
                'id': id,
                'author_id': 'public-alice',
                'game_slug': 'cabo',
                'author': 'Alice',
                'text': 'Rules',
                'created_at': '2026-10-26T00:00:00Z',
                'deleted': false,
                'likes': 0,
                'liked_by_me': false,
              },
            ],
            'next_cursor': null,
          }),
          200,
        );
      });
      addTearDown(api.close);
      GameCommentsService create() => GameCommentsService(
        client: api,
        scope: 'alice',
        uid: 'public-alice',
        isActive: () => true,
        displayName: () => 'Alice',
        token: () async => 'token',
      );
      final first = create();
      await first.publish(game: 'cabo', text: 'Rules', operationId: id);
      await first.synchronize();
      expect(first.pendingIds, contains(id));
      first.dispose();
      fail = false;
      final restored = create();
      addTearDown(restored.dispose);
      restored.watchGame('cabo');
      await restored.synchronize();
      expect(seen, [id, id]);
      expect(restored.pending, isFalse);
      expect(restored.projection.comments[id]!.text, 'Rules');
    },
  );
  test(
    'late acknowledgement after scope change cannot clear the old account queue',
    () async {
      var active = true;
      final gate = Completer<http.Response>();
      final entered = Completer<void>();
      final api = client((r) async {
        entered.complete();
        return gate.future;
      });
      addTearDown(api.close);
      final service = GameCommentsService(
        client: api,
        scope: 'alice',
        uid: 'alice',
        isActive: () => active,
        displayName: () => 'Alice',
        token: () async => 'token',
      );
      addTearDown(service.dispose);
      final id = await service.publish(game: 'cabo', text: 'Draft');
      final work = service.synchronize();
      await entered.future;
      active = false;
      gate.complete(
        http.Response(jsonEncode({'id': id, 'status': 'applied'}), 200),
      );
      await work;
      expect(service.pendingIds, contains(id));
    },
  );
}
