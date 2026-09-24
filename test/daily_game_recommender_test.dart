import 'package:flutter_test/flutter_test.dart';
import 'package:board_game_agent/features/games/models/daily_recommendation_record.dart';
import 'package:board_game_agent/features/games/models/game_info.dart';
import 'package:board_game_agent/features/games/services/daily_game_recommender.dart';

void main() {
  const recommender = DailyGameRecommender();

  test('30 games rotate without repeats across five consecutive days', () {
    final games = List<GameInfo>.generate(30, _game);
    var history = <DailyRecommendationRecord>[];
    final shown = <String>{};
    for (var day = 0; day < 5; day++) {
      final date = DateTime(2026, 9, 23 + day);
      history = recommender.update(
        now: date,
        games: games,
        history: history,
        favoriteSlugs: const <String>{},
        recentlyViewed: const [],
      );
      final slate = history.first.gameIds;
      expect(slate, hasLength(6));
      expect(slate.toSet(), hasLength(6));
      expect(slate.where(shown.contains), isEmpty);
      shown.addAll(slate);
    }
    expect(shown, hasLength(30));
  });

  test('same day remains stable when inputs change', () {
    final games = List<GameInfo>.generate(12, _game);
    final date = DateTime(2026, 9, 23);
    final first = recommender.update(
      now: date,
      games: games,
      history: const [],
      favoriteSlugs: const <String>{},
      recentlyViewed: const [],
    );
    final second = recommender.update(
      now: date.add(const Duration(hours: 8)),
      games: games.reversed.toList(),
      history: first,
      favoriteSlugs: {'game-11'},
      recentlyViewed: const [],
    );
    expect(second.first.gameIds, first.first.gameIds);
  });

  test('small catalogs show each game once and missing games are replaced', () {
    final games = List<GameInfo>.generate(8, _game);
    final date = DateTime(2026, 9, 23);
    final first = recommender.update(
      now: date,
      games: games,
      history: const [],
      favoriteSlugs: const <String>{},
      recentlyViewed: const [],
    );
    final removedId = first.first.gameIds.first;
    final changedCatalog = games.where((game) => game.id != removedId).toList();
    final updated = recommender.update(
      now: date,
      games: changedCatalog,
      history: first,
      favoriteSlugs: const <String>{},
      recentlyViewed: const [],
    );
    expect(updated.first.gameIds, hasLength(6));
    expect(updated.first.gameIds, isNot(contains(removedId)));

    final tiny = recommender.update(
      now: date,
      games: games.take(3).toList(),
      history: const [],
      favoriteSlugs: const <String>{},
      recentlyViewed: const [],
    );
    expect(tiny.first.gameIds.toSet(), {'game-0', 'game-1', 'game-2'});
  });
}

GameInfo _game(int index) => GameInfo(
  id: 'game-$index',
  slug: 'game-$index',
  title: 'Game $index',
  subtitle: 'Game $index',
  coverAssetPath: '',
  bannerAssetPath: '',
  cardAccent: 0,
  score: '8.0',
  scoreCountLabel: '',
  releaseYear: '',
  categoryLine: 'Category ${index % 5}',
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
