import 'package:board_game_agent/ui/shared/game_cover_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'reference geometry uses the sample cubic timing in either direction',
    () {
      const begin = Rect.fromLTWH(0, 0, 100, 80);
      const end = Rect.fromLTWH(200, 100, 300, 160);
      for (final reverse in [false, true]) {
        final tween = reverse
            ? referenceHeroRectTween(end, begin)
            : referenceHeroRectTween(begin, end);
        for (final t in [.1, .25, .5, .75, .9]) {
          final actual = tween.lerp(Curves.fastOutSlowIn.transform(t))!;
          final expected = Rect.lerp(
            reverse ? end : begin,
            reverse ? begin : end,
            const ReferenceViewCurve().transform(t),
          )!;
          // Flutter's cubic curve inversion has finite numerical precision.
          expect(actual.left, closeTo(expected.left, 1));
          expect(actual.width, closeTo(expected.width, 1));
        }
      }
    },
  );
  testWidgets('desktop cover fades into the destination before removal', (
    tester,
  ) async {
    var finished = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 300,
          height: 200,
          child: GameCoverFlight(
            begin: const Rect.fromLTWH(0, 0, 100, 80),
            end: const Rect.fromLTWH(0, 0, 300, 200),
            reference: true,
            onEnd: () => finished = true,
            child: const ColoredBox(
              key: ValueKey('shared-cover'),
              color: Colors.red,
            ),
          ),
        ),
      ),
    );
    double opacity() => tester
        .widget<Opacity>(
          find
              .ancestor(
                of: find.byKey(const ValueKey('shared-cover')),
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity;
    await tester.pump(const Duration(milliseconds: 210));
    expect(opacity(), closeTo(1, .01));
    await tester.pump(const Duration(milliseconds: 70));
    expect(opacity(), closeTo(.5, .01));
    await tester.pump(const Duration(milliseconds: 70));
    expect(opacity(), 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(finished, isTrue);
  });
  test(
    'reference detail route has equal 350 ms forward and reverse durations',
    () {
      final route = GameDetailRoute<void>(
        builder: (_) => const SizedBox(),
        reference: true,
      );
      expect(route.transitionDuration, const Duration(milliseconds: 350));
      expect(
        route.reverseTransitionDuration,
        const Duration(milliseconds: 350),
      );
    },
  );
}
