import '../models/game_info.dart';

class RelatedGameRecommendation {
  const RelatedGameRecommendation({required this.game, required this.reason});

  final GameInfo game;
  final String reason;
}

/// Ranks games by the metadata already present in the local catalog.
final class RelatedGameRecommender {
  const RelatedGameRecommender();

  List<RelatedGameRecommendation> recommend({
    required GameInfo source,
    required Iterable<GameInfo> catalog,
    int limit = 6,
  }) {
    if (limit <= 0) return const [];
    final seenIds = <String>{};
    final scored = <_ScoredGame>[];
    for (final candidate in catalog) {
      if (candidate.id == source.id ||
          candidate.id == '__empty__' ||
          !seenIds.add(candidate.id)) {
        continue;
      }
      final commonKeywords = _shared(source.keywords, candidate.keywords);
      final commonCategories = _shared(
        _categories(source),
        _categories(candidate),
      );
      final meaningfulCategories = commonCategories
          .where(
            (category) => !_genericCategories.contains(_normalize(category)),
          )
          .toList();
      final commonDesigners = _shared(source.designers, candidate.designers);
      final sharedPlayers = source.supportedPlayers.toSet().intersection(
        candidate.supportedPlayers.toSet(),
      );
      final playerUnion = source.supportedPlayers.toSet().union(
        candidate.supportedPlayers.toSet(),
      );
      final playerSimilarity = playerUnion.isEmpty
          ? 0.0
          : sharedPlayers.length / playerUnion.length;
      final difficultySimilarity = _difficultySimilarity(source, candidate);
      final durationSimilarity = _durationSimilarity(source, candidate);
      final rating = double.tryParse(candidate.score) ?? 0;
      final score =
          commonKeywords.length * 5.0 +
          meaningfulCategories.length * 4.0 +
          (commonCategories.length - meaningfulCategories.length) * 0.5 +
          commonDesigners.length * 3.0 +
          playerSimilarity * 2.0 +
          difficultySimilarity * 1.5 +
          durationSimilarity +
          rating.clamp(0, 10) * 0.05;
      final reason = commonKeywords.isNotEmpty
          ? commonKeywords.first
          : meaningfulCategories.isNotEmpty
          ? meaningfulCategories.first
          : commonDesigners.isNotEmpty
          ? commonDesigners.first
          : playerSimilarity >= 0.5
          ? 'players'
          : difficultySimilarity > 0
          ? 'difficulty'
          : 'rating';
      scored.add(_ScoredGame(candidate, score, reason));
    }
    scored.sort((a, b) {
      final difference = b.score.compareTo(a.score);
      return difference == 0 ? a.game.id.compareTo(b.game.id) : difference;
    });
    return scored
        .take(limit)
        .map(
          (entry) =>
              RelatedGameRecommendation(game: entry.game, reason: entry.reason),
        )
        .toList(growable: false);
  }

  static const _genericCategories = <String>{
    '竞争',
    'competitive',
    '桌游',
    'board game',
  };

  List<String> _categories(GameInfo game) => game.categoryLine
      .split('/')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);

  List<String> _shared(Iterable<String> left, Iterable<String> right) {
    final byNormalized = <String, String>{
      for (final value in left)
        if (_normalize(value).isNotEmpty) _normalize(value): value.trim(),
    };
    return right
        .map((value) => byNormalized[_normalize(value)])
        .whereType<String>()
        .toSet()
        .toList(growable: false);
  }

  String _normalize(String value) => value.trim().toLowerCase();

  double _difficultySimilarity(GameInfo left, GameInfo right) {
    final a = _difficultyRank(left.complexity);
    final b = _difficultyRank(right.complexity);
    if (a == null || b == null) return 0;
    return switch ((a - b).abs()) {
      0 => 1,
      1 => 0.45,
      _ => 0,
    };
  }

  int? _difficultyRank(String value) {
    final normalized = _normalize(value);
    if (normalized.isEmpty || normalized == '-') return null;
    if (normalized.contains('重') || normalized.contains('heavy')) return 3;
    if (normalized.contains('轻中') || normalized.contains('light-medium')) {
      return 1;
    }
    if (normalized.contains('中') || normalized.contains('medium')) return 2;
    if (normalized.contains('轻') || normalized.contains('light')) return 0;
    return null;
  }

  double _durationSimilarity(GameInfo left, GameInfo right) {
    final a = _minutes(left.playTime);
    final b = _minutes(right.playTime);
    if (a == null || b == null) return 0;
    final difference = (a - b).abs();
    if (difference <= 15) return 1;
    if (difference <= 30) return 0.5;
    return 0;
  }

  double? _minutes(String value) {
    final matches = RegExp(r'\d+').allMatches(value).take(2).toList();
    if (matches.isEmpty) return null;
    final first = double.parse(matches.first.group(0)!);
    return matches.length == 1
        ? first
        : (first + double.parse(matches.last.group(0)!)) / 2;
  }
}

class _ScoredGame {
  const _ScoredGame(this.game, this.score, this.reason);

  final GameInfo game;
  final double score;
  final String reason;
}
