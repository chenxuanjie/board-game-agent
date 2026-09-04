import 'package:board_game_agent/models/ai_conversation.dart';
import 'package:board_game_agent/models/ai_run.dart';
import 'package:board_game_agent/models/chat_message.dart';
import 'package:board_game_agent/models/rule_citation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('conversation model round trips scope, metadata, and messages', () {
    final DateTime createdAt = DateTime.utc(2026, 8, 27, 10);
    final DateTime updatedAt = DateTime.utc(2026, 8, 27, 10, 2);
    final AiConversation original = AiConversation(
      id: 'game:cabo',
      title: 'Cabo助手',
      scope: AiConversationScope.game,
      gameId: 'cabo',
      createdAt: createdAt,
      updatedAt: updatedAt,
      messages: <ChatMessage>[
        ChatMessage(
          id: 'message-1',
          role: ChatRole.user,
          text: '什么时候可以宣告 Cabo？',
          timestamp: updatedAt,
        ),
      ],
    );

    final AiConversation restored = AiConversation.fromMap(original.toMap());

    expect(restored.id, original.id);
    expect(restored.title, original.title);
    expect(restored.scope, AiConversationScope.game);
    expect(restored.gameId, 'cabo');
    expect(restored.opened, isTrue);
    expect(restored.createdAt, createdAt);
    expect(restored.updatedAt, updatedAt);
    expect(restored.messages, hasLength(1));
    expect(restored.messages.single.text, '什么时候可以宣告 Cabo？');
  });

  test('legacy IDs infer global and game scopes', () {
    final AiConversation global = AiConversation.fromMap(<String, dynamic>{
      'id': 'global',
      'messages': <dynamic>[],
    });
    final AiConversation game = AiConversation.fromMap(<String, dynamic>{
      'id': 'game:puerto-rico',
      'messages': <dynamic>[],
    });

    expect(global.scope, AiConversationScope.global);
    expect(game.scope, AiConversationScope.game);
  });

  test('entered greeting-only sessions stay opened without user messages', () {
    final DateTime now = DateTime.utc(2026, 8, 27, 11);
    final AiConversation greetingOnly = AiConversation(
      id: 'game:cabo',
      title: 'Cabo助手',
      scope: AiConversationScope.game,
      gameId: 'cabo',
      opened: true,
      createdAt: now,
      updatedAt: now,
      messages: <ChatMessage>[
        ChatMessage(
          id: 'greeting',
          role: ChatRole.assistant,
          text: '你好',
          timestamp: now,
        ),
      ],
    );
    final AiConversation used = AiConversation(
      id: 'game:cabo',
      title: 'Cabo助手',
      scope: AiConversationScope.game,
      gameId: 'cabo',
      createdAt: now,
      updatedAt: now,
      messages: <ChatMessage>[
        ChatMessage(
          id: 'question',
          role: ChatRole.user,
          text: '什么时候结束？',
          timestamp: now,
        ),
      ],
    );

    expect(greetingOnly.hasUserMessages, isFalse);
    expect(greetingOnly.isUnstarted, isFalse);
    expect(used.hasUserMessages, isTrue);
    expect(used.isUnstarted, isFalse);
  });

  test('legacy greeting-only maps are treated as unopened', () {
    final AiConversation restored = AiConversation.fromMap(<String, dynamic>{
      'id': 'game:cabo',
      'scope': 'game',
      'gameId': 'cabo',
      'messages': <dynamic>[
        <String, dynamic>{
          'id': 'greeting',
          'role': 'assistant',
          'text': '你好',
          'timestamp': '2026-08-27T11:00:00.000Z',
        },
      ],
    });

    expect(restored.opened, isFalse);
    expect(restored.isUnstarted, isTrue);
  });

  test('persists a safe run checkpoint without streaming answer text', () {
    final DateTime startedAt = DateTime.utc(2026, 8, 27, 12);
    final AiRunCheckpoint checkpoint = AiRunCheckpoint(
      runId: 'run-1',
      status: AiRunStatus.failed,
      contextKey: 'game:cabo|provider-fingerprint',
      sessionId: 'game:cabo|provider-fingerprint',
      model: 'test-model',
      startedAt: startedAt,
      completedAt: startedAt.add(const Duration(seconds: 2)),
      errorCode: 'network_timeout',
      errorMessage: '网络请求超时',
      events: <AiRunEvent>[
        AiRunEvent(
          runId: 'run-1',
          sequence: 0,
          type: AiRunEventType.stageCompleted,
          timestamp: startedAt.add(const Duration(seconds: 1)),
          stageId: 'official',
          delta: '不应写入检查点的半截 JSON',
          stageResult: const AiStageResult(
            stageId: 'official',
            scope: AiKnowledgeScope.official(gameId: 'cabo'),
            status: AiStageStatus.insufficient,
            inspectedSources: <RuleCitation>[
              RuleCitation(
                sourceType: 'official',
                sourceId: 'rules',
                title: 'Cabo 规则书',
                page: 3,
                quote: '不应写入本地检查点的原文',
              ),
            ],
          ),
        ),
      ],
    );

    final Map<String, dynamic> encoded = checkpoint.toMap();
    final String encodedText = encoded.toString();
    expect(encodedText, isNot(contains('半截 JSON')));
    expect(encodedText, isNot(contains('不应写入本地检查点的原文')));

    final AiRunCheckpoint restored = AiRunCheckpoint.fromMap(encoded);
    expect(restored.status, AiRunStatus.failed);
    expect(restored.contextKey, checkpoint.contextKey);
    expect(restored.events, hasLength(1));
    expect(restored.events.single.delta, isEmpty);
    expect(
      restored.events.single.stageResult?.inspectedSources.single.title,
      'Cabo 规则书',
    );
    expect(restored.events.single.stageResult?.inspectedSources.single.page, 3);
  });
}
