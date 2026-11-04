import 'dart:convert';

import 'package:app_client/app_client.dart';
import 'package:board_game_agent/core/theme/app_palette.dart';
import 'package:board_game_agent/core/theme/palette_registry.dart';
import 'package:board_game_agent/features/community/services/game_comments_service.dart';
import 'package:board_game_agent/ui/shared/game_comments.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const rejectedId = 'c11111111111111111111111111111111';
const missingParent = 'c22222222222222222222222222222222';

void main() {
  for (final size in [const Size(320, 844), const Size(1280, 900)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'rejected reply recovers as editable root at $size scale=$scale',
        (tester) async {
          final fixture = await mount(tester, size, scale);
          expect(find.text('原评论已不可回复，内容已保留'), findsOneWidget);
          expect(find.text('发送中'), findsNothing);
          await tester.tap(find.text('修改'));
          await settle(tester);
          final input = find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byKey(const ValueKey('comment-input')),
          );
          expect(input, findsOneWidget);
          expect(tester.widget<TextField>(input).enabled, isTrue);
          expect(tester.widget<TextField>(input).controller!.text, '需要修改的回复');
          expect(find.text('改发为新评论'), findsOneWidget);
          await tester.enterText(input, '修改后作为新评论');
          await settle(tester);
          final send = find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byKey(const ValueKey('comment-send')),
          );
          await tester.ensureVisible(send);
          await tester.tap(send);
          await settle(tester);
          expect(fixture.sent, hasLength(1));
          expect(fixture.sent.single['id'], isNot(rejectedId));
          expect(fixture.sent.single['parent_id'], isNull);
          expect(fixture.sent.single['body'], '修改后作为新评论');
          expect(fixture.service.pending, isFalse);
          expect(
            find.byKey(const ValueKey('comment-issue-$rejectedId')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets(
    'cancel keeps the body as draft and unlocks the existing wide composer',
    (tester) async {
      final fixture = await mount(tester, const Size(1280, 900), 1, root: true);
      expect(find.byKey(const ValueKey('comment-$rejectedId')), findsNothing);
      expect(find.text('评论 0'), findsOneWidget);
      final input = find.byKey(const ValueKey('comment-input'));
      expect(tester.widget<TextField>(input).enabled, isFalse);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('comment-send')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('取消发送'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, '取消发送'));
      await settle(tester);
      expect(fixture.service.pending, isFalse);
      expect(fixture.sent, isEmpty);
      expect(tester.widget<TextField>(input).enabled, isTrue);
      expect(tester.widget<TextField>(input).controller!.text, '需要修改的回复');
      final draft = await tester.runAsync(
        () => fixture.service.readDraft('cabo', null),
      );
      expect(draft!['enqueued'], isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'composer replaces retry with editable recovery for a permanent rejection',
    (tester) async {
      final fixture = await mount(tester, const Size(1280, 900), 1, root: true);
      await tester.tap(find.byKey(const ValueKey('comment-send')));
      await settle(tester);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('comment-input')))
            .enabled,
        isTrue,
      );
      expect(fixture.sent, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('comment-input')),
        '在编辑器中修改后发布',
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('comment-send')));
      await settle(tester);
      expect(fixture.sent.single['body'], '在编辑器中修改后发布');
      expect(fixture.sent.single['id'], isNot(rejectedId));
      expect(fixture.service.pending, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<void> settle(WidgetTester tester) async {
  for (var n = 0; n < 12; n++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<Fixture> mount(
  WidgetTester tester,
  Size size,
  double scale, {
  bool root = false,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({
    'board.community.api.v1.alice': jsonEncode({
      'commands': [
        {
          'id': rejectedId,
          'action': 'publish',
          'comment_id': rejectedId,
          'game_slug': 'cabo',
          'body': '需要修改的回复',
          'rating': null,
          'parent_id': root ? null : missingParent,
        },
      ],
      'optimistic': [
        {
          'id': rejectedId,
          'author_id': 'alice',
          'author': 'Alice',
          'game_slug': 'cabo',
          'text': '需要修改的回复',
          'rating': null,
          'created_at': '2026-11-04T00:00:00Z',
          'deleted': false,
          'likes': 0,
          'liked_by_me': false,
          'parent_id': root ? null : missingParent,
          'root_id': root ? null : missingParent,
        },
      ],
      'rejections': {
        rejectedId: root ? 'comment_rejected' : 'comment_parent_unavailable',
      },
    }),
    if (root)
      'board.community.api.v1.alice.draft.cabo.root': jsonEncode({
        'id': rejectedId,
        'text': '需要修改的回复',
        'enqueued': true,
        'rating': null,
      }),
  });
  final fixture = Fixture();
  addTearDown(fixture.client.close);
  addTearDown(fixture.service.dispose);
  await tester.runAsync(fixture.service.initialize);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        extensions: const [
          AppPaletteThemeExtension(PaletteRegistry.warmwoodStudy),
        ],
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: GameCommentsPanel(
              gameSlug: 'cabo',
              gameTitle: 'Cabo',
              service: fixture.service,
            ),
          ),
        ),
      ),
    ),
  );
  await settle(tester);
  return fixture;
}

class Fixture {
  Fixture() {
    client = AppJsonClient(
      Uri.parse('https://api.test'),
      applicationId: 'board_game_agent',
      client: MockClient((request) async {
        if (request.method == 'POST') {
          final command = jsonDecode(request.body) as Map<String, dynamic>;
          sent.add(command);
          return http.Response(
            jsonEncode({'id': command['id'], 'status': 'applied'}),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'comments': [
              for (final command in sent)
                {
                  'id': command['comment_id'],
                  'author_id': 'alice',
                  'author': 'Alice',
                  'game_slug': 'cabo',
                  'text': command['body'],
                  'parent_id': command['parent_id'],
                  'root_id': null,
                  'rating': null,
                  'created_at': '2026-11-04T00:00:00Z',
                  'likes': 0,
                  'liked_by_me': false,
                  'deleted': false,
                },
            ],
            'next_cursor': null,
          }),
          200,
        );
      }),
    );
    service = GameCommentsService(
      client: client,
      scope: 'alice',
      uid: 'alice',
      displayName: () => 'Alice',
      token: () async => 'token',
      isActive: () => true,
    );
  }
  late final AppJsonClient client;
  late final GameCommentsService service;
  final sent = <Map<String, dynamic>>[];
}
