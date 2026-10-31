import 'dart:async';
import 'dart:convert';
import 'package:app_client/app_client.dart';
import 'package:board_game_agent/features/games/models/game_vote_record.dart';
import 'package:board_game_agent/features/games/services/game_vote_service.dart';
import 'package:board_game_agent/features/games/services/service_game_statistics.dart';
import 'package:board_game_agent/features/settings/services/preferences_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'notification during a read is followed by a fresh snapshot without double counting own like',
    () async {
      SharedPreferences.setMockInitialValues({});
      final first = Completer<http.Response>(),
          second = Completer<http.Response>();
      final entered = Completer<void>(), followup = Completer<void>();
      var requests = 0;
      final client = AppJsonClient(
        Uri.parse('https://api.test'),
        applicationId: 'board_game_agent',
        client: MockClient((request) async {
          requests++;
          if (requests == 1) {
            entered.complete();
            return first.future;
          }
          followup.complete();
          return second.future;
        }),
      );
      addTearDown(client.close);
      final target = GameVoteService(
        preferences: PreferencesService(),
        namespace: GameVoteBallot.favoritesNamespace,
        externalGames: () => ['cabo'],
      );
      addTearDown(target.dispose);
      final source = ServiceGameStatistics(
        client: client,
        scope: 'alice',
        namespace: GameVoteBallot.favoritesNamespace,
        target: () => target,
        active: () => true,
      );
      final oldRead = source.synchronize();
      await entered.future;
      final newRead = source.synchronize();
      expect(requests, 1);
      http.Response snapshot(int count) => http.Response(
        jsonEncode({
          'favorites': {'cabo': count},
          'own_favorites': ['cabo'],
          'votes': [],
          'own_votes': [],
        }),
        200,
      );
      first.complete(snapshot(4));
      await followup.future;
      second.complete(snapshot(5));
      await Future.wait([oldRead, newRead]);
      expect(requests, 2);
      expect(target.count('cabo'), 5);
      expect(target.status, GameVoteSyncStatus.synced);
    },
  );
}
