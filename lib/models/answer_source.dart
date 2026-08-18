/// Describes where a board-game assistant answer came from.
enum AnswerSource { rulebook, generalAdvice, insufficient }

extension AnswerSourceX on AnswerSource {
  String get code {
    switch (this) {
      case AnswerSource.rulebook:
        return 'rulebook';
      case AnswerSource.generalAdvice:
        return 'general_advice';
      case AnswerSource.insufficient:
        return 'insufficient';
    }
  }
}
