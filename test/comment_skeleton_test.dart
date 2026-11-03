import 'dart:async';
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'manual refresh shows skeleton and restores comments after failure',
    (tester) async {
      final pending = Completer<http.Response>();
      var blockReads = false;
      final api = AppJsonClient(
        Uri.parse('https://api.test'),
        applicationId: 'board_game_agent',
        client: MockClient((_) {
          if (blockReads) return pending.future;
          return Future.value(
            http.Response(
              jsonEncode({
                'comments': [
                  {
                    'id': 'c00000000000000000000000000000000',
                    'author_id': 'alice',
                    'game_slug': 'cabo',
                    'author': 'Alice',
                    'text': 'Existing comment',
                    'created_at': '2026-10-26T00:00:00Z',
                    'deleted': false,
                    'likes': 0,
                    'liked_by_me': false,
                  },
                ],
                'next_cursor': null,
              }),
              200,
            ),
          );
        }),
      );
      final service = GameCommentsService(
        client: api,
        scope: 'guest',
        isActive: () => true,
        displayName: () => '',
      );
      addTearDown(api.close);
      addTearDown(service.dispose);
      service.watchGame('cabo');
      await tester.runAsync(service.synchronize);
      expect(service.projection.comments.length, 1, reason: '${service.error}');
      service.unwatchGame('cabo');
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: const [
              AppPaletteThemeExtension(PaletteRegistry.warmwoodStudy),
            ],
          ),
          home: Scaffold(
            body: GameCommentsPanel(
              gameSlug: 'cabo',
              gameTitle: 'Cabo',
              preview: true,
              service: service,
            ),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        if (!service.loading) break;
      }
      await tester.pump(const Duration(milliseconds: 350));
      blockReads = true;
      final existing = find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText && widget.data == 'Existing comment',
      );
      expect(existing, findsOneWidget);
      await tester.tap(find.byTooltip('刷新评论'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byKey(const ValueKey('comments-loading')), findsOneWidget);
      expect(existing, findsNothing);
      pending.complete(http.Response('unavailable', 503));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        if (!service.loading) break;
      }
      await tester.pump(const Duration(milliseconds: 350));
      expect(existing, findsOneWidget);
      expect(find.text('评论刷新未完成，请重试'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('failed first load shows an error instead of an empty state', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    final api = AppJsonClient(
      Uri.parse('https://api.test'),
      applicationId: 'board_game_agent',
      client: MockClient((_) => response.future),
    );
    final service = GameCommentsService(
      client: api,
      scope: 'guest',
      isActive: () => true,
      displayName: () => '',
    )..loading = true;
    addTearDown(api.close);
    addTearDown(service.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const [
            AppPaletteThemeExtension(PaletteRegistry.warmwoodStudy),
          ],
        ),
        home: Scaffold(
          body: GameCommentsPanel(
            gameSlug: 'cabo',
            gameTitle: 'Cabo',
            preview: true,
            service: service,
          ),
        ),
      ),
    );
    await tester.pump();
    response.complete(http.Response('unavailable', 503));
    await tester.pumpAndSettle();
    expect(find.text('评论刷新未完成，请重试'), findsOneWidget);
    expect(find.text('还没有评论，聊聊你的桌游体验吧'), findsNothing);
    expect(find.byType(ShaderMask), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final reduced in [false, true]) {
    testWidgets(
      'comment loading settles to a real empty state, reduced=$reduced',
      (tester) async {
        final response = Completer<http.Response>();
        final api = AppJsonClient(
          Uri.parse('https://api.test'),
          applicationId: 'board_game_agent',
          client: MockClient((_) => response.future),
        );
        final service = GameCommentsService(
          client: api,
          scope: 'guest',
          isActive: () => true,
          displayName: () => '',
        )..loading = true;
        addTearDown(api.close);
        addTearDown(service.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              extensions: const [
                AppPaletteThemeExtension(PaletteRegistry.warmwoodStudy),
              ],
            ),
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(390, 800),
                disableAnimations: reduced,
              ),
              child: Scaffold(
                body: GameCommentsPanel(
                  gameSlug: 'cabo',
                  gameTitle: 'Cabo',
                  preview: true,
                  service: service,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final panel = find.byKey(const ValueKey('game-comments-panel'));
        expect(find.byKey(const ValueKey('skeleton-image-0')), findsOneWidget);
        expect(find.byKey(const ValueKey('skeleton-image-1')), findsOneWidget);
        expect(
          tester.getSize(find.byKey(const ValueKey('skeleton-image-0'))),
          const Size(96, 56),
        );
        expect(
          find.descendant(of: panel, matching: find.byType(ShaderMask)),
          reduced ? findsNothing : findsOneWidget,
        );
        if (!reduced) {
          final loading = find.byKey(const ValueKey('comments-loading'));
          final shimmer = tester.widget<AnimatedBuilder>(
            find.descendant(
              of: loading,
              matching: find.byType(AnimatedBuilder),
            ),
          );
          await tester.pump(const Duration(milliseconds: 450));
          expect(
            (shimmer.animation as Animation<double>).value,
            closeTo(.5, .02),
          );
        }
        expect(find.text('还没有评论，聊聊你的桌游体验吧'), findsNothing);
        response.complete(
          http.Response(jsonEncode({'comments': [], 'next_cursor': null}), 200),
        );
        await tester.pumpAndSettle();
        expect(find.text('还没有评论，聊聊你的桌游体验吧'), findsOneWidget);
        expect(find.byType(ShaderMask), findsNothing);
        expect(find.text('查看全部评论'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
