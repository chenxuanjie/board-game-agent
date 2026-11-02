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
  test(
    'reference detail route has equal 600 ms forward and reverse durations',
    () {
      final route = GameDetailRoute<void>(
        builder: (_) => const SizedBox(),
        reference: true,
      );
      expect(route.transitionDuration, const Duration(milliseconds: 600));
      expect(
        route.reverseTransitionDuration,
        const Duration(milliseconds: 600),
      );
    },
  );
}
