import 'dart:async';
import 'dart:convert';
import 'package:app_client/app_client.dart';
import 'package:board_game_agent/features/community/services/game_comments_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  AppJsonClient client(Future<http.Response> Function(http.Request) handler) =>
      AppJsonClient(
        Uri.parse('https://api.test'),
        applicationId: 'board_game_agent',
        client: MockClient(handler),
      );
  test(
    'guests read public comments without identity; writes require login',
    () async {
      final api = client((r) async {
        expect(r.headers['Authorization'], isNull);
        expect(r.url.path, '/v1/apps/board_game_agent/community/comments/cabo');
        return http.Response(
          jsonEncode({'comments': [], 'next_cursor': null}),
          200,
        );
      });
      addTearDown(api.close);
      final service = GameCommentsService(
        client: api,
        scope: 'public',
        isActive: () => true,
        displayName: () => '',
      );
      addTearDown(service.dispose);
      service.watchGame('cabo');
      await service.synchronize();
      expect(service.error, isNull);
      expect(service.readOnly, isTrue);
      await expectLater(
        service.publish(game: 'cabo', text: 'text'),
        throwsStateError,
      );
    },
  );
  test(
    'lost response retains command across restart and retries same ID without claimed actor',
    () async {
      final id = GameCommentsService.newId();
      final seen = <String>[];
      var fail = true;
      final api = client((r) async {
        expect(r.headers['Authorization'], 'Bearer token');
        if (r.method == 'POST') {
          final command = jsonDecode(r.body) as Map;
          expect(command.keys, isNot(contains('user_id')));
          expect(command.keys, isNot(contains('uid')));
          seen.add(command['id'] as String);
          if (fail) throw http.ClientException('lost acknowledgement');
          return http.Response(
            jsonEncode({'id': command['id'], 'status': 'applied'}),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'comments': [
              {
                'id': id,
                'author_id': 'public-alice',
                'game_slug': 'cabo',
                'author': 'Alice',
                'text': 'Rules',
                'created_at': '2026-10-26T00:00:00Z',
                'deleted': false,
                'likes': 0,
                'liked_by_me': false,
              },
            ],
            'next_cursor': null,
          }),
          200,
        );
      });
      addTearDown(api.close);
      GameCommentsService create() => GameCommentsService(
        client: api,
        scope: 'alice',
        uid: 'public-alice',
        isActive: () => true,
        displayName: () => 'Alice',
        token: () async => 'token',
      );
      final first = create();
      await first.publish(game: 'cabo', text: 'Rules', operationId: id);
      await first.synchronize();
      expect(first.pendingIds, contains(id));
      first.dispose();
      fail = false;
      final restored = create();
      addTearDown(restored.dispose);
      restored.watchGame('cabo');
      await restored.synchronize();
      expect(seen, [id, id]);
      expect(restored.pending, isFalse);
      expect(restored.projection.comments[id]!.text, 'Rules');
    },
  );
  test(
    'late acknowledgement after scope change cannot clear the old account queue',
    () async {
      var active = true;
      final gate = Completer<http.Response>();
      final entered = Completer<void>();
      final api = client((r) async {
        entered.complete();
        return gate.future;
      });
      addTearDown(api.close);
      final service = GameCommentsService(
        client: api,
        scope: 'alice',
        uid: 'alice',
        isActive: () => active,
        displayName: () => 'Alice',
        token: () async => 'token',
      );
      addTearDown(service.dispose);
      final id = await service.publish(game: 'cabo', text: 'Draft');
      final work = service.synchronize();
      await entered.future;
      active = false;
      gate.complete(
        http.Response(jsonEncode({'id': id, 'status': 'applied'}), 200),
      );
      await work;
      expect(service.pendingIds, contains(id));
    },
  );
}
