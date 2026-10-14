import '../models/game_info.dart';

/// Local, deterministic discovery slate. Favorites supply the preference
/// profile; they are only returned when there are too few undiscovered games.
final class PersonalGameRecommender {
  const PersonalGameRecommender();
  List<GameInfo> recommend({
    required Iterable<GameInfo> catalog,
    required Set<String> favoriteSlugs,
    int limit = 10,
  }) {
    if (limit <= 0) return const [];
    final games = <String, GameInfo>{};
    for (final game in catalog) {
      if (game.id.trim().isNotEmpty && game.id != '__empty__') {
        games.putIfAbsent(game.id, () => game);
      }
    }
    final favorites = favoriteSlugs.map(_normalize).toSet();
    final tags = {for (final game in games.values) game.id: _tags(game)};
    final profile = <String, int>{};
    for (final game in games.values.where(
      (g) => favorites.contains(_normalize(g.slug)),
    )) {
      for (final tag in tags[game.id]!) {
        profile.update(tag, (weight) => weight + 1, ifAbsent: () => 1);
      }
    }
    final total = profile.values.fold<int>(0, (sum, weight) => sum + weight);
    final affinity = <String, double>{};
    for (final game in games.values) {
      affinity[game.id] = total == 0
          ? 0
          : tags[game.id]!.fold<int>(
                  0,
                  (sum, tag) => sum + (profile[tag] ?? 0),
                ) /
                total;
    }
    final remaining = games.values.toList();
    final chosen = <GameInfo>[];
    final shownTags = <String, int>{};
    double score(GameInfo game) {
      final gameTags = tags[game.id]!;
      // Similar interests lead, while repeated kinds gradually yield space
      // to discovery. Generic "competitive" labels carry no preference.
      final repeated = gameTags.isEmpty
          ? 0.0
          : gameTags.fold<int>(0, (sum, tag) => sum + (shownTags[tag] ?? 0)) /
                gameTags.length;
      final parsedRating = double.tryParse(game.score);
      final rating = parsedRating != null && parsedRating.isFinite
          ? parsedRating.clamp(0, 10)
          : 0;
      return affinity[game.id]! * 6 + rating * .1 - repeated * .9;
    }

    while (remaining.isNotEmpty && chosen.length < limit) {
      final novel = remaining
          .where((game) => !favorites.contains(_normalize(game.slug)))
          .toList();
      final pool = novel.isEmpty ? remaining : novel;
      pool.sort((a, b) {
        final rank = score(b).compareTo(score(a));
        return rank == 0 ? a.id.compareTo(b.id) : rank;
      });
      final game = pool.first;
      chosen.add(game);
      remaining.remove(game);
      for (final tag in tags[game.id]!) {
        shownTags.update(tag, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    return List.unmodifiable(chosen);
  }

  static String _normalize(String value) => value.trim().toLowerCase();
  static const _generic = {
    '全部',
    'all',
    '竞争',
    'competitive',
    '桌游',
    'board game',
  };
  Set<String> _tags(GameInfo game) =>
      {
            ...game.browseCategories,
            ...game.categoryLine.split('/'),
            ...game.keywords,
          }
          .map(_normalize)
          .where((tag) => tag.isNotEmpty && !_generic.contains(tag))
          .toSet();
}
