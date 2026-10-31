import '../models/game_vote_record.dart';

/// Public counts and personal writes use the current application service.
abstract interface class RemoteGameVoteStore {
  String get scope;
  bool get enabled;
  Future<void> upload(GameVoteBallot ballot);
  Future<void> synchronize();
  void close();
}
