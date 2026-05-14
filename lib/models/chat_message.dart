enum ChatRole {
  user,
  assistant,
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.timestamp,
  });

  final String id;
  final ChatRole role;
  final String text;
  final DateTime timestamp;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'role': role.name,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'] as String? ?? '',
      role: ChatRole.values.firstWhere(
        (ChatRole role) => role.name == map['role'],
        orElse: () => ChatRole.assistant,
      ),
      text: map['text'] as String? ?? '',
      timestamp:
          DateTime.tryParse(map['timestamp'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
