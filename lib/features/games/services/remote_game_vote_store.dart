import '../models/game_vote_record.dart';

abstract interface class RemoteGameVoteStore {
  String get scope;
  Future<void> upload(GameVoteBallot ballot);
  Future<List<GameVoteBallot>> readBallots();
  void close();
}
