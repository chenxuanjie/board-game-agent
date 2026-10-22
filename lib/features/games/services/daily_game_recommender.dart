import '../models/daily_recommendation_record.dart';
import '../models/game_info.dart';
import '../models/recent_game_record.dart';

/// Produces a six-game daily slate using saved exposure history and local data.
final class DailyGameRecommender {
  const DailyGameRecommender();

  static const int slateSize = 6;
  static const int historyDays = 30;

  static String localDateKey(DateTime date) {
    final local = date.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  List<DailyRecommendationRecord> update({
    required DateTime now,
    required List<GameInfo> games,
    required List<DailyRecommendationRecord> history,
    required Set<String> favoriteSlugs,
    required List<RecentGameRecord> recentlyViewed,
  }) {
    final day = localDateKey(now);
    final validGames = <String, GameInfo>{
      for (final game in games)
        if (game.id.trim().isNotEmpty && game.id != '__empty__') game.id: game,
    };
    if (validGames.isEmpty) return const <DailyRecommendationRecord>[];

    final past =
        history
            .where((record) => record.date.compareTo(day) <= 0)
            .toList(growable: true)
          ..sort((a, b) => b.date.compareTo(a.date));
    final existingIndex = past.indexWhere((record) => record.date == day);
    if (existingIndex >= 0) {
      final existing = past[existingIndex];
      final retained = existing.gameIds
          .where(validGames.containsKey)
          .take(slateSize)
          .toList(growable: false);
      if (retained.length == slateSize ||
          retained.length == validGames.length) {
        return _retainHistory(past);
      }
      past.removeAt(existingIndex);
    }

    final recentDates = <String, String>{};
    for (final record in past) {
      for (final id in record.gameIds) {
        recentDates.putIfAbsent(id, () => record.date);
      }
    }
    final parsedDay = DateTime.parse(day);
    final currentDay = DateTime.utc(
      parsedDay.year,
      parsedDay.month,
      parsedDay.day,
    );
    final recentFive = past
        .where((record) {
          final recordDay = DateTime.tryParse(record.date);
          if (recordDay == null) return false;
          final daysAgo = currentDay
              .difference(
                DateTime.utc(recordDay.year, recordDay.month, recordDay.day),
              )
              .inDays;
          return daysAgo >= 1 && daysAgo <= 5;
        })
        .expand((record) => record.gameIds)
        .toSet();
    final normalizedFavorites = favoriteSlugs
        .map((slug) => slug.trim().toLowerCase())
        .toSet();
    final viewedRanks = <String, int>{
      for (var index = 0; index < recentlyViewed.length; index++)
        recentlyViewed[index].normalizedGameSlug: index,
    };
    final selected = <GameInfo>[];
    final selectedCategories = <String>{};
    final candidates = validGames.values.toList(growable: true);
    final targetCount = slateSize.clamp(0, candidates.length);
    while (selected.length < targetCount) {
      final unseen = candidates
          .where((game) => !recentFive.contains(game.id))
          .toList(growable: false);
      final pool = unseen.isNotEmpty ? unseen : candidates;
      pool.sort((left, right) {
        final leftScore = _score(
          left,
          day,
          normalizedFavorites,
          viewedRanks,
          selectedCategories,
          recentDates,
        );
        final rightScore = _score(
          right,
          day,
          normalizedFavorites,
          viewedRanks,
          selectedCategories,
          recentDates,
        );
        final comparison = rightScore.compareTo(leftScore);
        return comparison != 0 ? comparison : left.id.compareTo(right.id);
      });
      final chosen = pool.first;
      selected.add(chosen);
      selectedCategories.add(_category(chosen));
      candidates.remove(chosen);
    }
    past.insert(
      0,
      DailyRecommendationRecord(
        date: day,
        gameIds: selected.map((game) => game.id).toList(growable: false),
      ),
    );
    return _retainHistory(past);
  }

  List<DailyRecommendationRecord> _retainHistory(
    List<DailyRecommendationRecord> history,
  ) => history.take(historyDays).toList(growable: false);

  double _score(
    GameInfo game,
    String day,
    Set<String> favorites,
    Map<String, int> viewedRanks,
    Set<String> selectedCategories,
    Map<String, String> lastShown,
  ) {
    final slug = game.slug.trim().toLowerCase();
    final viewedRank = viewedRanks[slug];
    final rating = double.tryParse(game.score) ?? 0;
    final category = _category(game);
    final dayVariation = _stableHash('$day:${game.id}') % 1000 / 350;
    return (favorites.contains(slug) ? 2.4 : 0) +
        (viewedRank == null ? 0 : 1.5 / (viewedRank + 1)) +
        rating.clamp(0, 10) / 8 +
        dayVariation -
        (selectedCategories.contains(category) ? 1.2 : 0) -
        (lastShown.containsKey(game.id) ? 0.5 : 0);
  }

  String _category(GameInfo game) {
    final category = game.categoryLine.split('/').first.trim().toLowerCase();
    return category.isEmpty ? game.id : category;
  }

  int _stableHash(String text) {
    var hash = 2166136261;
    for (final code in text.codeUnits) {
      hash = ((hash ^ code) * 16777619) & 0xffffffff;
    }
    return hash;
  }
}
