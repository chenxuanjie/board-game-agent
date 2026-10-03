import '../models/game_info.dart';
import '../models/game_ranking_entry.dart';

/// Favorites alone decide rank; score and catalog order never affect rank.
abstract final class GameFavoriteRanker {
  static List<GameRankingEntry> rank(
    Iterable<GameInfo> games,
    int Function(String slug) count,
  ) {
    final seen = <String>{};
    final rows = <({GameInfo game, int count})>[];
    for (final game in games) {
      final slug = game.slug.trim();
      if (slug.isEmpty || !seen.add(slug)) continue;
      final total = count(slug);
      if (total > 0) rows.add((game: game, count: total));
    }
    rows.sort((left, right) {
      final popularity = right.count.compareTo(left.count);
      if (popularity != 0) return popularity;
      final name = left.game.title.toLowerCase().compareTo(
        right.game.title.toLowerCase(),
      );
      return name != 0 ? name : left.game.slug.compareTo(right.game.slug);
    });
    var position = 0;
    var previousCount = -1;
    final entries = <GameRankingEntry>[];
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      if (row.count != previousCount) position = index + 1;
      previousCount = row.count;
      entries.add(
        GameRankingEntry(
          game: row.game,
          rank: position,
          favoriteCount: row.count,
        ),
      );
    }
    return List.unmodifiable(entries);
  }
}
