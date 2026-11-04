import 'dart:convert';

import 'package:app_client/app_client.dart';
import 'package:app_identity/app_identity.dart';
import 'package:board_game_agent/features/community/services/game_comments_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/failing_preferences_store.dart';

const parentId = 'c11111111111111111111111111111111';
const childId = 'c22222222222222222222222222222222';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'permanent parent rejection persists and independent comments proceed across restart',
    () async {
      final fixture = QueueFixture();
      fixture.failures[parentId] = (409, 'comment_parent_unavailable');
      var service = fixture.service();
      await service.publish(
        game: 'cabo',
        text: '失效的回复',
        parent: childId,
        operationId: parentId,
      );
      final good = await service.publish(game: 'cabo', text: '正常评论');
      await service.synchronize();
      expect(fixture.sent.map((c) => c['id']), [parentId, good]);
      expect(service.pendingIds, {parentId});
      expect(service.issues.single.code, 'comment_parent_unavailable');
      expect(service.error, isNull);
      await service.drain();
      service.dispose();
      service = fixture.service();
      await service.initialize();
      expect(service.issues.single.text, '失效的回复');
      final next = await service.publish(game: 'cabo', text: '重启后的评论');
      await service.synchronize();
      expect(fixture.sent.map((c) => c['id']), [parentId, good, next]);
      expect(service.pendingIds, {parentId});
    },
  );

  test(
    'rejected parent blocks its descendants and later same-comment operations only',
    () async {
      SharedPreferences.setMockInitialValues({
        'board.community.api.v1.alice': jsonEncode({
          'commands': [
            command(parentId, text: '父评论'),
            command(childId, text: '子回复', parent: parentId),
            command('like-child', target: childId, action: 'like'),
            command('delete-parent', target: parentId, action: 'delete'),
            command('c33333333333333333333333333333333', text: '独立评论'),
          ],
          'optimistic': [],
        }),
      });
      final fixture = QueueFixture()
        ..failures[parentId] = (409, 'comment_rejected');
      final service = fixture.service();
      await service.synchronize();
      expect(fixture.sent.map((c) => c['id']), [
        parentId,
        'c33333333333333333333333333333333',
      ]);
      expect(service.issues.map((i) => i.id), [
        parentId,
        childId,
        'like-child',
        'delete-parent',
      ]);
      await service.withdrawRejected(parentId);
      await service.synchronize();
      expect(fixture.sent, hasLength(2));
      expect(
        service.issues.every(
          (i) =>
              i.code == 'comment_dependency_changed' ||
              i.code == 'comment_dependency_blocked',
        ),
        isTrue,
      );
      final draft = await service.readDraft('cabo', null);
      expect(draft!['text'], '父评论');
      expect(draft['enqueued'], isFalse);
      service.dispose();
      final restarted = fixture.service();
      await restarted.synchronize();
      expect(fixture.sent, hasLength(2));
      expect(restarted.issues, hasLength(3));
    },
  );

  test(
    'a pending parent is committed before replies even when queued later',
    () async {
      final fixture = QueueFixture(), service = fixture.service();
      await service.publish(
        game: 'cabo',
        text: '回复',
        parent: parentId,
        operationId: childId,
      );
      await service.publish(game: 'cabo', text: '父评论', operationId: parentId);
      await service.synchronize();
      expect(fixture.sent.map((c) => c['id']), [parentId, childId]);
      expect(service.pending, isFalse);
    },
  );

  for (final failure in [
    (409, 'mutation_reused'),
    (409, 'unknown_conflict'),
    (401, 'session_rejected'),
    (503, 'unavailable'),
  ]) {
    test(
      'unclassified or transient $failure retains queue and idempotency ID',
      () async {
        final fixture = QueueFixture()..failures[parentId] = failure;
        final service = fixture.service();
        await service.publish(game: 'cabo', text: '内容', operationId: parentId);
        final second = await service.publish(game: 'cabo', text: '下一条');
        await service.synchronize();
        expect(service.issues, isEmpty);
        expect(service.pendingIds, {parentId, second});
        expect(fixture.sent.map((c) => c['id']), [parentId]);
        expect(service.error, isNotNull);
        await expectLater(service.withdrawRejected(parentId), throwsStateError);
        fixture.failures.clear();
        await service.synchronize();
        expect(fixture.sent.map((c) => c['id']), [parentId, parentId, second]);
        expect(service.pending, isFalse);
      },
    );
  }

  test(
    'lost acknowledgement retries the original command instead of classifying it as rejection',
    () async {
      final fixture = QueueFixture()..dropReply = true;
      final service = fixture.service();
      await service.publish(game: 'cabo', text: '幂等评论', operationId: parentId);
      await service.synchronize();
      expect(service.pendingIds, {parentId});
      expect(service.issues, isEmpty);
      fixture.dropReply = false;
      await service.synchronize();
      expect(fixture.sent.map((c) => c['id']), [parentId, parentId]);
      expect(service.pending, isFalse);
    },
  );

  test(
    'expired token preserves commands without starting or automatically repeating HTTP',
    () async {
      final fixture = QueueFixture()
        ..tokenFailure = const IdentityFailure(
          IdentityFailureCode.sessionRejected,
        );
      final service = fixture.service();
      await service.publish(
        game: 'cabo',
        text: '等待重新登录',
        operationId: parentId,
      );
      await service.synchronize();
      expect(fixture.sent, isEmpty);
      expect(service.pendingIds, {parentId});
      expect(service.issues, isEmpty);
      expect(service.error, contains('登录'));
      await Future<void>.delayed(const Duration(milliseconds: 2100));
      expect(fixture.tokenCalls, 1);
      fixture.tokenFailure = null;
      await service.synchronize();
      expect(fixture.sent.single['id'], parentId);
      expect(service.pending, isFalse);
    },
  );

  test(
    'withdrawing a failed reply retains editable text and a new ID for root resubmission',
    () async {
      final fixture = QueueFixture()
        ..failures[parentId] = (409, 'comment_parent_unavailable');
      final service = fixture.service();
      await service.publish(
        game: 'cabo',
        text: '保留正文',
        parent: childId,
        operationId: parentId,
      );
      await service.synchronize();
      await service.withdrawRejected(parentId, asRoot: true);
      final draft = (await service.readDraft('cabo', childId))!;
      expect(draft['id'], isNot(parentId));
      expect(draft['text'], '保留正文');
      expect(draft['asRoot'], isTrue);
      expect(draft['enqueued'], isFalse);
      expect(service.pending, isFalse);
      await service.publish(
        game: 'cabo',
        text: '修改后正文',
        operationId: draft['id'] as String,
      );
      await service.synchronize();
      expect(fixture.sent.last['parent_id'], isNull);
      expect(fixture.sent.last['body'], '修改后正文');
    },
  );

  test(
    'withdrawal storage failures retain the rejected command and allow recovery',
    () async {
      final store = FailingPreferencesStore()..install();
      final fixture = QueueFixture()
        ..failures[parentId] = (409, 'comment_rejected');
      final service = fixture.service();
      await service.publish(game: 'cabo', text: '不能丢失', operationId: parentId);
      await service.synchronize();
      store.reject = (key) => key.contains('.draft.');
      await expectLater(service.withdrawRejected(parentId), throwsStateError);
      expect(service.pendingIds, {parentId});
      store.reject = (key) => key.endsWith('.alice');
      await expectLater(service.withdrawRejected(parentId), throwsStateError);
      expect(service.issues.single.id, parentId);
      store.reject = (_) => false;
      await service.withdrawRejected(parentId);
      await service.drain();
      await (await SharedPreferences.getInstance()).reload();
      expect((await service.readDraft('cabo', null))!['text'], '不能丢失');
      expect(service.pending, isFalse);
    },
  );

  test(
    'recovery never overwrites an unrelated draft or applies after scope invalidation',
    () async {
      final fixture = QueueFixture()
        ..failures[parentId] = (409, 'comment_rejected');
      final service = fixture.service();
      await service.publish(
        game: 'cabo',
        text: '被拒绝的内容',
        operationId: parentId,
      );
      await service.synchronize();
      await service.saveDraft('cabo', null, {'id': childId, 'text': '另外的草稿'});
      await expectLater(service.withdrawRejected(parentId), throwsStateError);
      expect((await service.readDraft('cabo', null))!['text'], '另外的草稿');
      fixture.active = false;
      await expectLater(service.withdrawRejected(parentId), throwsStateError);
      expect(service.pendingIds, {parentId});
    },
  );
}

Map<String, dynamic> command(
  String id, {
  String? target,
  String action = 'publish',
  String text = '',
  String? parent,
}) => {
  'id': id,
  'action': action,
  'game_slug': 'cabo',
  'comment_id': target ?? id,
  if (action == 'publish') ...{
    'body': text,
    'rating': null,
    'parent_id': parent,
  },
  if (action == 'like') 'active': true,
};

class QueueFixture {
  QueueFixture() {
    client = AppJsonClient(
      Uri.parse('https://api.test'),
      applicationId: 'board_game_agent',
      client: MockClient((r) async {
        if (r.method == 'GET') {
          return http.Response(
            jsonEncode({'comments': [], 'next_cursor': null}),
            200,
          );
        }
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        sent.add(body);
        expect(body.keys, isNot(contains('rejection')));
        if (dropReply) throw http.ClientException('lost acknowledgement');
        final failure = failures[body['id']];
        if (failure != null) {
          return http.Response(jsonEncode({'detail': failure.$2}), failure.$1);
        }
        return http.Response(
          jsonEncode({'id': body['id'], 'status': 'applied'}),
          200,
        );
      }),
    );
    addTearDown(client.close);
  }
  late final AppJsonClient client;
  final sent = <Map<String, dynamic>>[];
  final failures = <String, (int, String)>{};
  bool active = true, dropReply = false;
  IdentityFailure? tokenFailure;
  int tokenCalls = 0;
  GameCommentsService service() {
    final service = GameCommentsService(
      client: client,
      scope: 'alice',
      uid: 'alice',
      token: () async {
        tokenCalls++;
        if (tokenFailure case final failure?) throw failure;
        return 'token';
      },
      isActive: () => active,
      displayName: () => 'Alice',
    );
    // Tests that reconstruct a service dispose the older one explicitly.
    addTearDown(service.dispose);
    return service;
  }
}
