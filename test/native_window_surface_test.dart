import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';
import 'package:board_game_agent/core/platform/native_window_surface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final colors = <int>[];
  setUp(() {
    colors.clear();
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'isMaximized':
        case 'isFullScreen':
          return false;
        case 'isDocked':
          return 0;
        case 'setBackgroundColor':
          colors.add((call.arguments as Map)['backgroundColorA'] as int);
      }
      return null;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });
  Widget surface(bool enabled) => RepaintBoundary(
    key: const ValueKey('surface-capture'),
    child: NativeWindowSurface(
      enabled: enabled,
      child: const ColoredBox(color: Color(0xFF24261D)),
    ),
  );
  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  }

  testWidgets(
    'surface uses transparent antialiased corners and restores opaque host',
    (tester) async {
      try {
        await tester.binding.setSurfaceSize(const Size(100, 100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(surface(true));
        await tester.pumpAndSettle();
        final clip = tester.widget<ClipRRect>(
          find.byKey(const ValueKey('native-rounded-surface')),
        );
        expect(clip.clipBehavior, Clip.antiAlias);
        expect(clip.borderRadius, BorderRadius.circular(32));
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('surface-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          try {
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            expect(
              bytes.getUint8(3),
              0,
            ); // The corner is transparent, never white.
            expect(bytes.getUint8((50 * 100 + 50) * 4 + 3), 255);
            final alphas = List.generate(
              100 * 100,
              (i) => bytes.getUint8(i * 4 + 3),
            );
            expect(
              alphas.any((a) => a > 0 && a < 255),
              isTrue,
            ); // Smooth edge coverage.
          } finally {
            image.dispose();
          }
        });
        await tester.pumpWidget(surface(false));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('native-rounded-surface')),
          findsNothing,
        );
        expect(colors, [0, 255]);
      } finally {
        await cleanup(tester);
      }
    },
  );

  testWidgets(
    'other themes do not reconfigure or query the native window on mount',
    (tester) async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return null;
      });
      try {
        await tester.pumpWidget(surface(false));
        await tester.pumpAndSettle();
        expect(calls, isEmpty);
        expect(
          find.byKey(const ValueKey('native-rounded-surface')),
          findsNothing,
        );
      } finally {
        await cleanup(tester);
      }
    },
  );

  testWidgets('maximize fullscreen and docking square corners then restore', (
    tester,
  ) async {
    try {
      await tester.pumpWidget(surface(true));
      await tester.pumpAndSettle();
      final listener = windowManager.listeners.single;
      void radius(double value) => expect(
        tester
            .widget<ClipRRect>(
              find.byKey(const ValueKey('native-rounded-surface')),
            )
            .borderRadius,
        BorderRadius.circular(value),
      );
      listener.onWindowMaximize();
      await tester.pump();
      radius(0);
      listener.onWindowUnmaximize();
      await tester.pump();
      radius(32);
      listener.onWindowEnterFullScreen();
      await tester.pump();
      radius(0);
      listener.onWindowLeaveFullScreen();
      await tester.pump();
      radius(32);
      listener.onWindowDocked();
      await tester.pump();
      radius(0);
      listener.onWindowUndocked();
      await tester.pump();
      radius(32);
      expect(tester.takeException(), isNull);
    } finally {
      await cleanup(tester);
    }
  });

  testWidgets('unsupported composition leaves a rectangular surface', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setBackgroundColor') {
        throw PlatformException(code: 'unsupported');
      }
      if (call.method == 'isDocked') return 0;
      return false;
    });
    try {
      await tester.pumpWidget(surface(true));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('native-rounded-surface')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await cleanup(tester);
    }
  });

  testWidgets(
    'rapid replacement cannot leave an opaque host behind the new rounded surface',
    (tester) async {
      final firstWrite = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'isDocked') return 0;
        if (call.method != 'setBackgroundColor') return false;
        colors.add((call.arguments as Map)['backgroundColorA'] as int);
        if (colors.length == 1) await firstWrite.future;
        return null;
      });
      try {
        await tester.pumpWidget(surface(true));
        await tester.pump();
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        await tester.pumpWidget(surface(true));
        await tester.pump();
        firstWrite.complete();
        await tester.pumpAndSettle();
        expect(colors, [0, 0]);
        expect(
          find.byKey(const ValueKey('native-rounded-surface')),
          findsOneWidget,
        );
      } finally {
        if (!firstWrite.isCompleted) firstWrite.complete();
        await cleanup(tester);
      }
    },
  );
}
