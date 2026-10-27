import 'dart:async';

import 'package:board_game_agent/features/games/models/game_vote_record.dart';
import 'package:board_game_agent/features/games/services/game_vote_service.dart';
import 'package:board_game_agent/features/games/services/remote_game_vote_store.dart';
import 'package:board_game_agent/features/settings/services/preferences_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'manual refresh reaches coordinator while the previous model read is blocked',
    () async {
      final remote = _HeldCoordinator();
      final votes = GameVoteService(
        preferences: _MemoryPreferences(),
        remoteProvider: () => remote,
      );
      addTearDown(votes.dispose);
      final first = votes.sync();
      await remote.entered.future;
      final fresh = votes.sync(fresh: true);
      expect(remote.requests, 2);
      remote.release.complete();
      await Future.wait([first, fresh]);
      expect(remote.uploads, 0);
    },
  );
}

class _MemoryPreferences extends PreferencesService {
  String? data;
  @override
  Future<String?> loadGameVoteCache() async => data;
  @override
  Future<void> saveGameVoteCache(String value) async {
    data = value;
  }
}

class _HeldCoordinator implements CoordinatedGameVoteStore {
  final entered = Completer<void>(), release = Completer<void>();
  int requests = 0, uploads = 0;
  @override
  String get scope => 'account-public-v1.test';
  @override
  bool get enabled => true;
  @override
  Future<void> synchronize() async {
    requests++;
    if (!entered.isCompleted) entered.complete();
    await release.future;
  }

  @override
  Future<void> upload(GameVoteBallot ballot) async {
    uploads++;
  }

  @override
  Future<List<GameVoteBallot>> readBallots() async => [];
  @override
  void close() {}
}
