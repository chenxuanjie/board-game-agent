import '../models/game_vote_record.dart';

abstract interface class RemoteGameVoteStore {
  String get scope;
  Future<void> upload(GameVoteBallot ballot);
  Future<List<GameVoteBallot>> readBallots();
  void close();
}

/// Account synchronization owns publication, confirmed totals and retries.
/// The legacy anonymous DAV adapter still uses upload/readBallots directly.
abstract interface class CoordinatedGameVoteStore
    implements RemoteGameVoteStore {
  bool get enabled;
  Future<void> synchronize();
}
