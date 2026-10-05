import 'dart:convert';
import 'dart:io';
import 'package:app_identity/app_identity.dart';
// ignore: implementation_imports
import 'package:app_ai_client/src/default_http_client.dart';
import 'package:board_game_agent/features/identity/models/account_configuration.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:webdav_storage/webdav_storage.dart';
import 'package:integration_test/integration_test.dart';
import '../test/support/account_sync_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final account = Platform.environment['SYNOLOGY_TEST_ACCOUNT'];
  final password = Platform.environment['SYNOLOGY_TEST_PASSWORD'];
  testWidgets(
    'real NAS private-home sync, second device, deletion and cleanup',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      final environment =
          'cloud_probe_${DateTime.now().microsecondsSinceEpoch}';
      final origin = AccountConfiguration.defaults.nasOrigin;
      final storage = SecureIdentitySessionStorage(
        appId: 'board_game_agent.cloud_probe',
        environment: environment,
      );
      final gateway = SynologyIdentityGateway(
        origin: origin,
        environment: environment,
        storage: storage,
        client: createDefaultAiHttpClient(),
      );
      var written = false;
      try {
        await gateway.initialize();
        final user = await gateway.signIn(
          account: account!,
          password: password!,
        );
        final files = gateway.privateFiles(appId: 'board_game_agent');
        final a = SyncDeviceFixture(scope: user.id),
            b = SyncDeviceFixture(scope: user.id);
        await a.start();
        await b.start();
        a.entities['favorite|cloud-probe'] = {'gameSlug': 'cloud-probe'};
        a.entities['conversation|probe-chat'] = {
          'id': 'probe-chat',
          'title': '同步验收',
          'messages': ['synthetic test data'],
        };
        a.entities['nickname|profile'] = {'value': 'synthetic probe'};
        written = true;
        final upload = await a.sync(files);
        if (upload.failure case final WebDavException failure) {
          if (failure.cause case final PrivateFileException error) {
            debugPrint(
              'Sanitized private-file failure: ${error.failure.name}, NAS code ${error.code}, stage ${error.operation}',
            );
          }
        }
        // Never print raw NAS errors, SID or file request URLs.
        expect(
          upload.completed,
          isTrue,
          reason: 'Private NAS upload must complete',
        );
        expect(
          (await b.sync(files)).completed,
          isTrue,
          reason: 'Second-device download must complete',
        );
        expect(
          b.entities == a.entities,
          isFalse,
        ); // Independent maps, same content below.
        expect(b.entities, a.entities);
        b.entities.remove('favorite|cloud-probe');
        expect((await b.sync(files)).completed, isTrue);
        expect((await a.sync(files)).completed, isTrue);
        expect(a.entities.containsKey('favorite|cloud-probe'), isFalse);
        await b.start();
        expect((await b.sync(files)).completed, isTrue);
        expect(b.entities['nickname|profile']?['value'], 'synthetic probe');
        debugPrint(
          'Private home upload, download, deletion and restart passed.',
        );
      } finally {
        try {
          if (written) {
            final raw = await storage.read();
            if (raw != null) {
              final session = jsonDecode(raw) as Map<String, dynamic>;
              // Only this uniquely named test directory is ever removed.
              final target = '/home/Apps/board_game_agent/sync/v1/$environment';
              if (!RegExp(r'^cloud_probe_[0-9]+$').hasMatch(environment)) {
                throw StateError('Unsafe cleanup scope');
              }
              final client = createDefaultAiHttpClient();
              try {
                final request = http.Request(
                  'GET',
                  origin
                      .resolve('/webapi/entry.cgi')
                      .replace(
                        queryParameters: {
                          'api': 'SYNO.FileStation.Delete',
                          'version': '2',
                          'method': 'delete',
                          'path': jsonEncode([target]),
                          'recursive': 'true',
                          '_sid': session['sid'] as String,
                          if (session['synoToken'] case final String token)
                            'SynoToken': token,
                        },
                      ),
                )..followRedirects = false;
                final response = await http.Response.fromStream(
                  await client.send(request),
                ).timeout(const Duration(seconds: 30));
                final json = jsonDecode(response.body) as Map;
                expect(
                  json['success'] == true,
                  isTrue,
                  reason: 'Temporary private NAS test data must be removed',
                );
                debugPrint('Temporary NAS test directory removed.');
              } finally {
                client.close();
              }
            }
          }
        } finally {
          try {
            await gateway.signOut();
          } finally {
            await gateway.dispose();
            await storage.delete();
          }
        }
      }
    },
    skip: account == null || password == null,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
