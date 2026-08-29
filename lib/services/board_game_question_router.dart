import '../models/game_info.dart';

/// The first routing decision made before loading local rule sources.
enum BoardGameQuestionRoute { general, gameKnowledge, ambiguous }

/// How confidently the local router made its decision.
enum BoardGameQuestionConfidence { high, low }

/// A routing result that remains useful for diagnostics and a later model
/// classifier. The route itself is deliberately provider-independent.
class BoardGameQuestionRoutingDecision {
  const BoardGameQuestionRoutingDecision({
    required this.route,
    required this.confidence,
    required this.reason,
    this.source = BoardGameQuestionDecisionSource.heuristic,
  });

  final BoardGameQuestionRoute route;
  final BoardGameQuestionConfidence confidence;
  final String reason;
  final BoardGameQuestionDecisionSource source;

  bool get needsModelClassification =>
      route == BoardGameQuestionRoute.ambiguous;
}

/// Identifies which layer produced a routing decision.
enum BoardGameQuestionDecisionSource { heuristic, model, fallback }

/// Cheap, deterministic routing for the first turn of an AI request.
///
/// The router intentionally does not call a model. It prevents greetings and
/// unrelated questions from loading rule files or invoking web search. A
/// dedicated game page gets a little more contextual tolerance, while the
/// standalone assistant requires stronger game signals.
class BoardGameQuestionRouter {
  const BoardGameQuestionRouter();

  BoardGameQuestionRoute route({
    required String prompt,
    required GameInfo game,
    required bool useGlobalMode,
    bool useCurrentGameKnowledge = false,
  }) => decide(
    prompt: prompt,
    game: game,
    useGlobalMode: useGlobalMode,
    useCurrentGameKnowledge: useCurrentGameKnowledge,
  ).route;

  BoardGameQuestionRoutingDecision decide({
    required String prompt,
    required GameInfo game,
    required bool useGlobalMode,
    bool useCurrentGameKnowledge = false,
  }) {
    final String normalized = _normalize(prompt);
    if (normalized.isEmpty) {
      return const BoardGameQuestionRoutingDecision(
        route: BoardGameQuestionRoute.general,
        confidence: BoardGameQuestionConfidence.high,
        reason: 'empty_prompt',
      );
    }

    final int generalScore = _score(normalized, _generalMarkers);
    final _GameSignal gameSignal = _gameSignal(
      normalized,
      game: game,
      useGlobalMode: useGlobalMode,
    );

    // Explicitly conversational requests should never be forced through the
    // rule workflow when they do not also mention the game.
    if (generalScore > 0 && gameSignal.strongScore == 0) {
      return const BoardGameQuestionRoutingDecision(
        route: BoardGameQuestionRoute.general,
        confidence: BoardGameQuestionConfidence.high,
        reason: 'general_marker',
      );
    }
    if (gameSignal.strongScore > 0 && generalScore == 0) {
      return const BoardGameQuestionRoutingDecision(
        route: BoardGameQuestionRoute.gameKnowledge,
        confidence: BoardGameQuestionConfidence.high,
        reason: 'game_marker',
      );
    }

    // A prompt containing both broad conversation and game signals is not
    // safe to decide from keywords alone. Let the small classifier resolve it
    // before any documents or web tools are loaded.
    if (generalScore > 0 && gameSignal.score > 0) {
      return const BoardGameQuestionRoutingDecision(
        route: BoardGameQuestionRoute.ambiguous,
        confidence: BoardGameQuestionConfidence.low,
        reason: 'mixed_signals',
      );
    }

    // A dedicated game page is already scoped to the selected game. Keep
    // allowing natural short questions with omitted subjects, while the
    // standalone assistant remains ordinary-chat-first.
    if (!useGlobalMode || useCurrentGameKnowledge) {
      return const BoardGameQuestionRoutingDecision(
        route: BoardGameQuestionRoute.gameKnowledge,
        confidence: BoardGameQuestionConfidence.low,
        reason: 'explicit_game_scope',
      );
    }
    return const BoardGameQuestionRoutingDecision(
      route: BoardGameQuestionRoute.ambiguous,
      confidence: BoardGameQuestionConfidence.low,
      reason: 'no_local_signal',
    );
  }

  bool isGameQuestion({
    required String prompt,
    required GameInfo game,
    required bool useGlobalMode,
    bool useCurrentGameKnowledge = false,
  }) {
    return route(
          prompt: prompt,
          game: game,
          useGlobalMode: useGlobalMode,
          useCurrentGameKnowledge: useCurrentGameKnowledge,
        ) ==
        BoardGameQuestionRoute.gameKnowledge;
  }

  BoardGameQuestionRoutingDecision fallback({
    required bool useGlobalMode,
    bool useCurrentGameKnowledge = false,
  }) {
    return BoardGameQuestionRoutingDecision(
      route: useGlobalMode && !useCurrentGameKnowledge
          ? BoardGameQuestionRoute.general
          : BoardGameQuestionRoute.gameKnowledge,
      confidence: BoardGameQuestionConfidence.low,
      reason: useGlobalMode
          ? 'classifier_failed_global'
          : 'classifier_failed_game',
      source: BoardGameQuestionDecisionSource.fallback,
    );
  }

  _GameSignal _gameSignal(
    String prompt, {
    required GameInfo game,
    required bool useGlobalMode,
  }) {
    final Set<String> strongMarkers = <String>{
      ..._strongGameMarkers,
      ..._terms(game.title),
      ..._terms(game.subtitle),
      ..._terms(game.slug),
    };
    final int strongScore = _score(prompt, strongMarkers);
    int weakScore = _score(prompt, _weakGameMarkers);

    // On a dedicated game page, short contextual questions such as “这个怎
    // 么处理？” are naturally about the game. Do not apply this broad rule
    // to the standalone assistant, where normal conversation is the default.
    if (!useGlobalMode &&
        _contextualGameMarkers.any(prompt.contains) &&
        prompt.length <= 32) {
      weakScore += 1;
    }
    return _GameSignal(strongScore: strongScore, weakScore: weakScore);
  }

  int _score(String prompt, Iterable<String> markers) {
    int score = 0;
    for (final String marker in markers) {
      if (marker.isNotEmpty && _markerMatches(prompt, marker)) score += 1;
    }
    return score;
  }

  bool _markerMatches(String prompt, String marker) {
    final bool isAsciiWord = RegExp(r'^[a-z0-9]+$').hasMatch(marker);
    if (!isAsciiWord) return prompt.contains(marker);
    return RegExp(
      r'(?<![a-z0-9])' + RegExp.escape(marker) + r'(?![a-z0-9])',
    ).hasMatch(prompt);
  }

  Set<String> _terms(String value) {
    final String normalized = _normalize(value);
    if (normalized.isEmpty) return const <String>{};
    final List<String> pieces = normalized
        .split(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'))
        .where((String item) => item.isNotEmpty)
        .toList(growable: false);
    return <String>{normalized, ...pieces};
  }

  String _normalize(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\u0000-\u001f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');

  static const Set<String> _strongGameMarkers = <String>{
    '桌游',
    '游戏规则',
    '规则书',
    '规则',
    '玩法',
    '回合',
    '轮次',
    '阶段',
    '行动',
    '卡牌',
    '牌',
    '玩家',
    '资源',
    '费用',
    '得分',
    '胜利',
    '结束条件',
    '设置',
    'setup',
    'turn',
    'round',
    'card',
    'player',
    'score',
    'rule',
    'rules',
    'gameplay',
  };

  /// Broad words can occur in ordinary language (for example “游戏行业” or
  /// “设置应用”), so they make a global prompt ambiguous rather than forcing
  /// it into the document workflow.
  static const Set<String> _weakGameMarkers = <String>{
    '游戏',
    '阶段',
    '行动',
    '设置',
    '牌',
    'game',
  };

  static const Set<String> _contextualGameMarkers = <String>{
    '这个',
    '这张',
    '这条',
    '这一步',
    '本局',
    '当前游戏',
    '下一步',
    '怎么玩',
    '怎么开始',
    '怎么处理',
  };

  static const Set<String> _generalMarkers = <String>{
    '你好',
    '您好',
    '谢谢',
    '感谢',
    '你是谁',
    '你能做什么',
    '天气',
    '新闻',
    '翻译',
    '翻译成',
    '代码',
    '编程',
    '程序',
    '数学',
    '概率',
    '写一封',
    '写一个故事',
    '写诗',
    '食谱',
    '旅行计划',
    '生日祝福',
    'hello',
    'hi',
    'thanks',
    'translate',
    'code',
    'programming',
    'weather',
  };
}

class _GameSignal {
  const _GameSignal({required this.strongScore, required this.weakScore});

  final int strongScore;
  final int weakScore;

  int get score => strongScore + weakScore;
}
