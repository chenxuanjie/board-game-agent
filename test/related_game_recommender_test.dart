import 'package:board_game_agent/models/game_info.dart';
import 'package:board_game_agent/services/related_game_recommender.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const recommender = RelatedGameRecommender();

  test('shared specific mechanisms outrank generic category and rating', () {
    final source = _game('source', categories: '竞争 / 经济', keywords: ['拍卖']);
    final relevant = _game('relevant', categories: '竞争 / 经济', keywords: ['拍卖']);
    final generic = _game('generic', categories: '竞争 / 派对', rating: '9.8');
    final results = recommender.recommend(
      source: source,
      catalog: [generic, source, relevant, relevant],
    );
    expect(results.map((item) => item.game.id), ['relevant', 'generic']);
    expect(results.first.reason, '拍卖');
  });

  test(
    'player overlap and difficulty provide fallback when tags are absent',
    () {
      final source = _game('source', players: [2, 3, 4], complexity: '轻中');
      final close = _game('close', players: [2, 3, 4], complexity: '轻中');
      final distant = _game('distant', players: [6, 7], complexity: '中重');
      final results = recommender.recommend(
        source: source,
        catalog: [distant, close],
        limit: 1,
      );
      expect(results.single.game.id, 'close');
      expect(results.single.reason, 'players');
    },
  );

  test('ties use stable ids and empty catalog has no recommendations', () {
    final source = _game('source');
    final a = _game('a');
    final b = _game('b');
    expect(
      recommender
          .recommend(source: source, catalog: [b, a])
          .map((r) => r.game.id),
      ['a', 'b'],
    );
    expect(recommender.recommend(source: source, catalog: [source]), isEmpty);
  });
}

GameInfo _game(
  String id, {
  String categories = '',
  List<String> keywords = const [],
  List<int> players = const [],
  String complexity = '',
  String rating = '7.0',
}) => GameInfo(
  id: id,
  slug: id,
  title: id,
  subtitle: id,
  keywords: keywords,
  coverAssetPath: '',
  bannerAssetPath: '',
  cardAccent: 0,
  score: rating,
  scoreCountLabel: '',
  releaseYear: '',
  categoryLine: categories,
  learningDifficulty: '',
  perPlayerTime: '',
  setupTime: '',
  languageRequirement: '',
  supportedPlayers: players,
  recommendedPlayer: 0,
  rankBadges: const [],
  rulebookAssetPath: '',
  faqAssetPath: '',
  heroTagline: '',
  assistantIntro: '',
  summary: '',
  mentorPitch: '',
  playTime: '',
  playerCount: '',
  complexity: complexity,
  roundFlow: const [],
  assistantSkills: const [],
  quickPrompts: const [],
);
