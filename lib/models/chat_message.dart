import 'answer_source.dart';
import 'evidence_chunk.dart';

enum ChatRole { user, assistant }

enum ChatMessageState { complete, streaming, failed }

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.timestamp,
    this.source,
    List<EvidenceChunk> evidence = const <EvidenceChunk>[],
    this.state = ChatMessageState.complete,
    this.canRetry = false,
    this.retryPrompt,
  }) : evidence = List<EvidenceChunk>.unmodifiable(evidence);

  final String id;
  final ChatRole role;
  final String text;
  final DateTime timestamp;
  final AnswerSource? source;
  final List<EvidenceChunk> evidence;
  final ChatMessageState state;
  final bool canRetry;
  final String? retryPrompt;

  bool get isStreaming => state == ChatMessageState.streaming;
  bool get isFailed => state == ChatMessageState.failed;

  ChatMessage copyWith({
    String? text,
    AnswerSource? source,
    List<EvidenceChunk>? evidence,
    ChatMessageState? state,
    bool? canRetry,
    String? retryPrompt,
    DateTime? timestamp,
  }) {
    return ChatMessage(
      id: id,
      role: role,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      source: source ?? this.source,
      evidence: evidence ?? this.evidence,
      state: state ?? this.state,
      canRetry: canRetry ?? this.canRetry,
      retryPrompt: retryPrompt ?? this.retryPrompt,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'role': role.name,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      if (source != null) 'source': source!.code,
      if (evidence.isNotEmpty)
        'evidence': evidence.map((EvidenceChunk item) => item.toMap()).toList(),
      'state': state.name == ChatMessageState.streaming.name
          ? ChatMessageState.complete.name
          : state.name,
      if (canRetry) 'canRetry': true,
      if (retryPrompt != null) 'retryPrompt': retryPrompt,
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
      source: _parseSource(map['source'] as String?),
      evidence: (map['evidence'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(EvidenceChunk.fromMap)
          .toList(),
      state: _parseState(map['state'] as String?),
      canRetry: map['canRetry'] as bool? ?? false,
      retryPrompt: map['retryPrompt'] as String?,
    );
  }

  static AnswerSource? _parseSource(String? value) {
    for (final AnswerSource source in AnswerSource.values) {
      if (source.code == value) return source;
    }
    return null;
  }

  static ChatMessageState _parseState(String? value) {
    for (final ChatMessageState state in ChatMessageState.values) {
      if (state.name == value && state != ChatMessageState.streaming) {
        return state;
      }
    }
    return ChatMessageState.complete;
  }
}
