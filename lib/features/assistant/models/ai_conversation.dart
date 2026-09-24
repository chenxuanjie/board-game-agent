import 'chat_message.dart';
import 'ai_run.dart';

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
    this.opened = true,
    this.lastRun,
    List<ChatMessage> messages = const <ChatMessage>[],
  }) : messages = List<ChatMessage>.from(messages);

  final String id;
  final String title;
  final AiConversationScope scope;
  final String? gameId;

  /// Whether the user explicitly entered this assistant context.
  ///
  /// New sessions are marked opened immediately, even when they only contain
  /// the automatic greeting. Older stores without this field derive the value
  /// from the presence of a user message during migration.
  final bool opened;

  /// Latest local Run checkpoint, restored for activity continuity.
  AiRunCheckpoint? lastRun;
  final DateTime createdAt;
  DateTime updatedAt;
  final List<ChatMessage> messages;

  bool get isGlobal => scope == AiConversationScope.global;
  int get messageCount => messages.length;
  bool get hasUserMessages =>
      messages.any((ChatMessage message) => message.role == ChatRole.user);

  /// Legacy sessions with no persisted opened marker are treated as
  /// unstarted by the restore migration. New sessions are opened on entry.
  bool get isUnstarted => !opened;

  AiConversation copyWith({
    String? id,
    String? title,
    AiConversationScope? scope,
    String? gameId,
    bool? opened,
    AiRunCheckpoint? lastRun,
    bool clearLastRun = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<ChatMessage>? messages,
  }) {
    return AiConversation(
      id: id ?? this.id,
      title: title ?? this.title,
      scope: scope ?? this.scope,
      gameId: gameId ?? this.gameId,
      opened: opened ?? this.opened,
      lastRun: clearLastRun ? null : (lastRun ?? this.lastRun),
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
      'opened': opened,
      if (lastRun != null) 'lastRun': lastRun!.toMap(),
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
    final bool opened =
        map['opened'] as bool? ??
        messages.any((ChatMessage message) => message.role == ChatRole.user);
    final DateTime now = DateTime.now();
    return AiConversation(
      id: id,
      title: (map['title'] as String?)?.trim().isNotEmpty == true
          ? (map['title'] as String).trim()
          : (scope == AiConversationScope.global ? '通用 AI 助手' : '规则问答'),
      scope: scope,
      gameId: gameId?.isEmpty == true ? null : gameId,
      opened: opened,
      lastRun: map['lastRun'] is Map
          ? AiRunCheckpoint.fromMap(
              Map<String, dynamic>.from(map['lastRun'] as Map),
            )
          : null,
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
