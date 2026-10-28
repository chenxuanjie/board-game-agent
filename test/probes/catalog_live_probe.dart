// Explicit, anonymous, read-only NAS probe. Not part of the default test suite.
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:board_game_agent/core/localization/app_language.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:board_game_agent/features/library/services/remote_asset_service.dart';

class _RealNetwork extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'live published SQL catalog, images and PDF downloads',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        const address = String.fromEnvironment('BOARD_CATALOG_ORIGIN');
        if (address.isEmpty) {
          throw StateError('Pass BOARD_CATALOG_ORIGIN explicitly');
        }
        final directory = await Directory.systemTemp.createTemp(
          'board-catalog-live-',
        );
        final service = RemoteAssetService(
          serviceOrigin: () => Uri.parse(address),
          cacheDirectory: directory,
        );
        try {
          final snapshot = await service.loadCatalog();
          expect(snapshot.games, isNotEmpty);
          expect(
            snapshot.games.every(
              (g) => g
                  .toGameInfo(
                    g.locales.containsKey('zhHans')
                        ? AppLanguage.zhHans
                        : AppLanguage.en,
                  )
                  .title
                  .isNotEmpty,
            ),
            isTrue,
          );
          final paths = [
            snapshot.files.keys.firstWhere((p) => p.endsWith('.jpg')),
            snapshot.files.entries
                .firstWhere(
                  (e) =>
                      e.value.id ==
                      'war_chest-docs-official-rules-rulebook-en-pdf',
                )
                .key,
            snapshot.files.entries
                .firstWhere(
                  (e) =>
                      e.value.id ==
                      'puerto_rico-docs-official-rules-rulebook-en-pdf',
                )
                .key,
          ];
          final samples = <Map<String, dynamic>>[];
          for (final path in paths) {
            final result = await service.ensureCached(
              sources: [],
              remotePath: path,
              allowCachedFallback: false,
            );
            expect(result, isNotNull);
            final file = File(result!.localPath);
            final digest = (await sha256.bind(file.openRead()).first)
                .toString();
            expect(digest, snapshot.files[path]!.sha256);
            samples.add({
              'resource_id': snapshot.files[path]!.id,
              'bytes': await file.length(),
              'hash_matches': true,
            });
          }
          expect(await service.refreshCatalog(), isFalse);
          final report = File('.local/reports/client-catalog-live.json');
          await report.parent.create(recursive: true);
          final result = {
            'revision': snapshot.revision,
            'games': snapshot.games.length,
            'public_resources': snapshot.files.length,
            'samples': samples,
            'unchanged_revision_check': true,
            'read_only': true,
            'real_device': false,
          };
          await report.writeAsString(jsonEncode(result));
          stdout.writeln(jsonEncode(result));
        } finally {
          service.dispose();
          await directory.delete(recursive: true);
        }
      }, _RealNetwork());
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
