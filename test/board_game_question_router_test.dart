import 'package:flutter_test/flutter_test.dart';

import 'package:board_game_agent/models/game_info.dart';
import 'package:board_game_agent/services/board_game_question_router.dart';

void main() {
  const BoardGameQuestionRouter router = BoardGameQuestionRouter();

  test('routes ordinary conversation away from the knowledge workflow', () {
    expect(
      router.route(prompt: '你好，你能做什么？', game: _game(), useGlobalMode: true),
      BoardGameQuestionRoute.general,
    );
    expect(
      router.route(prompt: '帮我写一封邮件', game: _game(), useGlobalMode: true),
      BoardGameQuestionRoute.general,
    );
  });

  test('marks a global prompt without local signals as ambiguous', () {
    final BoardGameQuestionRoutingDecision decision = router.decide(
      prompt: '你最近怎么样？',
      game: _game(),
      useGlobalMode: true,
    );

    expect(decision.route, BoardGameQuestionRoute.ambiguous);
    expect(decision.needsModelClassification, isTrue);
    expect(decision.reason, 'no_local_signal');
  });

  test('does not treat an English substring as a game signal', () {
    expect(
      router.route(
        prompt: '请帮我分析一下这个 codec 的设计。',
        game: _game(),
        useGlobalMode: true,
      ),
      BoardGameQuestionRoute.ambiguous,
    );
  });

  test('routes explicit game questions into the knowledge workflow', () {
    expect(
      router.route(prompt: '波多黎各市长阶段怎么进行？', game: _game(), useGlobalMode: true),
      BoardGameQuestionRoute.gameKnowledge,
    );
    expect(
      router.route(prompt: '这个规则怎么处理？', game: _game(), useGlobalMode: false),
      BoardGameQuestionRoute.gameKnowledge,
    );
  });
}

GameInfo _game() => GameInfo(
  id: 'puerto-rico',
  slug: 'puerto_rico',
  title: '波多黎各',
  subtitle: 'Puerto Rico',
  coverAssetPath: '',
  bannerAssetPath: '',
  cardAccent: 0,
  score: '',
  scoreCountLabel: '',
  releaseYear: '',
  categoryLine: '',
  learningDifficulty: '',
  perPlayerTime: '',
  setupTime: '',
  languageRequirement: '',
  supportedPlayers: const <int>[],
  recommendedPlayer: 0,
  rankBadges: const <String>[],
  rulebookAssetPath: '',
  faqAssetPath: '',
  heroTagline: '',
  assistantIntro: '',
  summary: '',
  mentorPitch: '',
  playTime: '',
  playerCount: '',
  complexity: '',
  roundFlow: const <String>[],
  assistantSkills: const <String>[],
  quickPrompts: const <String>[],
);
