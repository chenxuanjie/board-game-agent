// Explicit local workload, excluded from the normal *_test.dart suite.
// flutter test --no-pub test/probes/personal_sync_profile.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:board_game_agent/features/identity/services/board_personal_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'profile invalidation versus full-row watching at 1000 chats / 100000 messages',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'personal-sync-profile-',
      );
      final db = PowerSyncDatabase(
        schema: boardPersonalSchema,
        path: '${directory.path}/profile.sqlite',
      );
      await db.initialize();
      final store = BoardPersonalStore(
        database: db,
        datasetId: 'synthetic-profile',
      );
      addTearDown(() async {
        await store.close();
        await directory.delete(recursive: true);
      });
      final body = 'x' * 256;
      await db.execute('''
WITH RECURSIVE seq(n) AS (SELECT 0 UNION ALL SELECT n+1 FROM seq WHERE n<999)
INSERT INTO conversations(id,dataset_id,title,scope,created_at,modified_at,opened,row_version)
SELECT 'c-'||n,'synthetic-profile','Chat '||n,'global','2026-11-03T00:00:00Z','2026-11-03T00:00:00Z',1,1 FROM seq
''');
      for (var batch = 0; batch < 100; batch++) {
        await db.execute(
          '''
WITH RECURSIVE seq(n) AS (SELECT ? UNION ALL SELECT n+1 FROM seq WHERE n<?)
INSERT INTO messages(id,dataset_id,conversation_id,role,content,created_at,state,source,citations,evidence,can_retry,row_version)
SELECT 'c-'||(n/100)||'|m-'||n,'synthetic-profile','c-'||(n/100),'assistant',?,
'2026-11-03T00:00:00Z','complete','generalAdvice','[]','[]',0,1 FROM seq
''',
          [batch * 1000, batch * 1000 + 999, body],
        );
        if ((batch + 1) % 25 == 0) {
          // ignore: avoid_print
          print('Seeded ${(batch + 1) * 1000} synthetic messages');
        }
      }

      final old = StreamIterator(
        db.watch('SELECT * FROM messages', throttle: null),
      );
      final fresh = StreamIterator(store.watchPersonalChanges());
      addTearDown(old.cancel);
      addTearDown(fresh.cancel);
      final initialTimer = Stopwatch()..start();
      expect(await old.moveNext(), isTrue);
      final oldInitialMs = initialTimer.elapsedMilliseconds;
      expect(old.current, hasLength(100000));
      final oldRowBytes = utf8
          .encode(
            jsonEncode(
              old.current.map((row) => Map<String, dynamic>.from(row)).toList(),
            ),
          )
          .length;
      final newInitialTimer = Stopwatch()..start();
      expect(await fresh.moveNext(), isTrue);
      final newInitialMs = newInitialTimer.elapsedMilliseconds;
      final headerTimer = Stopwatch()..start();
      final headers = await db.getAll(
        'SELECT id,conversation_id,row_version,updated_at,deleted_at FROM messages',
      );
      final headerMs = headerTimer.elapsedMilliseconds;
      expect(headers, hasLength(100000));

      final updateTimer = Stopwatch()..start();
      var oldUpdateMs = -1, newUpdateMs = -1;
      final nextOld = old.moveNext().then((received) {
        oldUpdateMs = updateTimer.elapsedMilliseconds;
        expect(received, isTrue);
      });
      final nextNew = fresh.moveNext().then((received) {
        newUpdateMs = updateTimer.elapsedMilliseconds;
        expect(received, isTrue);
      });
      await db.execute(
        'UPDATE messages SET content=?,row_version=2 WHERE id=?',
        ['y$body', 'c-0|m-0'],
      );
      await Future.wait([
        nextOld,
        nextNew,
      ]).timeout(const Duration(seconds: 30));
      expect(old.current, hasLength(100000));
      expect(fresh.current, {'messages'});
      final newNoticeBytes = utf8
          .encode(jsonEncode(fresh.current.toList()))
          .length;
      expect(newNoticeBytes, lessThan(100));
      // Compare amounts deterministically; timings are measurements, not CI limits.
      final metrics = {
        'conversations': 1000,
        'messages': 100000,
        'old_watch_rows_per_message_change': old.current.length,
        'old_watch_json_bytes': oldRowBytes,
        'new_notice_rows': 0,
        'new_notice_json_bytes': newNoticeBytes,
        'old_initial_ms': oldInitialMs,
        'new_initial_ms': newInitialMs,
        'old_change_ms': oldUpdateMs,
        'new_change_ms': newUpdateMs,
        'remaining_message_header_scan_ms': headerMs,
        'note':
            'Native local SQLite workload; serialized row bytes are an in-process comparison, not network traffic or UI frame timing.',
      };
      final output = File('.local/f08-profile.json');
      await output.parent.create(recursive: true);
      await output.writeAsString(
        const JsonEncoder.withIndent('  ').convert(metrics),
      );
      // ignore: avoid_print
      print(jsonEncode(metrics));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
