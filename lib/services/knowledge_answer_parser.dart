import 'dart:convert';

import '../models/answer_source.dart';
import '../models/app_language.dart';
import '../models/board_game_ai_answer.dart';
import '../models/evidence_chunk.dart';

/// Parses the constrained response used by the knowledge-only pass.
class KnowledgeAnswerParser {
  BoardGameAiAnswer parse(
    String input, {
    required AppLanguage language,
    required List<EvidenceChunk> availableEvidence,
  }) {
    final String stripped = _stripCodeFences(input.trim());
    final Map<String, dynamic>? json = _decodeObject(stripped);
    if (json != null) {
      final String status = _stringValue(json['status']).toLowerCase();
      final String answer = _stringValue(json['answer']);
      if (status == 'answered' && answer.isNotEmpty) {
        return BoardGameAiAnswer(
          text: answer,
          source: AnswerSource.rulebook,
          evidence: _resolveEvidence(
            json,
            availableEvidence,
            useAllWhenMissing: true,
          ),
        );
      }
      if (status == 'unknown') {
        return BoardGameAiAnswer(
          text: answer.isEmpty ? _unknownReply(language) : answer,
          source: AnswerSource.insufficient,
          evidence: _resolveEvidence(
            json,
            availableEvidence,
            useAllWhenMissing: false,
          ),
        );
      }
    }

    final RegExp statusPattern = RegExp(
      r'STATUS\s*:\s*([A-Za-z_]+)',
      caseSensitive: false,
    );
    final RegExp answerPattern = RegExp(
      r'ANSWER\s*:\s*([\s\S]+)$',
      caseSensitive: false,
    );
    final RegExpMatch? statusMatch = statusPattern.firstMatch(stripped);
    final RegExpMatch? answerMatch = answerPattern.firstMatch(stripped);
    final String status =
        statusMatch?.group(1)?.trim().toLowerCase() ?? 'unknown';
    final String answer = answerMatch?.group(1)?.trim() ?? '';

    if (status == 'answered' && answer.isNotEmpty) {
      return BoardGameAiAnswer(
        text: answer,
        source: AnswerSource.rulebook,
        evidence: availableEvidence,
      );
    }

    return BoardGameAiAnswer(
      text: answer.isEmpty ? _unknownReply(language) : answer,
      source: AnswerSource.insufficient,
    );
  }

  Map<String, dynamic>? _decodeObject(String input) {
    try {
      final dynamic decoded = jsonDecode(input);
      if (decoded is Map) {
        return decoded.map(
          (dynamic key, dynamic value) =>
              MapEntry<String, dynamic>('$key', value),
        );
      }
    } catch (_) {
      // Legacy STATUS/ANSWER parsing below keeps old provider responses usable.
    }
    return null;
  }

  List<EvidenceChunk> _resolveEvidence(
    Map<String, dynamic> json,
    List<EvidenceChunk> availableEvidence, {
    required bool useAllWhenMissing,
  }) {
    final dynamic rawEvidence = json['evidence'];
    if (rawEvidence is! List) {
      return useAllWhenMissing ? availableEvidence : const <EvidenceChunk>[];
    }

    final List<EvidenceChunk> resolved = <EvidenceChunk>[];
    for (final dynamic reference in rawEvidence) {
      EvidenceChunk? match;
      if (reference is num) {
        final int index = reference.toInt() - 1;
        if (index >= 0 && index < availableEvidence.length) {
          match = availableEvidence[index];
        }
      } else if (reference is String) {
        final String normalized = reference.trim().toLowerCase();
        for (final EvidenceChunk candidate in availableEvidence) {
          if (candidate.sourcePath.toLowerCase() == normalized ||
              candidate.sourceName.toLowerCase() == normalized ||
              candidate.title?.toLowerCase() == normalized) {
            match = candidate;
            break;
          }
        }
      }

      if (match != null && !resolved.contains(match)) {
        resolved.add(match);
      }
    }
    return resolved;
  }

  String _stringValue(dynamic value) => value is String ? value.trim() : '';

  String _stripCodeFences(String input) {
    String value = input.trim();
    value = value.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
    value = value.replaceFirst(RegExp(r'\s*```$'), '');
    return value.trim();
  }

  String _unknownReply(AppLanguage language) {
    return language == AppLanguage.zhHans
        ? '当前知识库没有足够信息回答这个问题。'
        : 'The current knowledge base does not contain enough information to answer this question.';
  }
}
