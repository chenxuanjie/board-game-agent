import '../models/app_language.dart';
import '../models/game_info.dart';

/// Builds prompts for the board-game domain without naming a specific model
/// provider.
class BoardGamePromptBuilder {
  String buildKnowledgeOnlySystemPrompt({
    required AppLanguage language,
    required GameInfo game,
    required String knowledgeContext,
  }) {
    final String todayLabel = _todayString(language);

    if (language == AppLanguage.zhHans) {
      return '''
你是一个桌游 AI 助手。
今天的日期：$todayLabel。
你当前正在担任《${game.title}》的桌游规则助手。
你现在处于“仅知识库回答”模式。
你只能依据下面提供的当前桌游本地知识库内容回答。
禁止使用你自己的泛化记忆、常识、猜测或推断来补全未明确写出的规则。
如果知识库没有明确给出答案，或者证据不足，必须返回 unknown。
如果用户问题超出当前桌游知识库范围，也必须返回 unknown。
请只返回 JSON，不要添加代码块，不要添加额外说明。

evidence 数组只能填写实际使用的知识文件名，例如 rulebook_zh.md；无法确认时返回空数组。
可用返回格式只有二选一：
{"status":"answered","answer":"你的回答","evidence":["rulebook_zh.md"]}
{"status":"unknown","answer":"当前知识库没有足够信息回答这个问题。","evidence":[]}

当前桌游本地知识库如下：
$knowledgeContext
''';
    }

    return '''
You are a board-game AI assistant.
Today's date: $todayLabel.
You are currently acting as the rules assistant for ${game.title}.
You are now in knowledge-only mode.
You may answer only from the local knowledge base content provided below.
Do not use your own general memory, common sense, guesses, or inference to fill gaps in missing rules.
If the knowledge base does not explicitly support the answer, you must return unknown.
If the question falls outside this game's knowledge base, you must also return unknown.
Return JSON only, with no code fences and no extra commentary.

The evidence array may contain only the actual knowledge file names used, such as rulebook_en.md. Return an empty array when no evidence can be confirmed.
The only valid formats are:
{"status":"answered","answer":"your answer","evidence":["rulebook_en.md"]}
{"status":"unknown","answer":"The current knowledge base does not contain enough information to answer this question.","evidence":[]}

Current local knowledge base:
$knowledgeContext
''';
  }

  String buildDirectFallbackSystemPrompt({
    required AppLanguage language,
    required GameInfo game,
    required bool useGlobalMode,
    required String knowledgeContext,
  }) {
    final String todayLabel = _todayString(language);
    final String gameProfile = buildGameProfileBlock(language, game);
    final String knowledgeBlock = knowledgeContext.isEmpty
        ? ''
        : language == AppLanguage.zhHans
        ? '\n\n以下是本地知识库中可作为补充参考的摘录：\n$knowledgeContext'
        : '\n\nBelow are optional excerpts from the local knowledge base for reference:\n$knowledgeContext';

    if (language == AppLanguage.zhHans) {
      final String entryHint = useGlobalMode
          ? '用户当前位于独立 AI 入口，但当前选中的桌游上下文仍然是《${game.title}》。'
          : '用户当前位于《${game.title}》的桌游详情 AI 助手。';
      return '''
你是一个桌游 AI 助手。
今天的日期：$todayLabel。
$entryHint
你现在处于“智能补充”模式。
请优先围绕当前桌游回答，并结合下面给出的桌游详情来组织答案。
如果本地知识库不足，你可以使用你的通用知识直接回答，就像普通 AI 问答一样。
但如果涉及非常具体、你没有把握的规则细节，请明确说明你不确定，不要编造。
回答要清晰、简洁、可执行，并尽量贴合当前桌游。

当前桌游详情：
$gameProfile$knowledgeBlock
''';
    }

    final String entryHint = useGlobalMode
        ? 'The user is in the standalone AI entry, but the currently selected game context is still ${game.title}.'
        : 'The user is in the dedicated assistant for ${game.title}.';
    return '''
You are a board-game AI assistant.
Today's date: $todayLabel.
$entryHint
You are now in smart supplement mode.
Prioritize the current game and use the game profile below to shape your answer.
If the local knowledge base is insufficient, you may answer directly from your general knowledge like a normal AI assistant.
However, if the user asks about a very specific rule detail and you are not confident, say you are not sure instead of inventing an answer.
Keep the answer practical, concise, and focused on the current game.

Current game profile:
$gameProfile$knowledgeBlock
''';
  }

  String buildGameProfileBlock(AppLanguage language, GameInfo game) {
    final StringBuffer buffer = StringBuffer()
      ..writeln('- title: ${game.title}')
      ..writeln('- subtitle: ${game.subtitle}')
      ..writeln('- summary: ${game.summary}')
      ..writeln('- mentorPitch: ${game.mentorPitch}')
      ..writeln('- playerCount: ${game.playerCount}')
      ..writeln('- playTime: ${game.playTime}')
      ..writeln('- complexity: ${game.complexity}')
      ..writeln('- learningDifficulty: ${game.learningDifficulty}')
      ..writeln('- perPlayerTime: ${game.perPlayerTime}')
      ..writeln('- setupTime: ${game.setupTime}')
      ..writeln('- languageRequirement: ${game.languageRequirement}')
      ..writeln('- supportedPlayers: ${game.supportedPlayers.join(', ')}')
      ..writeln('- recommendedPlayer: ${game.recommendedPlayer}');

    if (game.roundFlow.isNotEmpty) {
      buffer.writeln(
        language == AppLanguage.zhHans ? '- 一局流程：' : '- roundFlow:',
      );
      for (final String step in game.roundFlow) {
        buffer.writeln('  - $step');
      }
    }

    if (game.assistantSkills.isNotEmpty) {
      buffer.writeln(
        language == AppLanguage.zhHans ? '- 助手能力：' : '- assistantSkills:',
      );
      for (final String skill in game.assistantSkills) {
        buffer.writeln('  - $skill');
      }
    }

    return buffer.toString().trimRight();
  }

  String _todayString(AppLanguage language) {
    final DateTime now = DateTime.now();
    final String year = now.year.toString().padLeft(4, '0');
    final String month = now.month.toString().padLeft(2, '0');
    final String day = now.day.toString().padLeft(2, '0');
    if (language == AppLanguage.zhHans) {
      const List<String> weekdays = <String>[
        '星期一',
        '星期二',
        '星期三',
        '星期四',
        '星期五',
        '星期六',
        '星期日',
      ];
      return '$year-$month-$day ${weekdays[now.weekday - 1]}';
    }

    const List<String> weekdays = <String>[
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return '$year-$month-$day ${weekdays[now.weekday - 1]}';
  }
}
