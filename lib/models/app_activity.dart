/// A user-visible event shown in the desktop notification center.
///
/// Activities are intentionally separate from live connectivity state. A
/// connectivity status answers “what is true now?”, while an activity records
/// “what happened and when?” so a refresh or completed AI answer does not get
/// confused with a button that starts another refresh.
enum AppActivityKind {
  serviceRefresh,
  aiCompleted,
  aiFailed,
  libraryUpdate,
  libraryLoadFailed,
  info,
}

class AppActivity {
  const AppActivity({
    required this.id,
    required this.kind,
    required this.title,
    required this.message,
    required this.createdAt,
    this.isRead = false,
    this.conversationId,
    this.messageId,
  });

  final String id;
  final AppActivityKind kind;
  final String title;
  final String message;
  final DateTime createdAt;
  final bool isRead;

  /// Stable assistant session to open when this activity is selected.
  ///
  /// Non-assistant activities leave this null. Older persisted activities also
  /// remain valid because these fields are optional during migration.
  final String? conversationId;

  /// Optional stable answer message to reveal after opening [conversationId].
  final String? messageId;

  AppActivity copyWith({
    String? id,
    AppActivityKind? kind,
    String? title,
    String? message,
    DateTime? createdAt,
    bool? isRead,
    String? conversationId,
    String? messageId,
  }) {
    return AppActivity(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      message: message ?? this.message,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
      conversationId: conversationId ?? this.conversationId,
      messageId: messageId ?? this.messageId,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'kind': kind.name,
      'title': title,
      'message': message,
      'createdAt': createdAt.toIso8601String(),
      'isRead': isRead,
      if (conversationId != null && conversationId!.trim().isNotEmpty)
        'conversationId': conversationId,
      if (messageId != null && messageId!.trim().isNotEmpty)
        'messageId': messageId,
    };
  }

  factory AppActivity.fromMap(Map<String, dynamic> map) {
    final String rawId = map['id'] is String
        ? (map['id'] as String).trim()
        : '';
    final String rawCreatedAt = map['createdAt'] is String
        ? map['createdAt'] as String
        : '';
    final DateTime createdAt =
        DateTime.tryParse(rawCreatedAt) ?? DateTime.now();
    return AppActivity(
      id: rawId.isNotEmpty
          ? rawId
          : 'activity-${createdAt.microsecondsSinceEpoch}',
      kind: _parseKind(map['kind'] is String ? map['kind'] as String : null),
      title: map['title'] is String ? (map['title'] as String).trim() : '',
      message: map['message'] is String
          ? (map['message'] as String).trim()
          : '',
      createdAt: createdAt,
      isRead: map['isRead'] is bool ? map['isRead'] as bool : false,
      conversationId: _optionalString(map['conversationId']),
      messageId: _optionalString(map['messageId']),
    );
  }

  static String? _optionalString(Object? value) {
    if (value is! String) return null;
    final String normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  static AppActivityKind _parseKind(String? value) {
    for (final AppActivityKind kind in AppActivityKind.values) {
      if (kind.name == value) {
        return kind;
      }
    }
    return AppActivityKind.info;
  }
}
