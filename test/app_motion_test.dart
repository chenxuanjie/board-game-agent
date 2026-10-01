import 'dart:ui' show PointerDeviceKind;

import 'package:board_game_agent/core/localization/app_copy.dart';
import 'package:board_game_agent/core/localization/app_language.dart';
import 'package:board_game_agent/ui/desktop/content_primitives.dart';
import 'package:board_game_agent/ui/desktop/sidebar.dart';
import 'package:board_game_agent/ui/desktop/theme.dart';
import 'package:board_game_agent/ui/shared/app_page_transition.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'rapid destinations mount only the latest page and do not replay on updates',
    (tester) async {
      final destination = ValueNotifier(0);
      final scroll = ScrollController();
      final aiKey = GlobalKey();
      addTearDown(destination.dispose);
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<int>(
              valueListenable: destination,
              builder: (context, value, _) => AppPageTransition(
                identity: value,
                child: value == 2
                    ? SizedBox(key: aiKey, child: const Text('AI'))
                    : SingleChildScrollView(
                        controller: scroll,
                        child: Text('Page $value'),
                      ),
              ),
            ),
          ),
        ),
      );
      for (final value in [2, 1, 2, 0, 1, 2]) {
        destination.value = value;
        await tester.pump(const Duration(milliseconds: 20));
        expect(tester.takeException(), isNull);
        expect(find.byKey(aiKey), value == 2 ? findsOneWidget : findsNothing);
        expect(scroll.positions.length, lessThanOrEqualTo(1));
      }
      final fade = find.descendant(
        of: find.byType(AppPageTransition),
        matching: find.byType(FadeTransition),
      );
      expect(tester.widget<FadeTransition>(fade).opacity.value, lessThan(1));
      await tester.pumpAndSettle();
      expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
      destination.notifyListeners();
      await tester.pump();
      expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'enabling reduced motion settles an active page transition immediately',
    (tester) async {
      final settings = ValueNotifier((page: 0, reduced: false));
      addTearDown(settings.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder(
            valueListenable: settings,
            builder: (context, value, _) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: value.reduced),
              child: AppPageTransition(
                identity: value.page,
                child: Text('${value.page}'),
              ),
            ),
          ),
        ),
      );
      settings.value = (page: 1, reduced: false);
      await tester.pump();
      final fade = find.descendant(
        of: find.byType(AppPageTransition),
        matching: find.byType(FadeTransition),
      );
      expect(tester.widget<FadeTransition>(fade).opacity.value, lessThan(1));
      settings.value = (page: 1, reduced: true);
      await tester.pump();
      expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
      settings.value = (page: 2, reduced: true);
      await tester.pump();
      expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
      expect(find.text('2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'sidebar supports Tab, Enter and Space and moves the selection surface',
    (tester) async {
      final selected = ValueNotifier(0);
      addTearDown(selected.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDesktopTheme(),
          home: Scaffold(
            body: ValueListenableBuilder<int>(
              valueListenable: selected,
              builder: (context, index, _) => DesktopSidebar(
                compact: true,
                selectedIndex: index,
                copy: AppCopy(AppLanguage.en),
                onSelect: (value) => selected.value = value,
              ),
            ),
          ),
        ),
      );
      final indicator = find.byKey(
        const ValueKey('desktop-navigation-indicator'),
      );
      final start = tester.getTopLeft(indicator).dy;
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final tile = find.byKey(
        const ValueKey('desktop-sidebar-item-sidebar_library.png'),
      );
      final surface = tester.widget<AnimatedContainer>(
        find.descendant(of: tile, matching: find.byType(AnimatedContainer)),
      );
      expect(
        (surface.foregroundDecoration! as BoxDecoration).border!.top.color,
        DesktopColors.brown,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(selected.value, 1);
      await tester.pump(const Duration(milliseconds: 60));
      final middle = tester.getTopLeft(indicator).dy;
      expect(middle, greaterThan(start));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(indicator).dy, greaterThan(middle));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(selected.value, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reduced motion hover retains feedback without moving a card', (
    tester,
  ) async {
    var pressed = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDesktopTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: Center(
                child: HoverSurface(
                  onTap: () => pressed++,
                  child: const SizedBox(
                    width: 150,
                    height: 80,
                    child: Text('Card'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(HoverSurface)));
    await tester.pumpAndSettle();
    final surface = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(HoverSurface),
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect(surface.transform!.storage[13], 0);
    expect((surface.decoration! as BoxDecoration).boxShadow, isNotEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    final focused = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(HoverSurface),
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect(
      (focused.foregroundDecoration! as BoxDecoration).border!.top.color,
      isNot(Colors.transparent),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(pressed, 1);
    expect(tester.takeException(), isNull);
  });
}
