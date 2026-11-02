import 'package:board_game_agent/core/theme/app_palette.dart';
import 'package:board_game_agent/core/theme/palette_registry.dart';
import 'package:board_game_agent/ui/shared/favorite_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('comment like uses reference peak and reduced motion', (
    tester,
  ) async {
    Widget app(bool selected, bool reduced) => MaterialApp(
      theme: ThemeData(
        extensions: const [
          AppPaletteThemeExtension(PaletteRegistry.warmwoodStudy),
        ],
      ),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: FavoriteFeedbackIcon(selected: selected, motion166: true),
      ),
    );
    await tester.pumpWidget(app(false, false));
    await tester.pumpWidget(app(true, false));
    await tester.pump(const Duration(milliseconds: 120));
    final transform = tester.widget<Transform>(
      find
          .descendant(
            of: find.byType(FavoriteFeedbackIcon),
            matching: find.byType(Transform),
          )
          .last,
    );
    expect(transform.transform.storage[0], closeTo(1.45, .01));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(false, true));
    await tester.pumpWidget(app(true, true));
    final reducedTransform = tester.widget<Transform>(
      find
          .descendant(
            of: find.byType(FavoriteFeedbackIcon),
            matching: find.byType(Transform),
          )
          .last,
    );
    expect(reducedTransform.transform.storage[0], closeTo(1, .001));
  });
  testWidgets('warmwood like settles and respects reduced motion', (
    tester,
  ) async {
    Widget app({required bool selected, required bool reduced}) => MaterialApp(
      theme: ThemeData(
        extensions: const [
          AppPaletteThemeExtension(PaletteRegistry.warmwoodStudy),
        ],
      ),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: FavoriteFeedbackIcon(selected: selected),
      ),
    );

    await tester.pumpWidget(app(selected: false, reduced: false));
    await tester.pumpWidget(app(selected: true, reduced: false));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.widget<ScaleTransition>(find.byType(ScaleTransition)).scale.value,
      greaterThan(1),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<ScaleTransition>(find.byType(ScaleTransition)).scale.value,
      closeTo(1, .001),
    );

    await tester.pumpWidget(app(selected: false, reduced: true));
    await tester.pumpWidget(app(selected: true, reduced: true));
    expect(
      tester.widget<ScaleTransition>(find.byType(ScaleTransition)).scale.value,
      1,
    );
  });
}
