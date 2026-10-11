import 'dart:async';
import 'dart:convert';
import 'package:app_identity/app_identity.dart';
import 'package:board_game_agent/features/community/models/game_comment.dart';
import 'package:board_game_agent/features/community/services/game_comments_service.dart';
import 'package:board_game_agent/core/theme/app_theme.dart';
import 'package:board_game_agent/core/theme/palette_registry.dart';
import 'package:board_game_agent/ui/shared/game_comments.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/account_public_fixture.dart';

const game = 'carcassonne_3';
GameCommentsService service(
  PublicFixtureHub hub,
  int uid, {
  String? scope,
  AccountPublicFiles? files,
  bool Function()? active,
}) {
  final result = GameCommentsService(
    files: files ?? MemoryPublicFiles(hub, uid),
    scope: scope ?? 'test-$uid',
    isActive: active ?? () => true,
    displayName: () => '桌友$uid',
  );
  addTearDown(result.dispose);
  return result;
}

GameComment comment(GameCommentsService service, String id) => service
    .projection
    .forGame(game, service.pendingIds)
    .firstWhere((c) => c.id == id);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'optional score, per-account latest score and deletion never revive old score',
    () async {
      final hub = PublicFixtureHub(), a = service(PublicFixtureHub(), 101);
      // Use a shared transport for the remaining distinct accounts.
      final first = await a.publish(game: game, text: '第一次体验', rating: 8);
      await a.synchronize();
      final second = await a.publish(game: game, text: '第二次体验', rating: 9);
      await a.synchronize();
      await a.publish(game: game, text: '不评分的补充');
      await a.synchronize();
      expect(a.projection.ratings(game), {101: 9});
      await a.delete(comment(a, first));
      expect(a.projection.ratings(game), {101: 9});
      await a.delete(comment(a, second));
      expect(a.projection.ratings(game), isEmpty);
      final b = service(hub, 102);
      await b.publish(game: game, text: '可以不评分');
      await b.synchronize();
      expect(b.projection.ratings(game), isEmpty);
    },
  );
  test(
    'concurrent accounts do not overwrite comments or likes; cancellation counts once',
    () async {
      final hub = PublicFixtureHub();
      final a = service(hub, 101), b = service(hub, 102);
      final id = await a.publish(game: game, text: '值得一玩', rating: 8);
      await a.synchronize();
      await b.synchronize();
      await Future.wait([
        a.toggleLike(comment(a, id)),
        b.toggleLike(comment(b, id)),
      ]);
      await Future.wait([a.synchronize(), b.synchronize()]);
      expect(comment(a, id).likes, 2);
      expect(comment(b, id).likes, 2);
      await b.toggleLike(comment(b, id));
      await a.synchronize();
      expect(comment(a, id).likes, 1);
      await b.publish(game: game, text: '我的评论', rating: 6);
      await b.synchronize();
      await a.synchronize();
      expect(a.projection.ratings(game), {101: 8, 102: 6});
      expect(a.projection.forGame(game, {}).length, 2);
    },
  );
  test(
    'same account on another device contributes one score and one like',
    () async {
      final hub = PublicFixtureHub();
      final a = service(hub, 101, scope: 'device-a'),
          b = service(hub, 101, scope: 'device-b');
      final id = await a.publish(game: game, text: '旧评分', rating: 7);
      await a.synchronize();
      await b.synchronize();
      await b.publish(game: game, text: '最新评分', rating: 9);
      await b.synchronize();
      await a.synchronize();
      await a.toggleLike(comment(a, id));
      await b.synchronize();
      await b.toggleLike(comment(b, id));
      await a.synchronize();
      expect(a.projection.ratings(game), {101: 9});
      expect(comment(a, id).likes, 0);
    },
  );
  test(
    'delete retains other accounts replies; foreign delete is rejected',
    () async {
      final hub = PublicFixtureHub();
      final a = service(hub, 101), b = service(hub, 102);
      final id = await a.publish(game: game, text: '开个话题', rating: 8);
      await a.synchronize();
      await b.synchronize();
      final reply = await b.publish(game: game, text: '我的回复', parent: id);
      await b.synchronize();
      await a.synchronize();
      await expectLater(b.delete(comment(b, id)), throwsStateError);
      await a.delete(comment(a, id));
      await b.synchronize();
      expect(comment(b, id).deleted, isTrue);
      expect(comment(b, reply).deleted, isFalse);
      expect(a.projection.ratings(game), isEmpty);
      await expectLater(
        b.publish(game: game, text: '回复已删除原文', parent: id),
        throwsStateError,
      );
      await b.publish(game: game, text: '回复保留的讨论', parent: reply);
      await b.synchronize();
      expect(b.projection.forGame(game, {}).length, 3);
    },
  );
  test(
    'durable retries survive new service and repeated publish is idempotent',
    () async {
      final hub = PublicFixtureHub()..failure = PrivateFileFailure.unavailable;
      final a = service(hub, 101);
      final id = GameCommentsService.newId();
      await a.publish(game: game, text: '断网内容', operationId: id);
      await a.synchronize();
      expect(a.pendingIds, contains(id));
      expect(a.error, isNotNull);
      final restored = service(hub, 101);
      await restored.initialize();
      await restored.publish(game: game, text: '断网内容', operationId: id);
      hub.failure = null;
      await restored.synchronize();
      expect(restored.pending, isFalse);
      expect(restored.projection.comments.length, 1);
      expect(hub.objects.length, 1);
      await expectLater(
        restored.publish(game: game, text: '不同内容', operationId: id),
        throwsStateError,
      );
    },
  );
  test(
    'upload acknowledgement lost retries same snapshot without duplicate comment',
    () async {
      final hub = PublicFixtureHub();
      final files = _AckLostFiles(hub, 101);
      final a = service(hub, 101, files: files);
      final id = await a.publish(game: game, text: '已上传但确认丢失');
      await a.synchronize();
      expect(a.pendingIds, contains(id));
      files.loseAck = false;
      await a.synchronize();
      expect(a.pending, isFalse);
      expect(a.projection.comments.length, 1);
      expect(
        jsonDecode(hub.objects.values.single.text)['operations'].length,
        1,
      );
    },
  );
  test(
    'foreign author UID and DSM owner mismatch preserve last good list',
    () async {
      final hub = PublicFixtureHub(), a = service(PublicFixtureHub(), 101);
      await a.publish(game: game, text: '本机可靠记录');
      await a.synchronize();
      final b = service(hub, 102);
      final id = await b.publish(game: game, text: '可靠远端');
      await b.synchronize();
      final c = service(hub, 103);
      await c.synchronize();
      final entry = hub.objects.entries.single;
      final data = jsonDecode(entry.value.text);
      data['operations'][0]['uid'] = 999;
      hub.objects[entry.key] = (owner: 102, text: jsonEncode(data));
      await c.synchronize();
      expect(c.error, isNotNull);
      expect(c.projection.comments.containsKey(id), isTrue);
      hub.objects[entry.key] = (owner: 999, text: entry.value.text);
      await c.synchronize();
      expect(c.error, isNotNull);
      expect(c.projection.comments.containsKey(id), isTrue);
    },
  );
  test(
    'identity change while reading cannot mutate inactive service',
    () async {
      final hub = PublicFixtureHub();
      final a = service(hub, 101);
      await a.publish(game: game, text: '远端');
      await a.synchronize();
      var active = true;
      final b = service(hub, 102, active: () => active);
      hub.readGate = Completer<void>();
      final task = b.synchronize();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      active = false;
      hub.readGate!.complete();
      await task;
      expect(b.projection.comments, isEmpty);
      await expectLater(
        b.publish(game: game, text: '错误账号写入'),
        throwsStateError,
      );
      expect(hub.writes, 1);
    },
  );
  test(
    'all write paths reject invalid scores, reply scores and oversized content',
    () async {
      final a = service(PublicFixtureHub(), 101);
      for (final score in [0, 11]) {
        await expectLater(
          a.publish(game: game, text: '错误评分', rating: score),
          throwsFormatException,
        );
      }
      await expectLater(
        a.publish(game: '../unsafe', text: '错误路径'),
        throwsFormatException,
      );
      await expectLater(
        a.publish(game: game, text: 'x' * 1001),
        throwsFormatException,
      );
      final id = await a.publish(game: game, text: '原文');
      await expectLater(
        a.publish(game: game, text: '回复不能评分', parent: id, rating: 8),
        throwsFormatException,
      );
      expect(a.projection.comments.length, 1);
    },
  );
  test('draft storage belongs to account, game and reply', () async {
    final hub = PublicFixtureHub();
    final a = service(hub, 101), b = service(hub, 102);
    await a.saveDraft(game, null, {'text': '草稿', 'rating': null});
    expect((await a.readDraft(game, null))!['text'], '草稿');
    expect(await b.readDraft(game, null), isNull);
    expect(await a.readDraft('catan', null), isNull);
    expect(await a.readDraft(game, GameCommentsService.newId()), isNull);
  });

  test(
    'late stale device snapshot is repaired from durable acknowledged journal',
    () async {
      final hub = PublicFixtureHub();
      final a = service(hub, 101);
      await a.publish(game: game, text: '原记录');
      await a.synchronize();
      final entry = hub.objects.entries.single;
      final newId = await a.publish(game: game, text: '已确认的新记录');
      await a.synchronize();
      expect(a.pending, isFalse);
      // Simulate an older process's upload arriving after the newer upload.
      hub.objects[entry.key] = entry.value;
      await a.synchronize();
      final other = service(hub, 102);
      await other.synchronize();
      expect(other.projection.comments.containsKey(newId), isTrue);
      expect(other.projection.comments.length, 2);
      expect(a.pending, isFalse);
    },
  );
  testWidgets(
    'comment UI fits mobile desktop and large text; desktop can publish without a score',
    (tester) async {
      final a = service(PublicFixtureHub(), 101);
      await a.publish(game: game, text: '这是第一条桌游体验', rating: 8);
      await a.synchronize();
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final width in [320.0, 390.0, 1100.0]) {
        await tester.binding.setSurfaceSize(Size(width, 1000));
        for (final palette in [
          PaletteRegistry.warmwoodStudy,
          PaletteRegistry.classic,
        ]) {
          await tester.pumpWidget(
            MaterialApp(
              key: UniqueKey(),
              theme: AppTheme.buildTheme(palette),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  size: Size(width, 1000),
                  textScaler: const TextScaler.linear(2),
                ),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: GameCommentsPanel(
                    gameSlug: game,
                    gameTitle: '卡卡颂',
                    service: a,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('这是第一条桌游体验'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          theme: AppTheme.buildTheme(PaletteRegistry.warmwoodStudy),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(size: const Size(1100, 1000)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: GameCommentsPanel(
                gameSlug: game,
                gameTitle: '卡卡颂',
                service: a,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('comment-input')),
        '不评分也能发表',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('comment-send')));
      await tester.pumpAndSettle();
      expect(find.text('不评分也能发表'), findsOneWidget);
      expect(a.projection.ratings(game), {101: 8});
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('guests get a login entry instead of fake comments', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildTheme(PaletteRegistry.warmwoodStudy),
        home: const Scaffold(
          body: GameCommentsPanel(gameSlug: game, gameTitle: '卡卡颂'),
        ),
      ),
    );
    expect(find.text('登录后查看评论与桌友评分'), findsOneWidget);
    expect(find.byKey(const ValueKey('comment-input')), findsNothing);
    expect(find.text('登录'), findsOneWidget);
  });

  testWidgets(
    'five stars support ten points, clearing, and send feedback stays in button',
    (tester) async {
      final hub = PublicFixtureHub();
      final a = service(hub, 101);
      await a.publish(game: game, text: '已有评论');
      await a.synchronize();
      await tester.binding.setSurfaceSize(const Size(1100, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.buildTheme(PaletteRegistry.warmwoodStudy),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(size: const Size(1100, 900)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: GameCommentsPanel(
                gameSlug: game,
                gameTitle: '卡卡颂',
                service: a,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<int>), findsNothing);
      expect(find.textContaining('桌友评分'), findsNothing);
      expect(find.textContaining('暂无评分'), findsNothing);
      final star = tester.getRect(
        find.byKey(const ValueKey('comment-rating-star-5')),
      );
      final fullPoint = Offset(star.left + star.width * .75, star.center.dy);
      await tester.tapAt(fullPoint);
      await tester.pumpAndSettle();
      expect((await a.readDraft(game, null))!['rating'], 10);
      await tester.tapAt(fullPoint);
      await tester.pumpAndSettle();
      expect((await a.readDraft(game, null))!['rating'], isNull);
      await tester.tapAt(Offset(star.left + star.width * .25, star.center.dy));
      await tester.pumpAndSettle();
      expect((await a.readDraft(game, null))!['rating'], 9);
      expect(find.byIcon(Icons.star_half_rounded), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('comment-input')),
        '九分体验',
      );
      await tester.pumpAndSettle();
      hub.readGate = Completer<void>();
      await tester.tap(find.byKey(const ValueKey('comment-send')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('comment-send')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(find.text('有内容等待发送'), findsNothing);
      hub.readGate!.complete();
      await tester.pumpAndSettle();
      expect(a.projection.ratings(game), {101: 9});
      expect(find.text('九分体验'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mobile publish reveals own comment in hot list and reply composer has no score',
    (tester) async {
      final a = service(PublicFixtureHub(), 101);
      await a.initialize();
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(390, 844));
      final root = await a.publish(game: game, text: '原评论');
      await a.synchronize();
      await a.toggleLike(comment(a, root));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.buildTheme(PaletteRegistry.warmwoodStudy),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(size: const Size(390, 844)),
            child: child!,
          ),
          home: GameCommentsPage(gameSlug: game, gameTitle: '卡卡颂', service: a),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('写评论'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('comment-rating')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('comment-input')),
        '刚刚发表的体验',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('comment-send')));
      await tester.pumpAndSettle();
      expect(find.text('刚刚发表的体验'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('刚刚发表的体验')).dy,
        lessThan(tester.getTopLeft(find.text('原评论')).dy),
      );
      await tester.tap(find.text('回复').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('comment-rating')), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('comment-input')),
        '楼中楼回复',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('comment-send')));
      await tester.pumpAndSettle();
      expect(find.textContaining('楼中楼回复'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _AckLostFiles extends MemoryPublicFiles {
  _AckLostFiles(super.hub, super.uid);
  bool loseAck = true;
  @override
  Future<void> replaceOwn(String relativePath, String content) async {
    await super.replaceOwn(relativePath, content);
    if (loseAck) {
      throw const PrivateFileException(PrivateFileFailure.unavailable);
    }
  }
}
