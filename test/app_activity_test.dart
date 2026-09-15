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

  test('library load failures persist as notification activity kinds', () {
    final AppActivity original = AppActivity(
      id: 'activity-library-failed',
      kind: AppActivityKind.libraryLoadFailed,
      title: '资料加载失败',
      message: '连接超时。打开资料库可重试。',
      createdAt: DateTime.utc(2026, 9, 14),
    );

    final AppActivity restored = AppActivity.fromMap(original.toMap());

    expect(restored.kind, AppActivityKind.libraryLoadFailed);
    expect(restored.title, original.title);
    expect(restored.message, original.message);
  });

  test('keeps only the newest notification for each activity kind', () {
    final List<AppActivity> compacted = latestActivitiesByKind(<AppActivity>[
      AppActivity(
        id: 'old-library',
        kind: AppActivityKind.libraryLoadFailed,
        title: '资料加载失败',
        message: '旧错误',
        createdAt: DateTime.utc(2026, 9, 14, 8),
      ),
      AppActivity(
        id: 'ai-latest',
        kind: AppActivityKind.aiCompleted,
        title: 'AI 已完成回答',
        message: '最新回答',
        createdAt: DateTime.utc(2026, 9, 14, 10),
        conversationId: 'game:cabo',
        messageId: 'answer-2',
      ),
      AppActivity(
        id: 'new-library',
        kind: AppActivityKind.libraryLoadFailed,
        title: '资料加载失败',
        message: '最新错误',
        createdAt: DateTime.utc(2026, 9, 14, 11),
      ),
      AppActivity(
        id: 'ai-old',
        kind: AppActivityKind.aiCompleted,
        title: 'AI 已完成回答',
        message: '旧回答',
        createdAt: DateTime.utc(2026, 9, 14, 9),
      ),
    ]);

    expect(compacted, hasLength(2));
    expect(compacted.first.id, 'new-library');
    final AppActivity ai = compacted.singleWhere(
      (AppActivity activity) => activity.kind == AppActivityKind.aiCompleted,
    );
    expect(ai.id, 'ai-latest');
    expect(ai.conversationId, 'game:cabo');
    expect(ai.messageId, 'answer-2');
  });
}
