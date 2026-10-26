import 'dart:convert';
import 'dart:io';
import 'package:board_game_agent/features/identity/services/board_worker_version.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Web SDK worker fingerprint and all runtime dependencies match this client',
    () {
      final worker = File('web/powersync/powersync_db.worker.js');
      expect(
        sha256.convert(worker.readAsBytesSync()).toString(),
        boardWorkerVersion,
      );
      expect(
        File('web/powersync/sqlite3.wasm').lengthSync(),
        greaterThan(100000),
      );
      final versions =
          jsonDecode(File('web/powersync/dependencies.json').readAsStringSync())
              as Map;
      final lock = File('pubspec.lock').readAsStringSync();
      for (final entry in versions.entries) {
        final block = RegExp(
          '^  ${entry.key}:\\r?\\n[\\s\\S]*?(?=^  [a-zA-Z0-9_]+:|^sdks:)',
          multiLine: true,
        ).firstMatch(lock)!.group(0)!;
        final version = RegExp(
          'version: "([^"]+)"',
        ).firstMatch(block)!.group(1);
        expect(
          version,
          entry.value,
          reason: 'Regenerate the SDK worker after changing ${entry.key}',
        );
      }
    },
  );
}
