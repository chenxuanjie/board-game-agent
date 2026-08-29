import 'package:board_game_agent/models/ai_conversation.dart';
import 'package:board_game_agent/models/chat_message.dart';
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
}
