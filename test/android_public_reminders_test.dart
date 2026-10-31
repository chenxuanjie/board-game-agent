import 'dart:async';

import 'package:board_game_agent/core/platform/android_public_reminders.dart';
import 'package:board_game_agent/core/theme/app_theme.dart';
import 'package:board_game_agent/core/theme/palette_registry.dart';
import 'package:board_game_agent/ui/mobile/android_public_reminders_tile.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('board_game_agent/public_reminders');
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('guest enables and disables reminders using the public service', (
    tester,
  ) async {
    var enabled = false;
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      switch (call.method) {
        case 'state':
          return {'enabled': enabled, 'allowed': true};
        case 'enable':
          enabled = true;
          return null;
        case 'disable':
          enabled = false;
          return null;
        case 'configure':
          return null;
      }
      throw MissingPluginException();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildTheme(PaletteRegistry.warmwoodStudy),
        home: const Scaffold(
          body: AndroidPublicRemindersTile(checkUpdates: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final tile = find.byKey(const ValueKey('android-public-reminders'));
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    tester.widget<SwitchListTile>(tile).onChanged!(true);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    final configure = calls.firstWhere((call) => call.method == 'configure');
    expect((configure.arguments as Map)['origin'], 'https://cznas.pp.ua:18281');
    expect((configure.arguments as Map)['checkUpdates'], isTrue);
    tester.widget<SwitchListTile>(tile).onChanged!(false);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    expect(
      calls.map((call) => call.method),
      containsAllInOrder(['configure', 'enable', 'configure', 'disable']),
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('denied notification permission leaves reminders off', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'state') return {'enabled': false, 'allowed': false};
      if (call.method == 'enable') {
        throw PlatformException(code: 'permission_denied');
      }
      return null;
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildTheme(PaletteRegistry.warmwoodStudy),
        home: const Scaffold(
          body: AndroidPublicRemindersTile(checkUpdates: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final tile = find.byKey(const ValueKey('android-public-reminders'));
    tester.widget<SwitchListTile>(tile).onChanged!(true);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    expect(find.text('无法启用后台提醒，请检查系统通知权限和服务地址'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('disposing settings cancels a pending platform deadline', (
    tester,
  ) async {
    final pending = Completer<Object?>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) => pending.future,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AndroidPublicRemindersTile(checkUpdates: true)),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
    pending.complete(null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('other platforms do not call the Android channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(AndroidPublicReminders.supported, isFalse);
    expect((await AndroidPublicReminders.state()).enabled, isFalse);
    await AndroidPublicReminders.configure(
      Uri.parse('https://example.org'),
      true,
    );
  });
}
