import 'dart:convert';
import 'dart:io';

import 'package:app_identity/app_identity.dart';
// Use the same Windows proxy-aware transport as the application.
// ignore: implementation_imports
import 'package:app_ai_client/src/default_http_client.dart';
import 'package:board_game_agent/features/identity/models/account_configuration.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final account = Platform.environment['SYNOLOGY_TEST_ACCOUNT'];
  final password = Platform.environment['SYNOLOGY_TEST_PASSWORD'];
  testWidgets(
    'real NAS login, native secure storage, restart verification and remote logout',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      final storage = SecureIdentitySessionStorage(
        appId: 'board_game_agent.auth_probe',
        environment: 'probe_${DateTime.now().microsecondsSinceEpoch}',
      );
      SynologyIdentityGateway gateway(IdentitySessionStorage target) =>
          SynologyIdentityGateway(
            origin: AccountConfiguration.defaults.nasOrigin,
            environment: 'native_probe',
            client: createDefaultAiHttpClient(),
            storage: target,
          );
      var adapter = gateway(storage);
      try {
        await adapter.initialize();
        expect(await adapter.verifyCurrentUser(), isNull);
        final user = await adapter.signIn(
          account: account!,
          password: password!,
        );
        expect(user.displayName, account);
        expect((await adapter.verifyCurrentUser())?.id, user.id);
        final savedSession = await storage.read();
        expect(savedSession != null, isTrue);
        // The probe deliberately avoids matchers that print sensitive content.
        final storedFields = jsonDecode(savedSession!) as Map<String, dynamic>;
        expect(storedFields.containsKey('passwd'), isFalse);
        expect(storedFields.containsKey('password'), isFalse);
        expect(storedFields.containsKey('otp_code'), isFalse);
        await adapter.dispose();
        adapter = gateway(storage);
        await adapter.initialize();
        expect((await adapter.verifyCurrentUser())?.id, user.id);
        await adapter.signOut();
        expect(await storage.read(), isNull);

        final oldSession = _ProbeStorage(savedSession);
        final replay = gateway(oldSession);
        try {
          await replay.initialize();
          expect(await replay.verifyCurrentUser(), isNull);
          expect(await oldSession.read(), isNull);
        } finally {
          await replay.dispose();
        }
      } finally {
        try {
          await adapter.signOut();
        } finally {
          await adapter.dispose();
          await storage.delete();
        }
      }
    },
    skip: account == null || password == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

final class _ProbeStorage implements IdentitySessionStorage {
  _ProbeStorage(this.value);
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String text) async => value = text;
  @override
  Future<void> delete() async => value = null;
}
