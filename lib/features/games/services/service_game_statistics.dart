import 'dart:math';
import 'package:app_client/app_client.dart';
import '../../identity/services/board_personal_store.dart';
import '../models/game_vote_record.dart';
import 'game_vote_service.dart';
import 'remote_game_vote_store.dart';

/// Public aggregates never download other people's private favorites or votes.
final class ServiceGameStatistics implements CoordinatedGameVoteStore {
  ServiceGameStatistics({
    required this.client,
    required this.scope,
    required this.namespace,
    required this.target,
    required this.active,
    this.store,
    this.token,
  });
  final AppJsonClient client;
  @override
  final String scope;
  final String namespace;
  final GameVoteService Function() target;
  final bool Function() active;
  final BoardPersonalStore? store;
  final Future<String> Function()? token;
  @override
  bool get enabled => active();
  @override
  Future<void> upload(GameVoteBallot ballot) async {
    if (!enabled || store == null) throw StateError('请先登录');
    // Favorites already committed to their own table; voting also commits via
    // PreferencesService. Confirmation waits for the actual SDK upload queue.
    await store!.waitForUpload();
  }

  @override
  Future<void> synchronize() async {
    if (!enabled) throw StateError('账号已变化');
    final data = await client.request(
      '/v1/community/statistics',
      get: true,
      token: token == null ? null : await token!(),
    );
    if (!enabled) throw StateError('账号已变化');
    final counts = <String, int>{};
    if (namespace == GameVoteBallot.favoritesNamespace) {
      counts.addAll((data['favorites'] as Map).cast<String, int>());
      for (final game in (data['own_favorites'] as List).cast<String>()) {
        counts[game] = max(0, (counts[game] ?? 0) - 1);
      }
    } else {
      for (final vote in data['votes'] as List) {
        if (vote['campaign'] == namespace) {
          counts[vote['game_slug'] as String] = vote['count'] as int;
        }
      }
      for (final vote in data['own_votes'] as List) {
        if (vote['campaign'] == namespace) {
          final game = vote['game_slug'] as String;
          counts[game] = max(0, (counts[game] ?? 0) - 1);
        }
      }
    }
    await target().acceptPublicCounts(
      scope,
      counts,
      check: () {
        if (!enabled) throw StateError('账号已变化');
      },
    );
  }

  @override
  Future<List<GameVoteBallot>> readBallots() =>
      throw UnsupportedError('Private ballots are never public');
  @override
  void close() {}
}
