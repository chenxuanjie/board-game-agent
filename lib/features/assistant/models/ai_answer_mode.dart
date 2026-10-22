enum AiAnswerMode { knowledgeOnly, knowledgeThenDirect }

extension AiAnswerModeX on AiAnswerMode {
  String get code {
    switch (this) {
      case AiAnswerMode.knowledgeOnly:
        return 'knowledge_only';
      case AiAnswerMode.knowledgeThenDirect:
        return 'knowledge_then_direct';
    }
  }

  static AiAnswerMode fromCode(String? code, {required AiAnswerMode fallback}) {
    for (final AiAnswerMode value in AiAnswerMode.values) {
      if (value.code == code) {
        return value;
      }
    }
    return fallback;
  }
}
