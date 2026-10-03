import 'game_info.dart';

/// A competition rank: equal favorite counts share a rank (1, 1, 3).
class GameRankingEntry {
  const GameRankingEntry({
    required this.game,
    required this.rank,
    required this.favoriteCount,
  });
  final GameInfo game;
  final int rank;
  final int favoriteCount;
}
