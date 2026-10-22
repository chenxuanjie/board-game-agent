import 'package:board_game_agent/ui/desktop/desktop_window_frame.dart';
import 'package:board_game_agent/ui/desktop/window_controls.dart';
import 'package:board_game_agent/ui/desktop/desktop_responsive.dart';
import 'package:board_game_agent/ui/desktop/theme.dart';
import 'package:board_game_agent/ui/shared/account_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final calls = <String>[];
  var maximized = false;
  setUp(() {
    calls.clear();
    maximized = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), (
          call,
        ) async {
          calls.add(call.method);
          if (call.method == 'isMaximized') return maximized;
          if (call.method == 'maximize') maximized = true;
          if (call.method == 'unmaximize') maximized = false;
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
  });

  for (final size in [const Size(1100, 800), const Size(2560, 1440)]) {
    testWidgets(
      'chrome stays outside account routes and modal barriers at $size',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            builder: (_, child) => DesktopWindowFrame(child: child!),
            home: const Scaffold(body: Text('home')),
          ),
        );
        await tester.pumpAndSettle();
        navigator.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const AccountScreen()),
        );
        await tester.pumpAndSettle();
        expect(find.byType(WindowControls), findsOneWidget);
        expect(tester.getTopLeft(find.byType(WindowControls)).dy, 0);
        expect(
          tester.getTopLeft(find.byType(AccountScreen)).dy,
          greaterThan(0),
        );
        showDialog<void>(
          context: tester.element(find.byType(AccountScreen)),
          builder: (_) => const AlertDialog(content: Text('modal')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('最小化'));
        await tester.pump();
        expect(calls, contains('minimize'));
        await tester.tap(find.byTooltip('最大化'));
        await tester.pump();
        expect(calls, contains('maximize'));
        await tester.tap(find.byTooltip('关闭'));
        await tester.pump();
        expect(calls, contains('close'));
        expect(find.text('modal'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    'loading and failure replacements keep window controls',
    (tester) async {
      for (final body in [
        const CircularProgressIndicator(),
        const Text('启动失败'),
        const Text('账号数据切换未完成'),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) =>
                DesktopWindowFrame(child: Scaffold(body: body)),
          ),
        );
        await tester.pump();
        expect(find.byType(WindowControls), findsOneWidget);
        await tester.tap(find.byTooltip('最小化'));
        expect(calls, contains('minimize'));
        expect(tester.takeException(), isNull);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  for (final size in [
    const Size(700, 800),
    const Size(1100, 800),
    const Size(1280, 800),
    const Size(1586, 992),
    const Size(2560, 1440),
  ]) {
    testWidgets(
      'titlebar sidebar color matches the content viewport at $size',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final observer = DesktopWindowChromeObserver(
          workspaceRouteNames: {'/rankings'},
        );
        addTearDown(observer.sidebarVisible.dispose);
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            theme: buildDesktopTheme(),
            navigatorKey: navigator,
            navigatorObservers: [observer],
            builder: (_, child) => ValueListenableBuilder<bool>(
              valueListenable: observer.sidebarVisible,
              builder: (_, visible, _) =>
                  DesktopWindowFrame(sidebarVisible: visible, child: child!),
            ),
            home: const Scaffold(body: Text('workspace')),
          ),
        );
        await tester.pumpAndSettle();
        final background = find.byKey(
          const ValueKey('desktop-window-sidebar-background'),
        );
        if (size.width < DesktopResponsive.narrowBreakpoint) {
          expect(background, findsNothing);
        } else {
          final contentSize = tester.getSize(find.byType(Scaffold));
          final contentMetrics = DesktopResponsive.metricsFor(contentSize);
          final width = contentMetrics.px(
            size.width >= DesktopResponsive.fullSidebarBreakpoint
                ? DesktopResponsive.fullSidebarWidth
                : DesktopResponsive.compactSidebarWidth,
          );
          expect(tester.getSize(background).width, width);
          expect(
            (tester.widget<DecoratedBox>(background).decoration
                    as BoxDecoration)
                .color,
            DesktopColors.sidebar,
          );
          expect(tester.getTopLeft(background), Offset.zero);
        }
        navigator.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const AccountScreen()),
        );
        await tester.pumpAndSettle();
        expect(background, findsNothing);
        expect(find.byType(WindowControls), findsOneWidget);
        showDialog<void>(
          context: tester.element(find.byType(AccountScreen)),
          builder: (_) => const AlertDialog(content: Text('dialog')),
        );
        await tester.pumpAndSettle();
        expect(background, findsNothing);
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(
          background,
          size.width < DesktopResponsive.narrowBreakpoint
              ? findsNothing
              : findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    'Android keeps its own viewport without native chrome',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => DesktopWindowFrame(child: child!),
          home: const Scaffold(body: Text('mobile')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WindowControls), findsNothing);
      expect(calls, isEmpty);
      expect(tester.getTopLeft(find.byType(Scaffold)).dy, 0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
