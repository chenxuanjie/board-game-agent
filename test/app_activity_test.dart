import 'package:board_game_agent/models/app_activity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('activity model round trips kind, message, and read state', () {
    final DateTime createdAt = DateTime.utc(2026, 8, 27, 6, 30);
    final AppActivity original = AppActivity(
      id: 'activity-1',
      kind: AppActivityKind.aiCompleted,
      title: 'AI 已完成回答',
      message: '已完成《波多黎各》的新回答。',
      createdAt: createdAt,
      isRead: true,
      conversationId: 'game:puerto-rico',
      messageId: 'answer-1',
    );

    final AppActivity restored = AppActivity.fromMap(original.toMap());

    expect(restored.id, original.id);
    expect(restored.kind, AppActivityKind.aiCompleted);
    expect(restored.title, original.title);
    expect(restored.message, original.message);
    expect(restored.createdAt, createdAt);
    expect(restored.isRead, isTrue);
    expect(restored.conversationId, 'game:puerto-rico');
    expect(restored.messageId, 'answer-1');
  });

  test('malformed kind falls back to informational activity', () {
    final AppActivity restored = AppActivity.fromMap(<String, dynamic>{
      'id': 'activity-2',
      'kind': 'not-a-kind',
      'title': '提示',
      'message': '内容',
    });

    expect(restored.kind, AppActivityKind.info);
    expect(restored.isRead, isFalse);
    expect(restored.conversationId, isNull);
    expect(restored.messageId, isNull);
  });
}
