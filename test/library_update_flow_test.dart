import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:board_game_agent/app/state/app_controller.dart';
import 'package:board_game_agent/features/assistant/services/ai_service.dart';
import 'package:board_game_agent/features/assistant/services/speech_service.dart';
import 'package:board_game_agent/features/assistant/services/tts_service.dart';
import 'package:board_game_agent/features/games/models/game_catalog_manifest.dart';
import 'package:board_game_agent/features/games/services/game_manifest_service.dart';
import 'package:board_game_agent/features/library/models/asset_source_config.dart';
import 'package:board_game_agent/features/library/models/cached_asset.dart';
import 'package:board_game_agent/features/library/models/remote_library_update.dart';
import 'package:board_game_agent/features/library/models/remote_asset_file.dart';
import 'package:board_game_agent/features/library/services/remote_asset_service.dart';
import 'package:board_game_agent/features/library/services/library_update_diff.dart';
import 'package:board_game_agent/features/settings/services/preferences_service.dart';
import 'package:board_game_agent/ui/shared/library_update_review.dart';
import 'package:board_game_agent/ui/desktop/workspace.dart';
import 'package:board_game_agent/ui/mobile/home_screen.dart';
import 'package:board_game_agent/core/theme/app_theme.dart';
import 'package:board_game_agent/core/theme/palette_registry.dart';

class _NoAi extends Fake implements AiService {}

class _Remote extends RemoteAssetService {
  final texts = <String, String>{};
  final cached = <String, String>{};
  final changed = <String>{};
  final writes = <String>[];
  String? failPath;
  Completer<void>? gate;
  Completer<String?>? catalogGate;
  @override
  Future<String?> fetchRemoteText({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) async => remotePath == 'assets/catalog.json' && catalogGate != null
      ? await catalogGate!.future
      : texts[remotePath];
  @override
  Future<bool> hasRemoteChanged({
    required List<AssetSourceConfig> sources,
    required String remotePath,
  }) async => changed.contains(remotePath);
  @override
  Future<File?> cachedFileFor(String remotePath) async => null;
  @override
  Future<CachedAsset?> ensureCached({
    required List<AssetSourceConfig> sources,
    required String remotePath,
    bool forceRefresh = false,
    bool allowCachedFallback = true,
  }) async {
    if (!forceRefresh) return null;
    await gate?.future;
    if (remotePath == failPath) return null;
    writes.add(remotePath);
    cached[remotePath] = texts[remotePath]!;
    return CachedAsset(
      remotePath: remotePath,
      localPath: remotePath,
      exists: true,
      fromRemote: true,
      sourceId: 'fixture',
    );
  }

  @override
  Future<List<RemoteAssetFile>> listFilesRecursively({
    required List<AssetSourceConfig> sources,
    required String remotePath,
    int maxDepth = 6,
    int maxEntries = 1000,
  }) async => [];
}

class _Manifests extends GameManifestService {
  _Manifests(this.remote, this.game);
  final _Remote remote;
  final String game;
  static const catalog =
      '{"version":1,"games":[{"slug":"cabo","enabled":true,"order":1}]}';
  @override
  Future<String> loadCatalogSource({
    required RemoteAssetService remoteAssetService,
  }) async => remote.cached['assets/catalog.json'] ?? catalog;
  @override
  Future<String> loadManifestSource({
    required String remotePath,
    required RemoteAssetService remoteAssetService,
    List<AssetSourceConfig> sources = const [],
    bool preferRemote = false,
  }) async {
    if (remote.cached.containsKey(remotePath)) {
      return remote.cached[remotePath]!;
    }
    if (remotePath.endsWith('/game.json')) {
      return remote.cached[remotePath] ?? game;
    }
    throw StateError('Not bundled');
  }

  @override
  Future<List<GameManifest>> loadEnabledGames({
    required RemoteAssetService remoteAssetService,
    List<AssetSourceConfig> sources = const [],
    bool preferRemote = false,
  }) async => [
    GameManifest.fromJson(
      jsonDecode(remote.cached['assets/games/cabo/game.json'] ?? game),
    ),
  ];
}

Future<(AppController, _Remote)> _fixture() async {
  SharedPreferences.setMockInitialValues({});
  final remote = _Remote();
  final game = await rootBundle.loadString('assets/games/cabo/game.json');
  final next = jsonDecode(game) as Map<String, dynamic>;
  next['score'] = '8.2';
  remote.texts['assets/catalog.json'] =
      '{"version":1,"games":[{"slug":"cabo","enabled":true,"order":2}]}';
  remote.texts['assets/games/cabo/game.json'] = jsonEncode(next);
  remote.changed.add('assets/games/cabo/game.json');
  final c = AppController(
    preferencesService: PreferencesService(),
    aiService: _NoAi(),
    gameManifestService: _Manifests(remote, game),
    remoteAssetService: remote,
    speechService: SpeechService(),
    ttsService: TtsService(),
  );
  await c.reloadGames();
  await c.checkForLibraryUpdates();
  return (c, remote);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Noto Sans SC',
    )..addFont(rootBundle.load('assets/fonts/NotoSansSC-Variable.ttf'))).load();
  });
  testWidgets(
    'app update postpones library prompt until every update interaction finishes',
    (tester) async {
      final fixture = await tester.runAsync(_fixture);
      final (c, remote) = fixture!;
      addTearDown(c.dispose);
      final releasePrompt = c.suspendLibraryUpdatePrompts();
      final releaseDownload = c.suspendLibraryUpdatePrompts();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.buildTheme(PaletteRegistry.warmwoodStudy),
          home: HomeScreen(controller: c, onOpenAbout: () {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LibraryUpdateReview), findsNothing);
      expect(c.pendingLibraryUpdate, isNotNull);
      releasePrompt();
      releasePrompt(); // idempotent release must not unblock an active download.
      await tester.pumpAndSettle();
      expect(find.byType(LibraryUpdateReview), findsNothing);
      releaseDownload();
      await tester.pumpAndSettle();
      expect(find.byType(LibraryUpdateReview), findsOneWidget);
      expect(remote.writes, isEmpty);
      await tester.tap(find.byKey(const ValueKey('library-update-later')));
      await tester.pumpAndSettle();
      expect(c.pendingLibraryUpdate, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'manual library review cannot interrupt an app update at $width',
      (tester) async {
        final fixture = await tester.runAsync(_fixture);
        final (c, _) = fixture!;
        addTearDown(c.dispose);
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        late BuildContext host;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                host = context;
                return const Scaffold();
              },
            ),
          ),
        );
        final release = c.suspendLibraryUpdatePrompts();
        await showLibraryUpdateReview(host, c);
        await tester.pumpAndSettle();
        expect(find.byType(LibraryUpdateReview), findsNothing);
        expect(c.shouldShowLibraryUpdatePrompt(), isFalse);
        release();
        expect(c.shouldShowLibraryUpdatePrompt(), isTrue);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  test(
    'catalog reports additions, order/category edits and disabling; omissions preserve overlays',
    () {
      final result = catalogChanges(
        {
          'games': [
            {'slug': 'old', 'enabled': true, 'order': 1},
            {'slug': 'missing', 'enabled': true, 'order': 2},
          ],
        },
        {
          'games': [
            {
              'slug': 'old',
              'enabled': false,
              'order': 3,
              'browseCategories': ['coop'],
            },
            {'slug': 'new', 'enabled': true, 'order': 2},
          ],
        },
      );
      expect(result.map((r) => r.kind), [
        RemoteLibraryChangeKind.disabled,
        RemoteLibraryChangeKind.added,
      ]);
      expect(
        result.first.fields,
        containsAll(['enabled', 'order', 'browseCategories']),
      );
      expect(result.map((r) => r.title), isNot(contains('missing')));
    },
  );
  test(
    'catalog change does not hide metadata diffs; failure keeps review and successful retry clears it',
    () async {
      final (c, remote) = await _fixture();
      addTearDown(c.dispose);
      expect(c.pendingLibraryUpdate!.changedPaths, hasLength(2));
      expect(
        c.pendingLibraryUpdate!.changes.any((r) => r.fields.contains('score')),
        isTrue,
      );
      expect(
        c.pendingLibraryUpdate!.changes
            .firstWhere((r) => r.fields.contains('score'))
            .valueChanges['score'],
        '7.7 → 8.2',
      );
      c.dismissPendingLibraryUpdatePrompt();
      expect(c.pendingLibraryUpdate, isNotNull);
      expect(c.shouldShowLibraryUpdatePrompt(), isFalse);
      remote.failPath = 'assets/games/cabo/game.json';
      await c.applyPendingLibraryUpdate();
      expect(c.libraryUpdateError, isNotNull);
      expect(c.pendingLibraryUpdate, isNotNull);
      expect(remote.writes, isEmpty);
      expect(c.games.first.score, '7.7');
      remote.failPath = null;
      remote.gate = Completer<void>();
      final work = c.applyPendingLibraryUpdate();
      await c
          .applyPendingLibraryUpdate(); // repeated press cannot start a second run
      remote.gate!.complete();
      await work;
      expect(remote.writes, [
        'assets/games/cabo/game.json',
        'assets/catalog.json',
      ]);
      expect(c.pendingLibraryUpdate, isNull);
      expect(c.libraryUpdateError, isNull);
      expect(c.games.first.score, '8.2');
      expect(c.activities.first.title, '资料已更新');
      await c.refreshLibraryResources();
    },
  );
  test(
    'new games and registered resources are included, archive files stay excluded',
    () async {
      final (c, remote) = await _fixture();
      addTearDown(c.dispose);
      final catalog = jsonDecode(remote.texts['assets/catalog.json']!);
      catalog['games'].add({'slug': 'new_game', 'enabled': true, 'order': 3});
      remote.texts['assets/catalog.json'] = jsonEncode(catalog);
      final game = jsonDecode(remote.texts['assets/games/cabo/game.json']!);
      game['slug'] = 'new_game';
      game['id'] = 'new_game';
      remote.texts['assets/games/new_game/game.json'] = jsonEncode(game);
      remote.texts['assets/games/new_game/manifest.json'] = jsonEncode({
        'resources': [
          {'path': 'docs/rulebook.md', 'enabled': true, 'status': 'available'},
          {
            'path': 'docs/others/private.md',
            'enabled': true,
            'status': 'available',
          },
        ],
      });
      await c.checkForLibraryUpdates();
      expect(
        c.pendingLibraryUpdate!.changes.any(
          (change) => change.kind == RemoteLibraryChangeKind.added,
        ),
        isTrue,
      );
      expect(
        c.pendingLibraryUpdate!.changedPaths,
        containsAll([
          'assets/games/new_game/game.json',
          'assets/games/new_game/manifest.json',
          'assets/games/new_game/docs/rulebook.md',
        ]),
      );
      expect(
        c.pendingLibraryUpdate!.changedPaths.any(
          (path) => path.contains('/others/'),
        ),
        isFalse,
      );
    },
  );
  test(
    'resource manifest additions and disabling are reported; old-source completion cannot report success',
    () async {
      final (c, remote) = await _fixture();
      addTearDown(c.dispose);
      const path = 'assets/games/cabo/manifest.json';
      remote.changed.add(path);
      remote.cached[path] = jsonEncode({
        'resources': [
          {'path': 'docs/old.md', 'enabled': true, 'status': 'available'},
        ],
      });
      remote.texts[path] = jsonEncode({
        'resources': [
          {'path': 'docs/new.md', 'enabled': true, 'status': 'available'},
        ],
      });
      await c.checkForLibraryUpdates();
      final changes = c.pendingLibraryUpdate!.changes;
      expect(
        changes.any(
          (r) =>
              r.kind == RemoteLibraryChangeKind.disabled &&
              r.path.endsWith('/old.md'),
        ),
        isTrue,
      );
      expect(
        changes.any(
          (r) =>
              r.kind == RemoteLibraryChangeKind.added &&
              r.path.endsWith('/new.md'),
        ),
        isTrue,
      );
      remote.texts['assets/games/cabo/docs/new.md'] = 'new rules';
      remote.gate = Completer<void>();
      final work = c.applyPendingLibraryUpdate();
      await c.saveAssetSourceConfigs(const [
        AssetSourceConfig(
          id: 'new-nas',
          name: 'New',
          address: '',
          testUrl: 'https://new.example/friend/',
        ),
      ]);
      remote.gate!.complete();
      await work;
      expect(c.pendingLibraryUpdate, isNull);
      expect(c.libraryContentRevision, 0);
      expect(c.activities.any((a) => a.title == '资料已更新'), isFalse);
    },
  );
  testWidgets(
    'stale notification checks again and exposes loading, failure retry and empty state',
    (tester) async {
      final fixture = await tester.runAsync(_fixture);
      final (c, remote) = fixture!;
      addTearDown(c.dispose);
      await c.saveAssetSourceConfigs([]);
      remote.catalogGate = Completer<String?>();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.buildTheme(PaletteRegistry.warmwoodStudy),
          home: LibraryUpdateReview(controller: c, fullPage: true),
        ),
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      remote.catalogGate!.complete(null);
      await tester.pumpAndSettle();
      expect(find.textContaining('无法检查'), findsOneWidget);
      expect(find.byKey(const ValueKey('library-update-apply')), findsNothing);
      remote.catalogGate = null;
      remote.changed.clear();
      remote.texts['assets/catalog.json'] = _Manifests.catalog;
      await tester.tap(find.byKey(const ValueKey('library-update-check')));
      await tester.pumpAndSettle();
      expect(find.text('资料已是最新。'), findsOneWidget);
      expect(remote.writes, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'notification opens review and Later preserves updates at $width',
      (tester) async {
        final fixture = await tester.runAsync(_fixture);
        final (c, remote) = fixture!;
        c.dismissPendingLibraryUpdatePrompt();
        addTearDown(c.dispose);
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.buildTheme(PaletteRegistry.warmwoodStudy),
            home: width < 700
                ? HomeScreen(controller: c, onOpenAbout: () {})
                : DesktopWorkspace(controller: c, onOpenAbout: () {}),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          width < 700
              ? find.byKey(const ValueKey('mobile-home-activities'))
              : find.byTooltip('通知'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('发现资料更新').last);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('library-update-review')),
          findsOneWidget,
        );
        expect(find.textContaining('评分'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('library-update-later')));
        await tester.pumpAndSettle();
        expect(c.pendingLibraryUpdate, isNotNull);
        expect(remote.writes, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
    testWidgets(
      'review keeps failure retry and reports committed success at $width',
      (tester) async {
        final fixture = await tester.runAsync(_fixture);
        final (c, remote) = fixture!;
        addTearDown(c.dispose);
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.buildTheme(PaletteRegistry.warmwoodStudy),
            home: LibraryUpdateReview(controller: c, fullPage: width < 700),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
          ),
        );
        await tester.pumpAndSettle();
        remote.failPath = 'assets/games/cabo/game.json';
        await tester.tap(find.byKey(const ValueKey('library-update-apply')));
        await tester.pumpAndSettle();
        expect(find.textContaining('更新未完成'), findsOneWidget);
        remote.failPath = null;
        await tester.tap(find.byKey(const ValueKey('library-update-apply')));
        await tester.pump();
        await tester.runAsync(() async {
          await c.refreshLibraryResources();
        });
        await tester.pumpAndSettle();
        expect(find.text('资料已更新'), findsOneWidget);
        expect(c.games.first.score, '8.2');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
