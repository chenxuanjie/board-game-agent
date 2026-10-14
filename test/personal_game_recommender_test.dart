import 'package:flutter_test/flutter_test.dart';
import 'package:board_game_agent/features/games/models/game_info.dart';
import 'package:board_game_agent/features/games/services/personal_game_recommender.dart';

void main() {
  const recommender = PersonalGameRecommender();
  test(
    'favorite kinds outrank unrelated high ratings and liked titles are not rediscovered',
    () {
      final catalog = [
        _game('liked-economy', '经济', rating: '10'),
        _game('liked-strategy', '策略', rating: '10'),
        _game('new-economy', '经济', rating: '6'),
        _game('new-strategy', '策略', rating: '9.9'),
      ];
      final economy = recommender.recommend(
        catalog: catalog,
        favoriteSlugs: {' LIKED-ECONOMY '},
        limit: 2,
      );
      expect(economy.first.id, 'new-economy');
      expect(economy.map((g) => g.slug), isNot(contains('liked-economy')));
      final strategy = recommender.recommend(
        catalog: catalog,
        favoriteSlugs: {'liked-strategy'},
        limit: 2,
      );
      expect(strategy.first.id, 'new-strategy');
    },
  );
  test(
    'ten unique games are stable across catalog order and do not mutate the catalog',
    () {
      final catalog = List.generate(20, (i) => _game('game-$i', '类型${i % 4}'));
      final first = recommender.recommend(
        catalog: catalog,
        favoriteSlugs: {'game-0'},
      );
      final second = recommender.recommend(
        catalog: catalog.reversed,
        favoriteSlugs: {'game-0'},
      );
      expect(first, hasLength(10));
      expect(first.map((g) => g.id).toSet(), hasLength(10));
      expect(first.any((g) => g.slug == 'game-0'), isFalse);
      expect(second.map((g) => g.id), first.map((g) => g.id));
      expect(catalog.first.id, 'game-0');
    },
  );
  test(
    'cold start ranks quality with variety and ignores generic competitive preference',
    () {
      final catalog = [
        _game('liked', '竞争', rating: '10'),
        _game('competitive', '竞争', rating: '2'),
        _game('quality', '经济', rating: '9'),
        _game('other', '合作', rating: '8.9'),
      ];
      final cold = recommender.recommend(
        catalog: catalog,
        favoriteSlugs: {},
        limit: 3,
      );
      expect(cold.first.id, 'liked');
      final generic = recommender.recommend(
        catalog: catalog,
        favoriteSlugs: {'liked'},
        limit: 2,
      );
      expect(generic.map((g) => g.id), ['quality', 'other']);
    },
  );
  test('a preference still leaves room for other kinds', () {
    final catalog = [
      _game('liked', '经济'),
      ...List.generate(12, (i) => _game('economy-$i', '经济')),
      _game('party', '聚会'),
    ];
    final slate = recommender.recommend(
      catalog: catalog,
      favoriteSlugs: {'liked'},
    );
    expect(slate.first.categoryLine, '经济');
    expect(slate.any((g) => g.id == 'party'), isTrue);
  });
  test(
    'small catalogs fill once, invalid entries and duplicate ids do not inflate the result',
    () {
      final first = _game('a', '经济', rating: 'NaN');
      final catalog = [first, first, _game('b', '策略'), GameInfo.empty()];
      final result = recommender.recommend(
        catalog: catalog,
        favoriteSlugs: {'a', 'b'},
      );
      expect(result.map((g) => g.id).toSet(), {'a', 'b'});
      expect(result, hasLength(2));
      expect(recommender.recommend(catalog: [], favoriteSlugs: {}), isEmpty);
      expect(
        recommender.recommend(catalog: catalog, favoriteSlugs: {}, limit: 0),
        isEmpty,
      );
    },
  );
}

GameInfo _game(String id, String category, {String rating = '8'}) => GameInfo(
  id: id,
  slug: id,
  title: id,
  subtitle: '',
  coverAssetPath: '',
  bannerAssetPath: '',
  cardAccent: 0,
  score: rating,
  scoreCountLabel: '',
  releaseYear: '',
  categoryLine: category,
  learningDifficulty: '',
  perPlayerTime: '',
  setupTime: '',
  languageRequirement: '',
  supportedPlayers: const [],
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
  complexity: '',
  roundFlow: const [],
  assistantSkills: const [],
  quickPrompts: const [],
);
