import 'dart:async';
import 'dart:convert';

import 'package:board_game_agent/features/games/models/game_vote_record.dart';
import 'package:board_game_agent/features/games/services/game_vote_service.dart';
import 'package:board_game_agent/features/games/services/webdav_game_vote_store.dart';
import 'package:board_game_agent/features/settings/services/preferences_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:webdav_settings/webdav_settings.dart';

void main() {
  test('offline vote and cancellation persist across restarts', () async {
    final prefs = _Preferences();
    final votes = _service(prefs);
    await votes.load();
    final installationId = jsonDecode(prefs.data!)['ballot']['deviceId'];
    expect(await votes.toggle('splendor'), isTrue);
    expect(votes.count('splendor'), 1);
    expect(votes.status, GameVoteSyncStatus.localOnly);
    final reloaded = _service(prefs);
    await reloaded.load();
    expect(reloaded.hasVoted('splendor'), isTrue);
    expect(await reloaded.toggle('splendor'), isTrue);
    expect(reloaded.count('splendor'), 0);
    final empty = _service(prefs);
    await empty.load();
    expect(empty.count('splendor'), 0);
    expect(jsonDecode(prefs.data!)['ballot']['deviceId'], installationId);
  });

  test('local write failure does not change vote or upload', () async {
    final prefs = _Preferences();
    final cloud = _Cloud();
    final votes = _service(prefs, () => _Remote(cloud));
    await votes.load();
    prefs.failWrite = true;
    expect(await votes.toggle('splendor'), isFalse);
    expect(votes.count('splendor'), 0);
    expect(cloud.uploads, 0);
    prefs.failWrite = false;
    expect(await votes.toggle('splendor'), isTrue);
    await votes.sync();
    expect(votes.count('splendor'), 1);
  });

  test('corrupt local data remains intact and can be retried', () async {
    final prefs = _Preferences()..data = '{broken';
    final votes = _service(prefs);
    await votes.load();
    expect(votes.ready, isFalse);
    expect(prefs.data, '{broken');
    expect(await votes.toggle('splendor'), isFalse);
    prefs.data = null;
    await votes.load();
    expect(votes.ready, isTrue);
  });

  test(
    'two devices merge votes, retries are idempotent, cancellation propagates',
    () async {
      final cloud = _Cloud();
      final first = _service(_Preferences(), () => _Remote(cloud));
      final second = _service(_Preferences(), () => _Remote(cloud));
      await first.load();
      await second.load();
      await first.toggle('splendor');
      await first.sync();
      await second.toggle('splendor');
      await second.sync();
      await first.sync();
      expect(first.count('splendor'), 2);
      expect(second.count('splendor'), 2);
      await first.sync();
      await first.sync();
      expect(first.count('splendor'), 2);
      await second.toggle('splendor');
      await second.sync();
      await first.sync();
      expect(first.count('splendor'), 1);
      expect(second.count('splendor'), 1);
    },
  );

  test('offline cancellation keeps cached votes from other devices', () async {
    final cloud = _Cloud();
    final prefs = _Preferences();
    final votes = _service(prefs, () => _Remote(cloud));
    cloud.ballots['aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'] = GameVoteBallot(
      deviceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      games: ['splendor'],
    );
    await votes.load();
    await votes.toggle('splendor');
    await votes.sync();
    expect(votes.count('splendor'), 2);
    cloud.fail = true;
    await votes.toggle('splendor');
    await votes.sync();
    expect(votes.count('splendor'), 1);
    expect(votes.status, GameVoteSyncStatus.pending);
    final restarted = _service(prefs, () => _Remote(cloud));
    await restarted.sync();
    expect(restarted.count('splendor'), 1);
    cloud.fail = false;
    await restarted.sync();
    expect(restarted.status, GameVoteSyncStatus.synced);
    expect(
      cloud.ballots.values.where((b) => b.games.contains('splendor')),
      hasLength(1),
    );
  });

  test(
    'vote during an in-flight sync is not overwritten and gets uploaded',
    () async {
      final cloud = _Cloud()..gate = Completer<void>();
      final votes = _service(_Preferences(), () => _Remote(cloud));
      await votes.load();
      final sync = votes.sync();
      await Future<void>.delayed(Duration.zero);
      expect(await votes.toggle('splendor'), isTrue);
      expect(votes.count('splendor'), 1);
      cloud.gate!.complete();
      await sync;
      await Future<void>.delayed(Duration.zero);
      await votes.sync();
      expect(votes.count('splendor'), 1);
      expect(cloud.ballots.values.single.games, contains('splendor'));
    },
  );

  test('different WebDAV endpoints do not share cached counts', () async {
    final firstCloud = _Cloud()
      ..ballots['aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'] = GameVoteBallot(
        deviceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        games: ['splendor'],
      );
    final secondCloud = _Cloud()..fail = true;
    var endpoint = firstCloud;
    var scope = 'first';
    final votes = _service(
      _Preferences(),
      () => _Remote(endpoint, scope: scope),
    );
    await votes.sync();
    expect(votes.count('splendor'), 1);
    scope = 'second';
    endpoint = secondCloud;
    await votes.sync();
    expect(votes.count('splendor'), 0);
    scope = 'first';
    endpoint = firstCloud..fail = true;
    await votes.sync();
    expect(votes.count('splendor'), 1);
  });

  test('disposing cancels retries and ignores late remote results', () async {
    final cloud = _Cloud()..gate = Completer<void>();
    final votes = _service(_Preferences(), () => _Remote(cloud));
    await votes.load();
    final sync = votes.sync();
    await Future<void>.delayed(Duration.zero);
    votes.dispose();
    cloud.gate!.complete();
    await sync;
    expect(cloud.closes, greaterThan(0));
  });

  test(
    'ballot schema rejects incompatible versions and unsafe identifiers',
    () {
      final valid = GameVoteBallot(deviceId: 'a' * 32, games: ['splendor']);
      expect(GameVoteBallot.decode(valid.encode()).games, {'splendor'});
      for (final replacement in [
        {'version': 2},
        {'campaign': 'other'},
        {'deviceId': '../bad'},
        {
          'games': ['../bad'],
        },
        {'games': List.filled(257, 'splendor')},
      ]) {
        expect(
          () => GameVoteBallot.decode(
            jsonEncode({
              ...jsonDecode(valid.encode()) as Map<String, dynamic>,
              ...replacement,
            }),
          ),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'WebDAV adapter uses per-device JSON files and excludes unrelated entries',
    () async {
      final id = 'a' * 32;
      final ballot = GameVoteBallot(deviceId: id, games: ['splendor']);
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.method == 'MKCOL') return http.Response('', 405);
        if (request.method == 'PUT') {
          expect(GameVoteBallot.decode(request.body).games, {'splendor'});
          expect(
            request.headers['content-type'],
            startsWith('application/json'),
          );
          return http.Response('', 201);
        }
        if (request.method == 'PROPFIND') {
          final root = '/friend/${WebDavGameVoteStore.directory}';
          return http.Response('''<d:multistatus xmlns:d="DAV:">
          <d:response><d:href>$root/$id.json</d:href><d:propstat><d:prop><d:resourcetype/></d:prop></d:propstat></d:response>
          <d:response><d:href>$root/unrelated.json</d:href><d:propstat><d:prop><d:resourcetype/></d:prop></d:propstat></d:response>
        </d:multistatus>''', 207);
        }
        expect(request.method, 'GET');
        return http.Response(ballot.encode(), 200);
      });
      final remote = WebDavGameVoteStore(
        const WebDavSettings(
          mode: ExternalStorageMode.webDav,
          baseUrl: 'https://example.invalid/friend/',
        ),
        httpClient: client,
      );
      addTearDown(() {
        remote.close();
        client.close();
      });
      await remote.upload(ballot);
      expect((await remote.readBallots()).single.deviceId, id);
      expect(requests.where((r) => r.method == 'GET'), hasLength(1));
      expect(
        requests.where((r) => r.method == 'PUT').single.url.path,
        '/friend/${WebDavGameVoteStore.directory}/$id.json',
      );
    },
  );

  test('unconfigured WebDAV remains local without constructing a client', () {
    expect(WebDavGameVoteStore.fromSettings(const WebDavSettings()), isNull);
  });

  for (final statusCode in [401, 403, 500]) {
    test(
      'WebDAV $statusCode keeps the local vote and reports pending sync',
      () async {
        final client = MockClient((_) async => http.Response('', statusCode));
        addTearDown(client.close);
        final votes = _service(
          _Preferences(),
          () => WebDavGameVoteStore(
            const WebDavSettings(
              mode: ExternalStorageMode.webDav,
              baseUrl: 'https://example.invalid/friend/',
            ),
            httpClient: client,
          ),
        );
        await votes.load();
        expect(await votes.toggle('splendor'), isTrue);
        await votes.sync();
        expect(votes.hasVoted('splendor'), isTrue);
        expect(votes.count('splendor'), 1);
        expect(votes.status, GameVoteSyncStatus.pending);
      },
    );
  }

  test(
    'switching endpoints during sync cannot apply stale remote counts',
    () async {
      final oldCloud = _Cloud()..gate = Completer<void>();
      oldCloud.ballots['a' * 32] = GameVoteBallot(
        deviceId: 'a' * 32,
        games: ['splendor'],
      );
      final newCloud = _Cloud();
      var useOld = true;
      final votes = _service(
        _Preferences(),
        () => _Remote(
          useOld ? oldCloud : newCloud,
          scope: useOld ? 'old' : 'new',
        ),
      );
      await votes.load();
      final pending = votes.sync();
      await Future<void>.delayed(Duration.zero);
      useOld = false;
      oldCloud.gate!.complete();
      await pending;
      await Future<void>.delayed(Duration.zero);
      await votes.sync();
      expect(votes.count('splendor'), 0);
      expect(newCloud.uploads, greaterThan(0));
    },
  );
}

GameVoteService _service(
  _Preferences prefs, [
  RemoteGameVoteStore? Function()? remote,
]) {
  final service = GameVoteService(preferences: prefs, remoteProvider: remote);
  addTearDown(service.dispose);
  return service;
}

class _Preferences extends PreferencesService {
  String? data;
  bool failWrite = false;
  @override
  Future<String?> loadGameVoteCache() async => data;
  @override
  Future<void> saveGameVoteCache(String value) async {
    if (failWrite) throw StateError('Local storage unavailable');
    data = value;
  }
}

class _Cloud {
  final ballots = <String, GameVoteBallot>{};
  bool fail = false;
  int uploads = 0;
  int closes = 0;
  Completer<void>? gate;
}

class _Remote implements RemoteGameVoteStore {
  _Remote(this.cloud, {this.scope = 'test'});
  final _Cloud cloud;
  @override
  final String scope;
  @override
  Future<void> upload(GameVoteBallot ballot) async {
    if (cloud.fail) throw TimeoutException('Offline');
    cloud.ballots[ballot.deviceId] = ballot;
    cloud.uploads++;
  }

  @override
  Future<List<GameVoteBallot>> readBallots() async {
    if (cloud.fail) throw TimeoutException('Offline');
    if (cloud.gate != null) await cloud.gate!.future;
    return cloud.ballots.values.toList();
  }

  @override
  void close() => cloud.closes++;
}
