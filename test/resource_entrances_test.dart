import 'dart:async';
import 'package:board_game_agent/app/state/app_controller.dart';
import 'package:board_game_agent/core/models/connectivity_status.dart';
import 'package:board_game_agent/features/assistant/services/ai_service.dart';
import 'package:board_game_agent/features/assistant/services/speech_service.dart';
import 'package:board_game_agent/features/assistant/services/tts_service.dart';
import 'package:board_game_agent/features/games/services/game_manifest_service.dart';
import 'package:board_game_agent/features/library/models/asset_source_config.dart';
import 'package:board_game_agent/features/library/services/remote_asset_service.dart';
import 'package:board_game_agent/features/settings/services/preferences_service.dart';
import 'package:board_game_agent/ui/shared/resource_access_summary.dart';
import 'package:board_game_agent/core/theme/app_theme.dart';
import 'package:board_game_agent/core/theme/palette_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const sources = [
  AssetSourceConfig(
    id: 'inside',
    name: '内网入口',
    address: '',
    testUrl: 'https://inside.example/friend/',
  ),
  AssetSourceConfig(
    id: 'outside',
    name: '外网入口',
    address: '',
    testUrl: 'https://outside.example/friend/',
  ),
];
const catalog = '{"version":2,"games":[]}';

class _Client extends http.BaseClient {
  final requests = <http.BaseRequest>[];
  final pending = <Completer<http.StreamedResponse>>[];
  final aborted = <int>[];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final index = requests.length;
    requests.add(request);
    final result = Completer<http.StreamedResponse>();
    pending.add(result);
    if (request is http.Abortable) {
      request.abortTrigger?.then((_) {
        if (!result.isCompleted) {
          aborted.add(index);
          result.completeError(http.RequestAbortedException(request.url));
        }
      });
    }
    return result.future;
  }

  void reply(int index, {String body = catalog, int status = 200}) {
    if (!pending[index].isCompleted) {
      pending[index].complete(
        http.StreamedResponse(Stream.value(body.codeUnits), status),
      );
    }
  }
}

class _Ai extends Fake implements AiService {}

AppController controllerFor(RemoteAssetService service) => AppController(
  preferencesService: PreferencesService(),
  aiService: _Ai(),
  gameManifestService: GameManifestService(),
  remoteAssetService: service,
  speechService: SpeechService(),
  ttsService: TtsService(),
);
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'reads race both entrances, fastest success returns and aborts loser',
    () async {
      final client = _Client();
      final service = RemoteAssetService(client: client);
      final read = service.fetchRemoteText(
        sources: sources,
        remotePath: 'assets/catalog.json',
      );
      await settle();
      expect(client.requests.length, 2);
      client.reply(1, body: 'winner');
      expect(await read, 'winner');
      await settle();
      expect(client.aborted, [0]);
      client.reply(0, body: 'late response');
    },
  );
  test(
    'a fast failure cannot cancel or win over a slower successful entrance',
    () async {
      final client = _Client();
      final read = RemoteAssetService(
        client: client,
      ).fetchRemoteBytes(sources: sources, remotePath: 'assets/catalog.json');
      client.reply(0, status: 401);
      await settle();
      expect(client.aborted, isEmpty);
      client.reply(1, body: 'okay');
      expect(await read, 'okay'.codeUnits);
    },
  );
  test('all failed entrances return no data and no hanging request', () async {
    final client = _Client();
    final read = RemoteAssetService(
      client: client,
    ).fetchRemoteBytes(sources: sources, remotePath: 'assets/catalog.json');
    client.reply(0, status: 404);
    client.reply(1, status: 503);
    expect(await read, isNull);
  });
  test('timeouts abort both requests within one deadline', () async {
    final client = _Client();
    final service = RemoteAssetService(
      client: client,
      requestTimeout: const Duration(milliseconds: 30),
    );
    expect(
      await service.fetchRemoteBytes(
        sources: sources,
        remotePath: 'assets/catalog.json',
      ),
      isNull,
    );
    await settle();
    expect(client.aborted, [0, 1]);
  });
  test(
    'directory reads race entrances through the shared WebDAV parser',
    () async {
      final client = _Client();
      final read = RemoteAssetService(
        client: client,
      ).listFilesRecursively(sources: sources, remotePath: 'assets/docs');
      expect(client.requests.map((r) => r.method), ['PROPFIND', 'PROPFIND']);
      client.reply(
        1,
        status: 207,
        body: '''
      <d:multistatus xmlns:d="DAV:"><d:response>
      <d:href>/friend/apps/board_game_agent/board-game-lib/docs/test.pdf</d:href>
      <d:propstat><d:prop><d:resourcetype/><d:getetag>x</d:getetag></d:prop>
      <d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response></d:multistatus>
    ''',
      );
      final files = await read;
      expect(files.single.name, 'test.pdf');
      expect(files.single.sourceId, 'outside');
      await settle();
      expect(client.aborted, [0]);
    },
  );
  test(
    'all directory entrance failures remain retryable without internal errors',
    () async {
      final client = _Client();
      final read = RemoteAssetService(
        client: client,
      ).listFilesRecursively(sources: sources, remotePath: 'assets/docs');
      final expectation = expectLater(
        read,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'safe message',
            '资料目录暂时无法读取，请重试',
          ),
        ),
      );
      client.reply(0, status: 401, body: 'internal secret');
      client.reply(1, status: 503, body: 'internal secret');
      await expectation;
    },
  );
  test(
    'catalog health rejects an HTTP success containing HTML or invalid data',
    () async {
      for (final body in ['<html>login</html>', '{"games":"bad"}', '']) {
        final client = _Client();
        final probe = RemoteAssetService(
          client: client,
        ).checkAccess(sources.first);
        client.reply(0, body: body);
        expect((await probe).state, ConnectivityState.failure);
      }
    },
  );
  test(
    'health returns specific, sanitized authentication and directory failures',
    () async {
      for (final entry in {
        401: '需要重新登录',
        403: '没有资料访问权限',
        404: '找不到知识库目录',
      }.entries) {
        final client = _Client();
        final probe = RemoteAssetService(
          client: client,
        ).checkAccess(sources.first);
        client.reply(0, status: entry.key, body: 'internal secret');
        expect((await probe).message, entry.value);
      }
    },
  );
  test(
    'availability succeeds immediately; slow entrance remains visible then fails without downgrading',
    () async {
      final client = _Client();
      final app = controllerFor(RemoteAssetService(client: client));
      addTearDown(app.dispose);
      await app.saveAssetSourceConfigs(sources);
      final check = app.refreshAssetAccessStatus();
      expect(identical(check, app.refreshAssetAccessStatus()), isTrue);
      await settle();
      expect(client.requests.length, 2);
      client.reply(1);
      await settle();
      expect(app.assetConnectivityStatus.state, ConnectivityState.success);
      expect(
        app.assetSourceStatuses['inside']!.state,
        ConnectivityState.loading,
      );
      client.reply(0, status: 503);
      await check;
      expect(app.assetConnectivityStatus.state, ConnectivityState.success);
      expect(
        app.assetSourceStatuses['inside']!.state,
        ConnectivityState.failure,
      );
    },
  );
  test(
    'configuration changes abort old checks and late results cannot replace new status',
    () async {
      final client = _Client();
      final app = controllerFor(RemoteAssetService(client: client));
      addTearDown(app.dispose);
      await app.saveAssetSourceConfigs(sources);
      final old = app.refreshAssetAccessStatus();
      await settle();
      await app.saveAssetSourceConfigs([
        sources.last.copyWith(
          id: 'new',
          testUrl: 'https://new.example/friend/',
        ),
      ]);
      await old;
      expect(client.aborted, [0, 1]);
      expect(app.assetConnectivityStatus.state, ConnectivityState.unknown);
      expect(app.assetSourceStatuses.keys, ['new']);
      final next = app.refreshAssetAccessStatus();
      await settle();
      client.reply(2);
      await next;
      expect(app.assetConnectivityStatus.state, ConnectivityState.success);
      expect(app.assetSourceStatuses.keys, ['new']);
    },
  );
  for (final reduced in [false, true]) {
    testWidgets(
      'refresh is independent from details and follows check lifecycle (reduced=$reduced)',
      (tester) async {
        final client = _Client();
        final app = controllerFor(RemoteAssetService(client: client));
        addTearDown(app.dispose);
        await tester.runAsync(() => app.saveAssetSourceConfigs(sources));
        late Future<void> check;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.buildTheme(PaletteRegistry.classic),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: child!,
            ),
            home: Scaffold(
              body: ResourceAccessSummary(
                controller: app,
                onRefresh: () => check = app.refreshAssetAccessStatus(),
              ),
            ),
          ),
        );
        final refresh = find.byKey(const ValueKey('resource-access-refresh'));
        await tester.runAsync(() async {
          await tester.tap(refresh);
          await settle();
        });
        await tester.pump();
        expect(find.byType(AlertDialog), findsNothing);
        expect(client.requests.length, 2);
        expect(tester.widget<IconButton>(refresh).onPressed, isNull);
        await tester.pump(const Duration(milliseconds: 150));
        final rotation = tester
            .widget<RotationTransition>(
              find.byKey(const ValueKey('resource-access-refresh-rotation')),
            )
            .turns;
        expect(rotation.value, reduced ? 0 : greaterThan(0));
        // Tapping the status row opens diagnostics without starting another check.
        await tester.tap(find.text(app.copy.assetStatusTitle));
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('内网入口'), findsOneWidget);
        expect(client.requests.length, 2);
        await tester.runAsync(() async {
          client.reply(0, status: 403);
          client.reply(1, status: reduced ? 403 : 200);
          await check;
        });
        await tester.pumpAndSettle();
        expect(rotation.value, 0);
        expect(
          app.assetConnectivityStatus.state,
          reduced ? ConnectivityState.failure : ConnectivityState.success,
        );
        await tester.tap(find.text(app.copy.dialogClose));
        await tester.pumpAndSettle();
        expect(tester.widget<IconButton>(refresh).onPressed, isNotNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final width in [320.0, 1280.0]) {
    testWidgets('access summary and live entrance details fit $width', (
      tester,
    ) async {
      final client = _Client();
      final app = controllerFor(RemoteAssetService(client: client));
      addTearDown(app.dispose);
      await tester.runAsync(() => app.saveAssetSourceConfigs(sources));
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.buildTheme(PaletteRegistry.classic),
          home: Scaffold(
            body: ResourceAccessSummary(
              controller: app,
              onReorder: (from, to) {},
            ),
          ),
        ),
      );
      expect(find.text('内网入口'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('resource-access-summary')));
      await tester.pumpAndSettle();
      expect(find.text('内网入口'), findsOneWidget);
      expect(find.text('外网入口'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final check = app.refreshAssetAccessStatus();
        await settle();
        client.reply(1);
        client.reply(0, status: 403);
        await check;
      });
      await tester.pumpAndSettle();
      expect(find.text('资源可用'), findsNWidgets(2));
      expect(find.text('没有资料访问权限'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
