import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:board_game_agent/ui/shared/hover_carousel_controls.dart';
import 'package:board_game_agent/ui/shared/hover_horizontal_scrollbar.dart';

void main() {
  testWidgets(
    'edge controls fade on hover, switch pages and allow keyboard focus',
    (tester) async {
      final pages = PageController();
      addTearDown(pages.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                height: 180,
                child: HoverCarouselControls(
                  keyPrefix: 'test-carousel',
                  onPrevious: () => pages.animateToPage(
                    0,
                    duration: const Duration(milliseconds: 100),
                    curve: Curves.linear,
                  ),
                  onNext: () => pages.animateToPage(
                    1,
                    duration: const Duration(milliseconds: 100),
                    curve: Curves.linear,
                  ),
                  child: PageView(
                    controller: pages,
                    children: const [Text('first'), Text('second')],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final visibility = find.byKey(
        const ValueKey('test-carousel-next-visibility'),
      );
      expect(tester.widget<AnimatedOpacity>(visibility).opacity, 0);
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: Offset.zero);
      await pointer.moveTo(
        tester.getCenter(find.byKey(const ValueKey('test-carousel-hover'))),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedOpacity>(visibility).opacity, 1);
      expect(
        tester.getSize(find.byKey(const ValueKey('test-carousel-next'))),
        const Size(38, 72),
      );
      await tester.tap(find.byKey(const ValueKey('test-carousel-next')));
      await tester.pumpAndSettle();
      expect(pages.page, 1);
      FocusManager.instance.primaryFocus?.unfocus();
      await pointer.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedOpacity>(visibility).opacity, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedOpacity>(visibility).opacity, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(pages.page, 0);
      await pointer.removePointer();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'horizontal scrollbar appears on hover and dragging changes content',
    (tester) async {
      ScrollController? stripController;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: HoverHorizontalScrollbar(
                  enabled: true,
                  keyPrefix: 'test-strip',
                  builder: (controller) {
                    stripController = controller;
                    return SizedBox(
                      height: 100,
                      child: ListView(
                        controller: controller,
                        scrollDirection: Axis.horizontal,
                        children: List.generate(
                          8,
                          (index) =>
                              SizedBox(width: 150, child: Text('game $index')),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scrollbar = find.byKey(const ValueKey('test-strip-scrollbar'));
      expect(tester.widget<RawScrollbar>(scrollbar).thumbVisibility, isFalse);
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: Offset.zero);
      await pointer.moveTo(tester.getCenter(scrollbar));
      await tester.pumpAndSettle();
      expect(tester.widget<RawScrollbar>(scrollbar).thumbVisibility, isTrue);
      expect(tester.widget<RawScrollbar>(scrollbar).thickness, 8);
      final rect = tester.getRect(scrollbar);
      await pointer.moveTo(Offset(rect.left + 30, rect.bottom - 4));
      await pointer.down(Offset(rect.left + 30, rect.bottom - 4));
      await pointer.moveBy(const Offset(80, 0));
      await pointer.up();
      await tester.pumpAndSettle();
      expect(stripController!.offset, greaterThan(0));
      await pointer.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(tester.widget<RawScrollbar>(scrollbar).thumbVisibility, isFalse);
      await pointer.removePointer();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a strip without overflow is safe and touch-only carousels keep swiping',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: HoverHorizontalScrollbar(
                enabled: true,
                keyPrefix: 'short-strip',
                builder: (controller) => SizedBox(
                  height: 100,
                  child: ListView(
                    controller: controller,
                    scrollDirection: Axis.horizontal,
                    children: const [SizedBox(width: 100, child: Text('only'))],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final pages = PageController();
      addTearDown(pages.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 180,
              child: HoverCarouselControls(
                enabled: false,
                keyPrefix: 'touch-carousel',
                onPrevious: () {},
                onNext: () {},
                child: PageView(
                  controller: pages,
                  children: const [Text('first'), Text('second')],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(pages.page, 1);
      expect(find.byKey(const ValueKey('touch-carousel-next')), findsNothing);
    },
  );
}
