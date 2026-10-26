// Invoked explicitly by app_data_service/tools/run_sync_probe.py. Never uses
// production accounts: tokens, databases and containers belong to that run.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:app_client/app_client.dart';
import 'package:board_game_agent/features/identity/services/board_personal_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:powersync/powersync.dart';

class _RealNetwork extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'actual SDK: two devices converge offline, isolate users and sync typed chat',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        const path = String.fromEnvironment('BOARD_PROBE_CONFIG');
        if (path.isEmpty) throw StateError('Use the isolated probe runner');
        final config = jsonDecode(await File(path).readAsString()) as Map;
        final root = Directory(config['directory'] as String);
        if (!root.path.contains('app-data-sync-probe-')) {
          throw StateError('Not an isolated probe');
        }
        final clients = <AppJsonClient>[];
        final stores = <BoardPersonalStore>[];
        Future<(BoardPersonalStore, BoardSyncConnector)> device(
          String id,
          String user,
        ) async {
          final db = PowerSyncDatabase(
            schema: boardPersonalSchema,
            path: '${root.path}/board-$id.sqlite',
          );
          await db.initialize();
          final store = BoardPersonalStore(
            database: db,
            datasetId: 'board-$user',
          );
          stores.add(store);
          final client = AppJsonClient(
            Uri.parse(config['api'] as String),
            applicationId: 'board_game_agent',
            client: http.Client(),
          );
          clients.add(client);
          final connector = BoardSyncConnector(
            client: client,
            store: store,
            active: () => true,
            token: () async => config['tokens'][user] as String,
            userId: user,
          );
          await store.connect(connector, httpClient: http.Client.new);
          await db.waitForFirstSync().timeout(const Duration(seconds: 35));
          return (store, connector);
        }

        Future<void> until(Future<bool> Function() condition) async {
          final deadline = DateTime.now().add(const Duration(seconds: 25));
          while (!await condition()) {
            if (DateTime.now().isAfter(deadline)) {
              throw TimeoutException('Convergence deadline');
            }
            await Future<void>.delayed(const Duration(milliseconds: 150));
          }
        }

        try {
          final (a, _) = await device('alice-1', 'alice');
          final (b, bc) = await device('alice-2', 'alice');
          final (other, _) = await device('bob', 'bob');
          await a.loadCollection('favorites');
          await a.saveCollection('favorites', [
            {
              'id': 'cabo',
              'game_slug': 'cabo',
              'created_at': '2026-10-26T00:00:00Z',
            },
          ]);
          await until(
            () async =>
                (await b.records('favorites')).any((r) => r['id'] == 'cabo'),
          );
          expect(await other.records('favorites'), isEmpty);
          await b.database.disconnect();
          final local = await b.loadCollection('favorites');
          await b.saveCollection('favorites', [
            ...local,
            {
              'id': 'harmonies',
              'game_slug': 'harmonies',
              'created_at': '2026-10-26T00:00:00Z',
            },
          ]);
          await b.setPreference('voice_reply_enabled', true);
          await a.setPreference('nickname', 'Alice');
          expect(
            (await a.records('favorites')).any((r) => r['id'] == 'harmonies'),
            isFalse,
          );
          await b.database.connect(connector: bc);
          await until(
            () async =>
                (await a.records('favorites')).length == 2 &&
                (await b.preferences())['nickname'] == 'Alice' &&
                (await a.preferences())['voice_reply_enabled'] == true,
          );
          await a.loadConversations();
          final localTimestamp = DateTime.now().toIso8601String();
          await a.saveConversations(
            jsonEncode({
              'conversations': {
                'conversation:probe': {
                  'id': 'conversation:probe',
                  'title': 'Rules',
                  'scope': 'global',
                  'opened': true,
                  'createdAt': localTimestamp,
                  'updatedAt': localTimestamp,
                  'lastRun': {'private': 'never-sync-this'},
                  'messages': [
                    {
                      'id': 'm1',
                      'role': 'assistant',
                      'text': 'Answer',
                      'state': 'complete',
                      'timestamp': localTimestamp,
                    },
                  ],
                },
              },
            }),
          );
          await until(() async => (await b.records('messages')).isNotEmpty);
          final chat = jsonDecode(await b.loadConversations()) as Map;
          expect(
            chat['conversations']['conversation:probe']['messages']
                .single['id'],
            'm1',
          );
          expect(
            chat['conversations']['conversation:probe'].containsKey('lastRun'),
            isFalse,
          );
          await a.loadCollection('favorites');
          await a.saveCollection('favorites', [
            {
              'id': 'harmonies',
              'game_slug': 'harmonies',
              'created_at': '2026-10-26T00:00:00Z',
            },
          ]);
          await until(() async => (await b.records('favorites')).length == 1);
          expect(await other.records('conversations'), isEmpty);
          expect(await other.records('preferences'), isEmpty);
          // ignore: avoid_print
          print('BOARD_LIVE_PROBE_PASSED');
        } finally {
          for (final store in stores) {
            await store.close();
          }
          for (final client in clients) {
            client.close();
          }
        }
      }, _RealNetwork());
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
