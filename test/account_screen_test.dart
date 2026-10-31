import 'dart:async';
import 'package:app_identity/app_identity.dart';
import 'package:board_game_agent/features/identity/services/account_service.dart';
import 'package:board_game_agent/ui/shared/account_scope.dart';
import 'package:board_game_agent/ui/shared/account_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'account_service_test.dart'
    show FixtureApp, FixtureGateway, MemoryStorage;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final width in [320.0, 1280.0]) {
    testWidgets('new API login and cancel share a stable button at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final gateway = FixtureGateway()..pending = Completer<IdentityUser>();
      late AccountService service;
      await tester.runAsync(() async {
        service = AccountService(
          controller: FixtureApp(),
          gatewayFactory: (_) async => gateway,
          savedLoginStorage: MemoryStorage(),
          switchScope: (_) async {},
        );
        await service.configureService('https://service.example.test');
      });
      addTearDown(service.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: AccountScope(
            service: service,
            child: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 1200),
                textScaler: TextScaler.linear(width == 320 ? 1.5 : 1),
              ),
              child: const AccountScreen(),
            ),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('account-service-address')),
        findsOneWidget,
      );
      expect(find.textContaining('5001'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('account-username')),
        'reader',
      );
      await tester.enterText(
        find.byKey(const ValueKey('account-password')),
        'fixture',
      );
      final button = find.byKey(const ValueKey('account-sign-in'));
      await tester.ensureVisible(button);
      final initial = tester.getSize(button);
      await tester.tap(button);
      await tester.pump();
      expect(find.text('Cancel sign-in'), findsOneWidget);
      expect(find.byKey(const ValueKey('account-loading')), findsOneWidget);
      expect(tester.getSize(button), initial);
      await tester.tap(button);
      await tester.pump();
      await tester.runAsync(() async {
        gateway.pending!.complete(const IdentityUser(id: 'late'));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      expect(service.isBusy, isFalse);
      await tester.pumpAndSettle();
      expect(service.user, isNull);
      expect(find.byKey(const ValueKey('account-loading')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
