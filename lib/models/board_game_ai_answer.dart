import 'answer_source.dart';
import 'evidence_chunk.dart';

/// Structured output from the board-game AI domain service.
class BoardGameAiAnswer {
  BoardGameAiAnswer({
    required this.text,
    required this.source,
    List<EvidenceChunk> evidence = const <EvidenceChunk>[],
  }) : evidence = List<EvidenceChunk>.unmodifiable(evidence);

  final String text;
  final AnswerSource source;
  final List<EvidenceChunk> evidence;
}
