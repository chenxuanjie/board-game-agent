import 'chat_message.dart';

/// The context used by an assistant conversation.
enum AiConversationScope { global, game }

/// A durable assistant session.
///
/// The controller owns the mutable message list. Consumers receive copies of
/// this model, so UI code can render and select sessions without reaching into
/// the controller's internal store.
class AiConversation {
  AiConversation({
    required this.id,
    required this.title,
    required this.scope,
    required this.createdAt,
    required this.updatedAt,
    this.gameId,
    List<ChatMessage> messages = const <ChatMessage>[],
  }) : messages = List<ChatMessage>.from(messages);

  final String id;
  final String title;
  final AiConversationScope scope;
  final String? gameId;
  final DateTime createdAt;
  DateTime updatedAt;
  final List<ChatMessage> messages;

  bool get isGlobal => scope == AiConversationScope.global;
  int get messageCount => messages.length;

  AiConversation copyWith({
    String? id,
    String? title,
    AiConversationScope? scope,
    String? gameId,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<ChatMessage>? messages,
  }) {
    return AiConversation(
      id: id ?? this.id,
      title: title ?? this.title,
      scope: scope ?? this.scope,
      gameId: gameId ?? this.gameId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: messages ?? this.messages,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'scope': scope.name,
      if (gameId != null) 'gameId': gameId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'messages': messages
          .map((ChatMessage message) => message.toMap())
          .toList(),
    };
  }

  factory AiConversation.fromMap(Map<String, dynamic> map) {
    final String id = (map['id'] as String? ?? '').trim();
    final AiConversationScope scope = _parseScope(map['scope'] as String?, id);
    final String? gameId = (map['gameId'] as String?)?.trim();
    final List<ChatMessage> messages =
        (map['messages'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(ChatMessage.fromMap)
            .toList();
    final DateTime now = DateTime.now();
    return AiConversation(
      id: id,
      title: (map['title'] as String?)?.trim().isNotEmpty == true
          ? (map['title'] as String).trim()
          : (scope == AiConversationScope.global ? '通用 AI 助手' : '规则问答'),
      scope: scope,
      gameId: gameId?.isEmpty == true ? null : gameId,
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(map['updatedAt'] as String? ?? '') ?? now,
      messages: messages,
    );
  }

  static AiConversationScope _parseScope(String? value, String id) {
    if (value == AiConversationScope.global.name || id == 'global') {
      return AiConversationScope.global;
    }
    return AiConversationScope.game;
  }
}
