import 'dart:async';
import 'dart:io';
import 'package:app_client/app_client.dart';
import 'package:board_game_agent/features/community/services/board_public_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:powersync/powersync.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<(PowerSyncDatabase, AppJsonClient)> fixture() async {
    final directory = await Directory.systemTemp.createTemp('board-public-');
    final db = PowerSyncDatabase(
      schema: boardPublicSchema,
      path: '${directory.path}/public.sqlite',
    );
    await db.initialize();
    addTearDown(() async {
      await db.close();
      await directory.delete(recursive: true);
    });
    final client = AppJsonClient(
      Uri.parse('https://api.test'),
      applicationId: 'board_game_agent',
      client: MockClient((_) async => http.Response('{}', 404)),
    );
    addTearDown(client.close);
    return (db, client);
  }

  test(
    'coalesces notifications and preserves changes arriving during a refresh',
    () async {
      final (db, client) = await fixture();
      final gate = Completer<void>();
      final batches = <(bool, Set<String>)>[];
      final sync = BoardPublicSync(
        database: db,
        client: client,
        active: () => true,
        refresh: (statistics, games) async {
          batches.add((statistics, games));
          if (batches.length == 1) await gate.future;
        },
      );
      sync.requestRefresh(statistics: false, games: ['cabo']);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      sync.requestRefresh(statistics: false, games: ['cabo']);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(batches.length, 1);
      expect(batches[0].$1, isFalse);
      expect(batches[0].$2, {'cabo'});
      sync.requestRefresh(games: ['harmonies']);
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(batches.length, 2);
      expect(batches[1].$1, isTrue);
      expect(batches[1].$2, {'harmonies'});
      await sync.setForeground(false);
      sync.requestRefresh(games: ['late']);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(batches.length, 2);
    },
  );

  test(
    'refresh failure has bounded retries and a new event can recover',
    () async {
      final (db, client) = await fixture();
      var fail = true, requests = 0;
      final sync = BoardPublicSync(
        database: db,
        client: client,
        active: () => true,
        refresh: (_, _) async {
          requests++;
          if (fail) throw StateError('offline');
        },
      );
      sync.requestRefresh(games: ['cabo']);
      final deadline = DateTime.now().add(const Duration(seconds: 40));
      while (requests < 6 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(requests, 6);
      expect(sync.error, isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(requests, 6);
      fail = false;
      sync.requestRefresh(games: ['cabo']);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(requests, 7);
      expect(sync.error, isNull);
    },
    timeout: const Timeout(Duration(seconds: 50)),
  );
}
