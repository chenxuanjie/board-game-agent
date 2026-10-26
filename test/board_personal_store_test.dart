import 'dart:convert';
import 'dart:io';
import 'package:app_client/app_client.dart';
import 'package:board_game_agent/features/identity/services/board_personal_store.dart';
import 'package:board_game_agent/features/settings/services/preferences_service.dart';
import 'package:board_game_agent/features/games/models/favorite_game_record.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:powersync/powersync.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late BoardPersonalStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('board-personal-test-');
    final db = PowerSyncDatabase(
      schema: boardPersonalSchema,
      path: '${directory.path}/personal.sqlite',
    );
    await db.initialize();
    store = BoardPersonalStore(database: db, datasetId: 'personal-board-alice');
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  test(
    'new account starts empty; favorites persist directly in SDK database',
    () async {
      final prefs = PreferencesService(
        identityUserId: 'account-a',
        personalStore: store,
      );
      expect(await prefs.loadFavoriteGames(), isEmpty);
      await prefs.saveFavoriteGames([
        FavoriteGameRecord(gameSlug: 'cabo', createdAt: DateTime.utc(2026)),
      ]);
      expect((await prefs.loadFavoriteGames()).single.gameSlug, 'cabo');
      final row = (await store.records('favorites')).single;
      expect(row['id'], 'cabo');
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      await expectLater(
        store.setPreference('api_key', 'secret'),
        throwsArgumentError,
      );
    },
  );
  test(
    'chat round trip keeps local run and stable message identity, excludes run from upload',
    () async {
      await store.loadConversations();
      final data = {
        'conversations': {
          'conversation:one': {
            'id': 'conversation:one',
            'title': '规则',
            'scope': 'global',
            'opened': true,
            'createdAt': '2026-10-26T00:00:00Z',
            'updatedAt': '2026-10-26T00:01:00Z',
            'lastRun': {'private_checkpoint': 'local-only'},
            'messages': [
              {
                'id': 'm1',
                'role': 'assistant',
                'text': '规则回答',
                'timestamp': '2026-10-26T00:01:00Z',
                'state': 'complete',
              },
            ],
          },
        },
      };
      await store.saveConversations(jsonEncode(data));
      final first = jsonDecode(await store.loadConversations()) as Map;
      expect(
        first['conversations']['conversation:one']['messages'].single['id'],
        'm1',
      );
      await store.saveConversations(jsonEncode(first));
      expect(
        (await store.records('messages')).single['id'],
        'conversation:one|m1',
      );
      final queue = await store.database.getAll('SELECT data FROM ps_crud');
      expect(jsonEncode(queue), isNot(contains('local-only')));
      expect(
        first['conversations']['conversation:one']['lastRun']['private_checkpoint'],
        'local-only',
      );
    },
  );
  test('unseen remote rows survive a stale UI snapshot', () async {
    await store.loadCollection('favorites');
    // A row arrives after this UI loaded its empty snapshot.
    await store.database.execute(
      'INSERT INTO favorites(id,dataset_id,game_slug,created_at) VALUES(?,?,?,?)',
      ['remote', store.datasetId, 'remote', '2026-10-26T00:00:00Z'],
    );
    await store.saveCollection('favorites', []);
    expect((await store.records('favorites')).single['id'], 'remote');
  });
  test(
    'browser sync uses its fixed API proxy; native rejects a foreign sync origin',
    () async {
      AppJsonClient client({required bool browser}) => AppJsonClient(
        Uri.parse('https://site.test'),
        applicationId: 'board_game_agent',
        baseUri: browser ? Uri.parse('https://site.test/api/') : null,
        client: MockClient(
          (r) async => http.Response(
            jsonEncode({
              'user_id': 'alice',
              'app_id': 'board_game_agent',
              'token': 'sync-token',
              'endpoint': 'https://shared-api.test:18281/powersync',
            }),
            200,
          ),
        ),
      );
      final web = client(browser: true), native = client(browser: false);
      addTearDown(web.close);
      addTearDown(native.close);
      BoardSyncConnector connector(AppJsonClient api) => BoardSyncConnector(
        client: api,
        store: store,
        token: () async => 'app-token',
        active: () => true,
        userId: 'alice',
      );
      final credentials = await connector(web).fetchCredentials();
      expect(
        credentials!.endpointUri('sync/stream').toString(),
        'https://site.test/api/powersync/sync/stream',
      );
      await expectLater(connector(native).fetchCredentials(), throwsStateError);
    },
  );
  test(
    'local chat timestamps become aware UTC and invalid text never poisons the SDK queue',
    () async {
      await store.loadConversations();
      final local = DateTime(2026, 10, 26, 18, 30);
      await store.saveConversations(
        jsonEncode({
          'conversations': {
            'c': {
              'id': 'c',
              'title': 'Rules',
              'scope': 'global',
              'opened': true,
              'createdAt': local.toIso8601String(),
              'updatedAt': local.toIso8601String(),
              'messages': [
                {
                  'id': 'm',
                  'role': 'user',
                  'text': 'question',
                  'timestamp': local.toIso8601String(),
                },
              ],
            },
          },
        }),
      );
      expect(
        (await store.records('conversations')).single['created_at'],
        local.toUtc().toIso8601String(),
      );
      expect(
        (await store.records('messages')).single['created_at'],
        local.toUtc().toIso8601String(),
      );
      final before = (await store.database.getAll(
        'SELECT * FROM ps_crud',
      )).length;
      await expectLater(
        store.setPreference('nickname', 'bad\u0000name'),
        throwsFormatException,
      );
      expect(
        (await store.database.getAll('SELECT * FROM ps_crud')).length,
        before,
      );
    },
  );
  test(
    'oversized message rolls back the entire conversation transaction',
    () async {
      await store.loadConversations();
      await expectLater(
        store.saveConversations(
          jsonEncode({
            'conversations': {
              'c': {
                'id': 'c',
                'title': 'Rules',
                'scope': 'global',
                'opened': true,
                'createdAt': '2026-10-26T00:00:00Z',
                'updatedAt': '2026-10-26T00:00:00Z',
                'messages': [
                  {
                    'id': 'm',
                    'role': 'assistant',
                    'text': 'a' * (512 * 1024),
                    'timestamp': '2026-10-26T00:00:00Z',
                  },
                ],
              },
            },
          }),
        ),
        throwsStateError,
      );
      expect(await store.records('conversations'), isEmpty);
      expect(await store.database.getCrudBatch(), isNull);
    },
  );
  test(
    'lost upload acknowledgement reuses the durable mutation ID; account change retains queue',
    () async {
      await store.loadCollection('favorites');
      await store.saveCollection('favorites', [
        {
          'id': 'cabo',
          'game_slug': 'cabo',
          'created_at': '2026-10-26T00:00:00Z',
        },
      ]);
      final ids = <String>[];
      var lose = true, active = true;
      final client = AppJsonClient(
        Uri.parse('https://api.test'),
        applicationId: 'board_game_agent',
        client: MockClient((r) async {
          expect(r.url.path, '/v1/apps/board_game_agent/sync/upload');
          expect(r.headers['Authorization'], 'Bearer app-token');
          final mutation = (jsonDecode(r.body)['mutations'] as List).single;
          ids.add(mutation['id'] as String);
          if (lose) {
            lose = false;
            throw http.ClientException('response lost');
          }
          return http.Response(
            jsonEncode({
              'results': [
                {'id': mutation['id'], 'status': 'applied'},
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(client.close);
      final connector = BoardSyncConnector(
        client: client,
        store: store,
        token: () async => 'app-token',
        active: () => active,
        userId: 'alice',
      );
      await expectLater(
        connector.uploadData(store.database),
        throwsA(isA<AppClientFailure>()),
      );
      expect(await store.database.getCrudBatch(), isNotNull);
      await connector.uploadData(store.database);
      expect(ids, [ids.first, ids.first]);
      expect(await store.database.getCrudBatch(), isNull);
      await store.setPreference('nickname', 'Alice');
      active = false;
      await expectLater(connector.uploadData(store.database), throwsStateError);
      expect(await store.database.getCrudBatch(), isNotNull);
    },
  );
}
