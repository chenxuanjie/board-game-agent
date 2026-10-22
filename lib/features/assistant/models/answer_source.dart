/// Describes where a board-game assistant answer came from.
enum AnswerSource {
  /// Legacy label retained for persisted conversations.
  rulebook,
  official,
  community,
  web,
  modelKnowledge,
  generalAdvice,
  insufficient,
}

extension AnswerSourceX on AnswerSource {
  String get code {
    switch (this) {
      case AnswerSource.rulebook:
        return 'rulebook';
      case AnswerSource.official:
        return 'official';
      case AnswerSource.community:
        return 'community';
      case AnswerSource.web:
        return 'web';
      case AnswerSource.modelKnowledge:
        return 'model_knowledge';
      case AnswerSource.generalAdvice:
        return 'general_advice';
      case AnswerSource.insufficient:
        return 'insufficient';
    }
  }
}
