import 'answer_source.dart';
import 'evidence_chunk.dart';
import 'rule_citation.dart';

/// Structured output from the board-game AI domain service.
class BoardGameAiAnswer {
  BoardGameAiAnswer({
    required this.text,
    required this.source,
    List<EvidenceChunk> evidence = const <EvidenceChunk>[],
    List<RuleCitation> citations = const <RuleCitation>[],
  }) : evidence = List<EvidenceChunk>.unmodifiable(evidence),
       citations = List<RuleCitation>.unmodifiable(citations);

  final String text;
  final AnswerSource source;
  final List<EvidenceChunk> evidence;
  final List<RuleCitation> citations;
}
