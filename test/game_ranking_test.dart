import 'dart:async';
import 'dart:io';

import 'package:board_game_agent/app/state/app_controller.dart';
import 'package:board_game_agent/core/localization/app_language.dart';
import 'package:board_game_agent/core/theme/app_theme.dart';
import 'package:board_game_agent/features/assistant/services/ai_service.dart';
import 'package:board_game_agent/features/assistant/services/speech_service.dart';
import 'package:board_game_agent/features/assistant/services/tts_service.dart';
import 'package:board_game_agent/features/games/models/favorite_game_record.dart';
import 'package:board_game_agent/features/games/models/game_catalog_manifest.dart';
import 'package:board_game_agent/features/games/models/game_info.dart';
import 'package:board_game_agent/features/games/models/game_vote_record.dart';
import 'package:board_game_agent/features/games/services/game_favorite_ranker.dart';
import 'package:board_game_agent/features/games/services/game_manifest_service.dart';
import 'package:board_game_agent/features/games/services/game_vote_service.dart';
import 'package:board_game_agent/features/games/services/webdav_game_vote_store.dart';
import 'package:board_game_agent/features/library/models/asset_source_config.dart';
import 'package:board_game_agent/features/library/services/remote_asset_service.dart';
import 'package:board_game_agent/features/settings/services/preferences_service.dart';
import 'package:board_game_agent/ui/desktop/sidebar.dart';
import 'package:board_game_agent/ui/desktop/theme.dart';
import 'package:board_game_agent/ui/desktop/workspace.dart';
import 'package:board_game_agent/ui/shared/game_ranking_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_settings/webdav_settings.dart';

const _otherId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _namespace = GameVoteBallot.favoritesNamespace;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await (FontLoader(
      'Noto Sans SC',
    )..addFont(rootBundle.load('assets/fonts/NotoSansSC-Variable.ttf'))).load();
  });

  test(
    'likes determine rank; ties share 1,1,3 and ignore rating/catalog order',
    () {
      final counts = {'a': 4, 'b': 4, 'c': 2, 'unavailable': 99};
      final games = [
        _game('c', score: '9.9'),
        _game('b'),
        _game('a'),
        _game('zero'),
        _game('a'),
      ];
      final ranking = GameFavoriteRanker.rank(
        games,
        (slug) => counts[slug] ?? 0,
      );
      expect(ranking.map((row) => row.game.slug), ['a', 'b', 'c']);
      expect(ranking.map((row) => row.rank), [1, 1, 3]);
      expect(ranking.map((row) => row.favoriteCount), [4, 4, 2]);
      expect(() => ranking.clear(), throwsUnsupportedError);
      expect(GameFavoriteRanker.rank(games, (_) => 0), isEmpty);
    },
  );

  test(
    'existing favorites migrate without changing timestamps; restart and cancel work',
    () async {
      final prefs = _Preferences()
        ..favorites = [_record('a'), _record('b'), _record('a')];
      final app = _app(prefs);
      await app.reloadGames();
      await app.refreshFavoriteRankings();
      expect(app.favoriteRankings.map((row) => row.favoriteCount), [1, 1]);
      expect(prefs.favorites.first.createdAt, _record('a').createdAt);
      final cached = GameVoteCache.decode(prefs.cache!, namespace: _namespace);
      final restarted = _app(prefs);
      await restarted.reloadGames();
      await restarted.refreshFavoriteRankings();
      expect(restarted.favoriteStatistics.count('a'), 1);
      expect(await restarted.toggleFavorite(_game('a')), isTrue);
      await restarted.favoriteStatistics.sync();
      expect(restarted.favoriteRankings.map((row) => row.game.slug), ['b']);
      expect(
        GameVoteCache.decode(
          prefs.cache!,
          namespace: _namespace,
        ).ballot.deviceId,
        cached.ballot.deviceId,
      );
    },
  );

  test(
    'two devices aggregate actual likes; refresh is idempotent; cancellation propagates',
    () async {
      final cloud = _Cloud();
      final first = _app(
        _Preferences()..favorites = [_record('a')],
        cloud: cloud,
      );
      final second = _app(
        _Preferences()..favorites = [_record('a'), _record('b')],
        cloud: cloud,
      );
      await first.refreshFavoriteRankings();
      await second.refreshFavoriteRankings();
      await first.refreshFavoriteRankings();
      expect(first.favoriteStatistics.count('a'), 2);
      expect(second.favoriteStatistics.count('a'), 2);
      await first.refreshFavoriteRankings();
      expect(first.favoriteStatistics.count('a'), 2);
      expect(cloud.ballots, hasLength(2));
      expect(await second.toggleFavorite(_game('a')), isTrue);
      await second.favoriteStatistics.sync();
      await first.refreshFavoriteRankings();
      expect(first.favoriteStatistics.count('a'), 1);
      expect(second.favoriteStatistics.count('a'), 1);
      expect(first.favoriteStatistics.count('b'), 1);
    },
  );

  test(
    'pending or failed local saves never publish optimistic favorites',
    () async {
      final cloud = _Cloud();
      final prefs = _Preferences();
      final app = _app(prefs, cloud: cloud);
      await app.refreshFavoriteRankings();
      prefs.saveGate = Completer<void>();
      prefs.failWrite = true;
      final change = app.toggleFavorite(_game('a'));
      await Future<void>.delayed(Duration.zero);
      expect(app.isFavorite(_game('a')), isTrue);
      expect(app.favoriteStatistics.count('a'), 0);
      await app.favoriteStatistics.sync();
      expect(cloud.ballots.values.single.games, isEmpty);
      prefs.saveGate!.complete();
      expect(await change, isFalse);
      expect(app.isFavorite(_game('a')), isFalse);
      prefs.failWrite = false;
      prefs.saveGate = null;
      expect(await app.toggleFavorite(_game('a')), isTrue);
      await app.favoriteStatistics.sync();
      expect(cloud.ballots.values.single.games, ['a']);
    },
  );

  test(
    'offline cancellation and restart preserve other-device cached likes',
    () async {
      final cloud = _Cloud()..ballots[_otherId] = _ballot(_otherId, ['a']);
      final prefs = _Preferences()..favorites = [_record('a')];
      final app = _app(prefs, cloud: cloud);
      await app.refreshFavoriteRankings();
      expect(app.favoriteStatistics.count('a'), 2);
      cloud.fail = true;
      expect(await app.toggleFavorite(_game('a')), isTrue);
      await app.favoriteStatistics.sync();
      expect(app.favoriteStatistics.count('a'), 1);
      expect(app.favoriteStatistics.status, GameVoteSyncStatus.pending);
      final offline = _app(prefs);
      await offline.refreshFavoriteRankings();
      expect(offline.favoriteStatistics.count('a'), 1);
      expect(offline.favoriteStatistics.hasCachedRemoteCounts, isTrue);
      expect(offline.favoriteStatistics.status, GameVoteSyncStatus.localOnly);
      cloud.fail = false;
      await app.refreshFavoriteRankings();
      expect(
        cloud.ballots.values.where((ballot) => ballot.games.contains('a')),
        hasLength(1),
      );
    },
  );

  test(
    'changing endpoint/account isolates cached totals even before refresh',
    () async {
      final oldCloud = _Cloud()..ballots[_otherId] = _ballot(_otherId, ['a']);
      final newCloud = _Cloud()..fail = true;
      var cloud = oldCloud;
      var scope = 'old-account';
      final app = _app(
        _Preferences(),
        remote: () => _Remote(cloud, scope),
        scope: () => scope,
      );
      await app.refreshFavoriteRankings();
      expect(app.favoriteStatistics.count('a'), 1);
      scope = 'new-account';
      cloud = newCloud;
      expect(app.favoriteStatistics.count('a'), 0);
      await app.refreshFavoriteRankings();
      expect(app.favoriteStatistics.count('a'), 0);
      scope = 'old-account';
      cloud = oldCloud..fail = true;
      expect(app.favoriteStatistics.count('a'), 1);
    },
  );

  test(
    'favorites changed during remote read get another upload without stale overwrite',
    () async {
      final cloud = _Cloud()..readGate = Completer<void>();
      final app = _app(_Preferences(), cloud: cloud);
      final refresh = app.refreshFavoriteRankings();
      await Future<void>.delayed(Duration.zero);
      expect(await app.toggleFavorite(_game('b')), isTrue);
      cloud.readGate!.complete();
      await refresh;
      await Future<void>.delayed(Duration.zero);
      await app.favoriteStatistics.sync();
      expect(app.favoriteStatistics.count('b'), 1);
      expect(cloud.ballots.values.single.games, ['b']);
    },
  );

  test(
    'unreadable favorite source cannot replace remote likes with empty snapshot',
    () async {
      final prefs = _Preferences()..failRead = true;
      final cloud = _Cloud();
      final app = _app(prefs, cloud: cloud);
      await app.refreshFavoriteRankings();
      expect(app.favoriteRankingSourceReady, isFalse);
      expect(cloud.uploads, 0);
      expect(await app.toggleFavorite(_game('a')), isFalse);
      prefs.failRead = false;
      prefs.favorites = [_record('a')];
      await app.refreshFavoriteRankings();
      expect(app.favoriteRankingSourceReady, isTrue);
      expect(cloud.ballots.values.single.games, ['a']);
    },
  );

  test(
    'corrupt statistics cache is retained, with real local counts and retry',
    () async {
      final prefs = _Preferences()
        ..cache = '{broken'
        ..favorites = [_record('a')];
      final cloud = _Cloud();
      final app = _app(prefs, cloud: cloud);
      await app.refreshFavoriteRankings();
      expect(app.favoriteStatistics.loadError, isNotNull);
      expect(app.favoriteStatistics.count('a'), 1);
      expect(prefs.cache, '{broken');
      expect(cloud.uploads, 0);
      prefs.cache = null;
      await app.refreshFavoriteRankings();
      expect(app.favoriteStatistics.loadError, isNull);
      expect(cloud.ballots.values.single.games, ['a']);
    },
  );

  test(
    'cache save failure preserves identity and does not publish a new snapshot',
    () async {
      final prefs = _Preferences();
      final cloud = _Cloud();
      final app = _app(prefs, cloud: cloud);
      await app.refreshFavoriteRankings();
      final oldCache = prefs.cache;
      final uploads = cloud.uploads;
      prefs.failCacheWrite = true;
      expect(await app.toggleFavorite(_game('a')), isTrue);
      await app.favoriteStatistics.sync();
      expect(app.favoriteStatistics.count('a'), 1);
      expect(app.favoriteStatistics.status, GameVoteSyncStatus.pending);
      expect(prefs.cache, oldCache);
      expect(cloud.uploads, uploads);
      prefs.failCacheWrite = false;
      await app.favoriteStatistics.sync();
      expect(cloud.ballots.values.single.games, ['a']);
    },
  );

  test(
    'want-to-play ballots and duplicate device files cannot inflate likes',
    () async {
      final cloud = _Cloud()
        ..ballots['one'] = _ballot(_otherId, ['a'])
        ..ballots['duplicate'] = _ballot(_otherId, ['a'])
        ..ballots['campaign'] = GameVoteBallot(
          deviceId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          games: ['a', 'b'],
        );
      final app = _app(_Preferences(), cloud: cloud);
      await app.refreshFavoriteRankings();
      expect(app.favoriteStatistics.count('a'), 1);
      expect(app.favoriteStatistics.count('b'), 0);
      expect(
        () => GameVoteBallot.decode(
          cloud.ballots['campaign']!.encode(),
          namespace: _namespace,
        ),
        throwsFormatException,
      );
      expect(
        () => GameVoteBallot.decode(_ballot(_otherId, ['a']).encode()),
        throwsFormatException,
      );
      expect(
        GameVoteBallot.decode(
          _ballot(_otherId, List.generate(300, (i) => 'game-$i')).encode(),
          namespace: _namespace,
        ).games,
        hasLength(300),
      );
    },
  );

  test(
    'malformed or partially invalid persisted favorites are preserved for retry',
    () async {
      final prefs = await SharedPreferences.getInstance();
      for (final raw in [
        '{broken',
        '{"records":[{"gameSlug":"a","createdAt":"2026-01-01"},{}]}',
      ]) {
        await prefs.setString('favorite_games_v1', raw);
        await expectLater(
          PreferencesService().loadFavoriteGames(),
          throwsFormatException,
        );
        expect(prefs.getString('favorite_games_v1'), raw);
      }
      await PreferencesService().saveFavoriteGames([_record('a')]);
      expect(
        (await PreferencesService().loadFavoriteGames()).single.gameSlug,
        'a',
      );
    },
  );

  test('WebDAV adapter uses isolated favorite directory and schema', () async {
    const root = '/friend/apps/board_game_agent/votes/game-favorites-v1';
    final methods = <String>[];
    final ballot = _ballot(_otherId, ['a']);
    final client = MockClient((request) async {
      methods.add('${request.method} ${request.url.path}');
      switch (request.method) {
        case 'MKCOL':
          return http.Response('', 405);
        case 'PUT':
          expect(request.url.path, '$root/$_otherId.json');
          expect(
            GameVoteBallot.decode(request.body, namespace: _namespace).games,
            ['a'],
          );
          return http.Response('', 201);
        case 'PROPFIND':
          return http.Response(
            '<d:multistatus xmlns:d="DAV:"><d:response><d:href>$root/$_otherId.json</d:href><d:propstat><d:prop><d:resourcetype/></d:prop></d:propstat></d:response></d:multistatus>',
            207,
          );
        case 'GET':
          return http.Response(ballot.encode(), 200);
        default:
          throw StateError('Unexpected method');
      }
    });
    final settings = WebDavSettings(
      mode: ExternalStorageMode.webDav,
      baseUrl: 'https://dav.example/friend/',
      username: 'tester',
      password: 'example',
    );
    final store = WebDavGameVoteStore(
      settings,
      httpClient: client,
      namespace: _namespace,
    );
    addTearDown(store.close);
    await store.upload(ballot);
    expect((await store.readBallots()).single.games, ['a']);
    expect(
      methods.any((request) => request.contains(GameVoteBallot.campaign)),
      isFalse,
    );
    expect(store.scope, isNot(WebDavGameVoteStore.scopeFor(settings)));
    expect(
      store.scope,
      isNot(
        WebDavGameVoteStore.scopeFor(
          settings.copyWith(username: 'another'),
          namespace: _namespace,
        ),
      ),
    );
    await expectLater(
      store.upload(GameVoteBallot(deviceId: _otherId, games: ['a'])),
      throwsFormatException,
    );
  });

  testWidgets(
    'hidden ranking page fits narrow/wide layouts and opens the selected game',
    (tester) async {
      final app = _app(
        _Preferences()..favorites = [_record('a'), _record('b')],
      );
      await app.reloadGames();
      await app.refreshFavoriteRankings();
      GameInfo? opened;
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final width in [320.0, 390.0, 1280.0]) {
        await tester.binding.setSurfaceSize(Size(width, 800));
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            theme: width >= 1000
                ? buildDesktopTheme()
                : AppTheme.buildTheme(app.palette),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: GameRankingScreen(
              controller: app,
              onOpenGame: (game) => opened = game,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('ranking-game-a')), findsOneWidget);
        expect(find.text('1 次喜欢'), findsNWidgets(2));
        await tester.tap(find.byKey(const ValueKey('ranking-game-b')));
        expect(opened?.slug, 'b');
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'ranking read error has retry and empty data does not invent ranks',
    (tester) async {
      final prefs = _Preferences()..failRead = true;
      final app = _app(prefs);
      await app.reloadGames();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.buildTheme(app.palette),
          home: GameRankingScreen(controller: app, onOpenGame: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('喜欢统计读取失败'), findsOneWidget);
      expect(find.byKey(const ValueKey('ranking-game-a')), findsNothing);
      prefs.failRead = false;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('还没有喜欢记录'), findsOneWidget);
      expect(find.text('喜欢统计读取失败'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'desktop ranking navigation works while sidebar keeps its existing entries',
    (tester) async {
      final app = _app(_Preferences()..favorites = [_record('a')]);
      await app.reloadGames();
      await app.refreshFavoriteRankings();
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDesktopTheme(),
          home: DesktopWorkspace(
            controller: app,
            initialPage: 'rankings',
            enableNativeWindowControls: false,
            onOpenAbout: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final sidebar = find.byType(DesktopSidebar);
      expect(sidebar, findsOneWidget);
      expect(
        find.descendant(of: sidebar, matching: find.text('喜欢榜')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('ranking-game-a')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('game-ranking-screen')), findsNothing);
      await tester.tap(find.byTooltip('返回喜欢榜'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ranking-game-a')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

GameManifest _manifest(String slug, {String score = '1.0'}) =>
    GameManifest.fromJson({
      'id': slug,
      'slug': slug,
      'score': score,
      'locales': {
        'zhHans': {'title': slug},
        'en': {'title': slug},
      },
    });
GameInfo _game(String slug, {String score = '1.0'}) =>
    _manifest(slug, score: score).toGameInfo(AppLanguage.zhHans);
FavoriteGameRecord _record(String slug) =>
    FavoriteGameRecord(gameSlug: slug, createdAt: DateTime.utc(2026, 1, 1));
GameVoteBallot _ballot(String id, Iterable<String> games) =>
    GameVoteBallot(deviceId: id, games: games, namespace: _namespace);

AppController _app(
  _Preferences prefs, {
  _Cloud? cloud,
  RemoteGameVoteStore? Function()? remote,
  String? Function()? scope,
}) {
  final app = AppController(
    preferencesService: prefs,
    aiService: _UnusedAiService(),
    gameManifestService: _Manifests(),
    remoteAssetService: _NoAssets(),
    speechService: SpeechService(),
    ttsService: TtsService(),
    favoriteRemoteProvider:
        remote ?? (cloud == null ? null : () => _Remote(cloud, 'shared')),
    favoriteScopeProvider: scope,
  );
  addTearDown(app.dispose);
  return app;
}

class _UnusedAiService extends Fake implements AiService {}

class _Manifests extends GameManifestService {
  @override
  Future<List<GameManifest>> loadEnabledGames({
    required RemoteAssetService remoteAssetService,
    List<AssetSourceConfig> sources = const [],
    bool preferRemote = false,
  }) async => [_manifest('a'), _manifest('b'), _manifest('c')];
}

class _NoAssets extends RemoteAssetService {
  @override
  Future<File?> cachedFileFor(String remotePath) async => null;
}

class _Preferences extends PreferencesService {
  List<FavoriteGameRecord> favorites = [];
  String? cache;
  bool failRead = false;
  bool failWrite = false;
  bool failCacheWrite = false;
  Completer<void>? saveGate;
  @override
  Future<List<FavoriteGameRecord>> loadFavoriteGames() async {
    if (failRead) throw const FormatException('Corrupt source');
    return List.of(favorites);
  }

  @override
  Future<void> saveFavoriteGames(Iterable<FavoriteGameRecord> records) async {
    if (saveGate != null) await saveGate!.future;
    if (failWrite) throw StateError('Storage unavailable');
    favorites = records.toList();
  }

  @override
  Future<String?> loadFavoriteRankingCache() async => cache;
  @override
  Future<void> saveFavoriteRankingCache(String value) async {
    if (failCacheWrite) throw StateError('Cache unavailable');
    cache = value;
  }
}

class _Cloud {
  final ballots = <String, GameVoteBallot>{};
  bool fail = false;
  int uploads = 0;
  Completer<void>? readGate;
}

class _Remote implements RemoteGameVoteStore {
  _Remote(this.cloud, this.scope);
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
    if (cloud.readGate != null) await cloud.readGate!.future;
    return cloud.ballots.values.toList();
  }

  @override
  void close() {}
}
