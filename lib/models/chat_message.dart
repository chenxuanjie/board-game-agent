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
}
