import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:board_game_agent/app/state/browse_session.dart';
import 'package:board_game_agent/ui/shared/library_viewport.dart';
import 'package:board_game_agent/ui/shared/content_entrance.dart';
import 'package:board_game_agent/ui/shared/app_modals.dart';
import 'package:board_game_agent/ui/shared/image_reveal.dart';
import 'package:board_game_agent/ui/shared/smooth_progress.dart';

Widget grid(LibraryBrowseState state, ScrollController scroll, int columns) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            height: 300,
            child: LibraryViewport(
              state: state,
              controller: scroll,
              layout: columns,
              ids: List.generate(100, (i) => 'g$i'),
              estimate: (i) => (i ~/ columns) * 100,
              builder: (keys) => GridView.builder(
                controller: scroll,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisExtent: 100,
                ),
                itemCount: 100,
                itemBuilder: (_, i) => SizedBox(
                  key: keys['g$i'],
                  child: Text('g$i', key: ValueKey('item-g$i')),
                ),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets(
    'lazy grid restores the same game after column changes and remount',
    (tester) async {
      final state = LibraryBrowseState();
      final scroll = ScrollController(keepScrollOffset: false);
      addTearDown(scroll.dispose);
      await tester.pumpWidget(grid(state, scroll, 2));
      await tester.pumpAndSettle();
      scroll.jumpTo(550);
      await tester.pumpAndSettle();
      final id = state.anchorId!;
      final before = tester.getTopLeft(find.byKey(ValueKey('item-$id'))).dy;
      await tester.pumpWidget(grid(state, scroll, 4));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(ValueKey('item-$id'))).dy,
        closeTo(before, 1),
      );
      final saved = scroll.offset;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(grid(state, scroll, 4));
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(saved, 1));
      state.resetPosition();
      await tester.pumpWidget(grid(state, scroll, 4));
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'account transition replaces presentation state without old widget writes leaking',
    () {
      final session = BrowseSession();
      final old = session.library;
      old
        ..query = '卡卡颂'
        ..category = 5
        ..sort = 'score'
        ..anchorId = 'carcassonne';
      session.destination = 'games';
      session.reset();
      old.query = 'late old page write';
      expect(session.library.query, '');
      expect(session.library.anchorId, isNull);
      expect(session.destination, 'home');
      expect(identical(old, session.library), isFalse);
    },
  );

  testWidgets('only changed content animates and its input stays mounted', (
    tester,
  ) async {
    final data = ValueNotifier(0);
    addTearDown(data.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: data,
            builder: (_, value, _) => Column(
              children: [
                ContentEntrance(
                  key: const ValueKey('changed'),
                  changeIdentity: value,
                  child: const TextField(key: ValueKey('kept-input')),
                ),
                const ContentEntrance(
                  key: ValueKey('unchanged'),
                  child: Text('stable'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('kept-input')), 'draft');
    final element = tester.element(find.byKey(const ValueKey('kept-input')));
    data.value++;
    await tester.pump();
    Opacity opacity(String key) => tester.widget<Opacity>(
      find
          .descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(opacity('changed').opacity, lessThan(1));
    expect(opacity('unchanged').opacity, 1);
    expect(
      tester.element(find.byKey(const ValueKey('kept-input'))),
      same(element),
    );
    expect(find.text('draft'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'sheet repeated opens stay guarded through the closing animation',
    (tester) async {
      late BuildContext source;
      var builds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              source = context;
              return const Scaffold(body: Text('home'));
            },
          ),
        ),
      );
      Future<void> open() => showAppBottomSheet<void>(
        context: source,
        builder: (_) {
          builds++;
          return const SizedBox(height: 160, child: Text('sheet'));
        },
      );
      final first = open();
      await tester.pumpAndSettle();
      await open();
      expect(builds, 1);
      Navigator.of(source).pop();
      await tester.pump(const Duration(milliseconds: 40));
      await open();
      expect(builds, 1);
      await tester.pumpAndSettle();
      await first;
      final next = open();
      await tester.pumpAndSettle();
      expect(builds, 2);
      Navigator.of(source).pop();
      await tester.pumpAndSettle();
      await next;
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'decoded image fades in without changing size or hiding the retained frame',
    (tester) async {
      final ready = ValueNotifier(false);
      addTearDown(ready.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 200,
              height: 120,
              child: ValueListenableBuilder<bool>(
                valueListenable: ready,
                builder: (context, value, _) => revealImageFrame(
                  context,
                  const SizedBox.expand(child: ColoredBox(color: Colors.green)),
                  value ? 0 : null,
                  false,
                ),
              ),
            ),
          ),
        ),
      );
      final size = tester.getSize(find.byType(ImageLoadingPlaceholder));
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        0,
      );
      ready.value = true;
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(ImageLoadingPlaceholder)), size);
      ready.value = false;
      await tester.pump();
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        1,
      );
    },
  );

  testWidgets(
    'progress follows actual values and converges immediately with reduced motion',
    (tester) async {
      final value = ValueNotifier(.25);
      final reduced = ValueNotifier(false);
      addTearDown(value.dispose);
      addTearDown(reduced.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: reduced,
            builder: (context, disabled, _) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: disabled),
              child: ValueListenableBuilder<double>(
                valueListenable: value,
                builder: (_, actual, _) => SmoothProgress(value: actual),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      value.value = .5;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(indicator.value, greaterThan(.25));
      expect(indicator.value, lessThanOrEqualTo(.5));
      expect(indicator.semanticsValue, '50');
      // A new task/reset must never show the previous task's higher value.
      value.value = .1;
      await tester.pump();
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        lessThanOrEqualTo(.1),
      );
      reduced.value = true;
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .1,
      );
    },
  );
}
