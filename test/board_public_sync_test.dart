import 'dart:async';
import 'dart:io';
import 'package:app_client/app_client.dart';
import 'package:board_game_agent/features/community/services/board_public_sync.dart';
import 'package:board_game_agent/features/community/services/public_publication.dart';
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
      final recoveryDeadline = DateTime.now().add(const Duration(seconds: 3));
      while ((requests < 7 || sync.error != null) &&
          DateTime.now().isBefore(recoveryDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(requests, 7);
      expect(sync.error, isNull);
    },
    timeout: const Timeout(Duration(seconds: 50)),
  );
  test(
    'publication watch catches cached and later rows, retaining events during refresh',
    () async {
      final (db, client) = await fixture();
      var active = true;
      final first = Completer<void>(), entered = Completer<void>();
      final batches = <List<PublicPublication>>[];
      await db.execute(
        'INSERT INTO publication_versions '
        '(id,app_id,topic,revision,channel,platform,architecture) '
        "VALUES ('catalog','board_game_agent','catalog',1,'','','')",
      );
      final sync = BoardPublicSync(
        database: db,
        client: client,
        active: () => active,
        httpClient: () => MockClient((_) async => http.Response('{}', 503)),
        refresh: (_, _) async => throw StateError('community unavailable'),
        refreshPublications: (rows) async {
          batches.add(rows);
          if (batches.length == 1) {
            entered.complete();
            await first.future;
          }
        },
      );
      await sync.start();
      await entered.future.timeout(const Duration(seconds: 5));
      await db.execute(
        "UPDATE publication_versions SET revision=2 WHERE id='catalog'",
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));
      first.complete();
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!batches.any((rows) => rows.any((r) => r.revision == 2)) &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(batches.any((rows) => rows.any((r) => r.revision == 1)), isTrue);
      expect(batches.any((rows) => rows.any((r) => r.revision == 2)), isTrue);
      await sync.setForeground(false);
      final before = batches.length;
      sync.requestPublicationRefresh();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(batches.length, before);
      await sync.setForeground(true);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(batches.length, greaterThan(before));
      active = false;
      await sync.close();
    },
  );
  test(
    'publication failures retry even when community data succeeds',
    () async {
      final (db, client) = await fixture();
      var requests = 0;
      final sync = BoardPublicSync(
        database: db,
        client: client,
        active: () => true,
        refresh: (_, _) async {},
        refreshPublications: (_) async {
          requests++;
          if (requests == 1) throw StateError('offline');
        },
      );
      sync.requestPublicationRefresh();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(requests, 1);
      expect(sync.error, isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 1150));
      expect(requests, 2);
      expect(sync.error, isNull);
      await sync.close();
    },
  );
}
