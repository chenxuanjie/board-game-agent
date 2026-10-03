import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_settings/webdav_settings.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:board_game_agent/app/state/app_controller.dart';
import 'package:board_game_agent/core/localization/app_copy.dart';
import 'package:board_game_agent/core/localization/app_language.dart';
import 'package:board_game_agent/core/theme/app_theme.dart';
import 'package:board_game_agent/features/assistant/models/ai_api_config.dart';
import 'package:board_game_agent/features/assistant/services/ai_service.dart';
import 'package:board_game_agent/features/assistant/services/conversation_store.dart';
import 'package:board_game_agent/features/assistant/services/speech_service.dart';
import 'package:board_game_agent/features/assistant/services/tts_service.dart';
import 'package:board_game_agent/features/games/services/game_manifest_service.dart';
import 'package:board_game_agent/features/library/models/asset_source_config.dart';
import 'package:board_game_agent/features/library/services/remote_asset_service.dart';
import 'package:board_game_agent/features/settings/models/configuration_transfer.dart';
import 'package:board_game_agent/features/settings/services/preferences_service.dart';
import 'package:board_game_agent/features/settings/services/settings_transfer_service.dart';
import 'package:board_game_agent/ui/shared/settings_transfer_screen.dart';
import 'package:board_game_agent/ui/shared/resource_connection_screen.dart';
import 'package:board_game_agent/ui/mobile/settings_screen.dart';
import 'package:board_game_agent/ui/desktop/settings_pane.dart';
import 'package:board_game_agent/ui/desktop/desktop_responsive.dart';

const _oldAi = AiApiConfig(
  name: 'Old',
  baseUrl: 'https://old-ai.example/v1',
  apiKey: 'old-ai-secret',
  model: 'gpt-5.6-sol',
  apiKeyHeader: 'Authorization',
);
const _newAi = AiApiConfig(
  name: 'Gateway',
  baseUrl: 'https://ai.example/v1',
  apiKey: 'new-ai-secret',
  model: 'gpt-6-astra',
  apiKeyHeader: 'Authorization',
  reasoningEffort: AiReasoningEffort.high,
  responseSpeed: AiResponseSpeed.fast,
);
const _oldDav = WebDavSettings(
  mode: ExternalStorageMode.webDav,
  baseUrl: 'https://old-dav.example/friend/',
  username: 'old-user',
  password: 'old-dav-secret',
);
const _newDav = WebDavSettings(
  baseUrl: 'https://dav.example/friend/',
  username: 'new-user',
  password: 'new-dav-secret',
);

class _Journal implements ConfigurationTransferJournal {
  Map<String, dynamic>? value;
  bool failCommit = false;
  bool failClear = false;
  @override
  Future<Map<String, dynamic>?> read() async => value;
  @override
  Future<void> write(Map<String, dynamic> next) async {
    if (failCommit && next['committed'] == true) {
      failCommit = false;
      throw StateError('simulated commit write failure');
    }
    value = jsonDecode(jsonEncode(next)) as Map<String, dynamic>;
  }

  @override
  Future<void> clear() async {
    if (failClear) throw StateError('simulated cleanup failure');
    value = null;
  }
}

class _Preferences extends PreferencesService {
  AiApiConfig ai = _oldAi;
  List<AssetSourceConfig> sources = AssetSourceConfig.defaults.toList();
  bool failAi = false;
  bool failSources = false;
  @override
  Future<void> saveAiApiConfig(AiApiConfig value) async {
    if (failAi) {
      failAi = false;
      throw StateError('simulated AI write failure');
    }
    ai = value;
  }

  @override
  Future<void> saveAssetSourceConfigs(List<AssetSourceConfig> value) async {
    if (failSources) {
      failSources = false;
      throw StateError('simulated source write failure');
    }
    sources = value.toList();
  }

  @override
  Future<void> saveAiCustomPresets(Iterable<AiApiConfig> configs) async {}
}

class _DavStore implements WebDavSettingsStore {
  WebDavSettings value = _oldDav;
  bool failSave = false;
  @override
  Future<WebDavSettings?> load() async => value;
  @override
  Future<void> save(WebDavSettings next) async {
    if (failSave) {
      failSave = false;
      throw StateError('simulated DAV write failure');
    }
    value = next;
  }
}

class _Tester implements WebDavConnectionTester {
  int calls = 0;
  bool fail = false;
  @override
  Future<WebDavConnectionTestResult> test(WebDavSettings settings) async {
    calls++;
    if (fail) throw StateError('simulated network failure');
    return const WebDavConnectionTestResult.success();
  }
}

class _NoAi extends Fake implements AiService {}

class _NoNetwork extends RemoteAssetService {
  @override
  Future<File?> cachedFileFor(String remotePath) async => null;
}

class _NoTts extends TtsService {
  @override
  bool get isAvailable => false;
}

class _Conversations extends ConversationStore {
  @override
  Future<void> save(String payload) async {}
}

class _Fixture {
  final preferences = _Preferences();
  final store = _DavStore();
  final tester = _Tester();
  final journal = _Journal();
  late final dav = WebDavSettingsController(
    store: store,
    connectionTester: tester,
  );
  late final app = AppController(
    preferencesService: preferences,
    aiService: _NoAi(),
    gameManifestService: GameManifestService(),
    remoteAssetService: _NoNetwork(),
    speechService: SpeechService(),
    ttsService: _NoTts(),
    conversationStore: _Conversations(),
  );
  late final service = SettingsTransferService(
    controller: app,
    webDav: dav,
    journal: journal,
  );
  Future<void> setup() async {
    await dav.load();
    await app.saveAiApiConfig(_oldAi);
  }

  void dispose() {
    app.dispose();
    dav.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Noto Sans SC',
    )..addFont(rootBundle.load('assets/fonts/NotoSansSC-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
  test(
    'connection save activates WebDAV, prioritizes edited source and rolls back failed source writes',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.setup();
      final selected = f.app.assetSourceConfigs.last;
      f.preferences.failSources = true;
      await expectLater(
        f.service.apply(
          dav: _newDav,
          activateWebDav: true,
          resourceSource: selected,
        ),
        throwsA(isA<ConfigurationTransferException>()),
      );
      expect(f.dav.saved.baseUrl, _oldDav.baseUrl);
      await f.service.apply(
        dav: _newDav,
        activateWebDav: true,
        resourceSource: selected,
      );
      expect(f.dav.saved.mode, ExternalStorageMode.webDav);
      expect(f.app.assetSourceConfigs.first.id, selected.id);
      expect(f.app.assetSourceConfigs.first.testUrl, _newDav.baseUrl);
      expect(
        f.app.assetSourceConfigs.where((s) => s.id == selected.id),
        hasLength(1),
      );
      expect(f.tester.calls, 0);
      final reloaded = WebDavSettingsController(
        store: f.store,
        connectionTester: f.tester,
      );
      addTearDown(reloaded.dispose);
      await reloaded.load();
      expect(reloaded.saved.baseUrl, _newDav.baseUrl);
      expect(reloaded.saved.password, _newDav.password);
      final requests = <http.Request>[];
      final remote = RemoteAssetService(
        settingsProvider: () => reloaded.saved,
        client: MockClient((request) async {
          requests.add(request);
          return http.Response('rule', 200);
        }),
      );
      expect(
        await remote.fetchRemoteText(
          sources: f.app.assetSourceConfigs,
          remotePath: 'assets/catalog.json',
        ),
        'rule',
      );
      expect(requests.single.url.host, 'dav.example');
      expect(
        requests.single.headers['Authorization'],
        'Basic ${base64Encode(utf8.encode('${_newDav.username}:${_newDav.password}'))}',
      );
    },
  );
  testWidgets(
    'mobile connection edits persist, malformed URLs do not save and failed check remains editable',
    (tester) async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.setup();
      await tester.binding.setSurfaceSize(const Size(320, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.buildTheme(f.app.palette),
          home: MobileSettingsScreen(
            controller: f.app,
            transferService: f.service,
            onOpenAbout: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final entry = find.byKey(
        const ValueKey('mobile-settings-webdav-connection'),
      );
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      final url = find.byKey(const ValueKey('resource-connection-url'));
      await tester.enterText(url, 'not a url');
      await tester.tap(find.byKey(const ValueKey('resource-connection-save')));
      await tester.pumpAndSettle();
      expect(f.dav.saved.baseUrl, _oldDav.baseUrl);
      expect(find.text('请输入有效的 HTTP 或 HTTPS 地址'), findsOneWidget);
      await tester.enterText(url, _newDav.baseUrl);
      await tester.enterText(
        find.byKey(const ValueKey('resource-connection-username')),
        _newDav.username,
      );
      await tester.enterText(
        find.byKey(const ValueKey('resource-connection-password')),
        _newDav.password,
      );
      f.tester.fail = true;
      await tester.tap(find.byKey(const ValueKey('resource-connection-test')));
      await tester.pumpAndSettle();
      expect(find.text('连接检测失败，请检查地址与账号后重试。'), findsOneWidget);
      expect(f.dav.saved.baseUrl, _oldDav.baseUrl);
      expect(tester.widget<TextFormField>(url).enabled, isTrue);
      await tester.tap(find.byKey(const ValueKey('resource-connection-save')));
      await tester.pumpAndSettle();
      expect(find.byType(ResourceConnectionScreen), findsNothing);
      expect(f.dav.saved.baseUrl, _newDav.baseUrl);
      expect(f.dav.saved.mode, ExternalStorageMode.webDav);
      expect(f.app.assetSourceConfigs.first.testUrl, _newDav.baseUrl);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'resource connection fits phone and desktop widths with larger text',
    (tester) async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.setup();
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final width in [320.0, 390.0, 1280.0]) {
        await tester.binding.setSurfaceSize(Size(width, 820));
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            theme: AppTheme.buildTheme(f.app.palette),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: ResourceConnectionScreen(
              service: f.service,
              source: f.app.assetSourceConfigs.last,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(
                find.descendant(
                  of: find.byKey(
                    const ValueKey('resource-connection-password'),
                  ),
                  matching: find.byType(TextField),
                ),
              )
              .obscureText,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test(
    'imported WebDAV credentials stay within the configured origin and root',
    () async {
      final requests = <http.Request>[];
      final service = RemoteAssetService(
        settingsProvider: () => _newDav,
        client: MockClient((request) async {
          requests.add(request);
          return http.Response('missing', 404);
        }),
      );
      await service.fetchRemoteBytes(
        sources: [
          const AssetSourceConfig(
            id: 'own',
            name: 'Own',
            address: '',
            testUrl: 'https://dav.example/friend/',
          ),
          const AssetSourceConfig(
            id: 'other',
            name: 'Other',
            address: '',
            testUrl: 'https://other.example/friend/',
          ),
          const AssetSourceConfig(
            id: 'sibling',
            name: 'Sibling',
            address: '',
            testUrl: 'https://dav.example/another/',
          ),
          const AssetSourceConfig(
            id: 'insecure',
            name: 'Insecure',
            address: '',
            testUrl: 'http://dav.example/friend/',
          ),
        ],
        remotePath: 'games/demo/rule.pdf',
      );
      expect(requests, hasLength(4));
      expect(
        requests.first.headers['Authorization'],
        'Basic ${base64Encode(utf8.encode('${_newDav.username}:${_newDav.password}'))}',
      );
      for (final request in requests.skip(1)) {
        expect(request.headers.containsKey('Authorization'), isFalse);
      }
    },
  );
  test('a failed optional WebDAV check remains retryable', () async {
    final f = _Fixture();
    addTearDown(f.dispose);
    await f.setup();
    await f.service.apply(dav: _newDav);
    f.tester.fail = true;
    await expectLater(f.dav.testConnection(), throwsStateError);
    expect(f.dav.isTesting, isFalse);
    expect(f.dav.canEnableWebDav, isFalse);
    f.tester.fail = false;
    expect((await f.dav.testConnection()).isSuccess, isTrue);
    await f.dav.enableWebDav();
    expect(f.dav.saved.mode, ExternalStorageMode.webDav);
  });
  group('offline configuration parsing', () {
    test('three scopes round-trip codes with or without credentials', () {
      for (final scope in ConfigurationScope.values) {
        for (final secrets in [true, false]) {
          final payload = ConfigurationTransfer.payload(
            _newAi,
            _newDav,
            scope,
            includeSecrets: secrets,
          );
          final parsed = ConfigurationTransfer.parse(
            ConfigurationTransfer.encode(payload),
          );
          expect(parsed.ai.isNotEmpty, scope != ConfigurationScope.webDav);
          expect(parsed.webDav.isNotEmpty, scope != ConfigurationScope.ai);
          expect(
            parsed.ai.containsKey('apiKey'),
            secrets && scope != ConfigurationScope.webDav,
          );
          expect(
            parsed.webDav.containsKey('password'),
            secrets && scope != ConfigurationScope.ai,
          );
          expect(parsed.unassigned, isEmpty);
        }
      }
    });
    test(
      'readable formats round-trip delimiters and multiline secrets in both languages',
      () {
        final ai = _newAi.copyWith(apiKey: 'abc:=\nxyz "quoted"');
        final dav = _newDav.copyWith(password: ' :Password\nwith spaces: ');
        for (final language in AppLanguage.values) {
          final parsed = ConfigurationTransfer.parse(
            ConfigurationTransfer.readable(
              ConfigurationTransfer.payload(
                ai,
                dav,
                ConfigurationScope.all,
                includeSecrets: true,
              ),
              AppCopy(language),
            ),
          );
          expect(parsed.ai['apiKey'], ai.apiKey);
          expect(parsed.webDav['password'], dav.password);
          expect(parsed.unassigned, isEmpty);
        }
      },
    );
    test('smart text identifies single AI, single DAV and a combined paste', () {
      final ai = ConfigurationTransfer.parse(
        'Base URL = https://ai.example/v1\nAPI Key：test-key\n模型: gpt-6-astra',
      );
      expect(ai.ai['baseUrl'], 'https://ai.example/v1');
      expect(ai.webDav, isEmpty);
      final dav = ConfigurationTransfer.parse(
        '地址：https://dav.example/friend/\n账号：sample\n密码：sample-password',
      );
      expect(dav.webDav['baseUrl'], 'https://dav.example/friend/');
      expect(dav.ai, isEmpty);
      final both = ConfigurationTransfer.parse(
        'AI 地址：https://ai.example/v1\nAPI Key: key\nWebDAV 地址：https://dav.example/\n账号：sample\n密码：password',
      );
      expect(both.ai['baseUrl'], 'https://ai.example/v1');
      expect(both.webDav['baseUrl'], 'https://dav.example/');
    });
    test('ambiguous and conflicting addresses require review', () {
      final parsed = ConfigurationTransfer.parse(
        '地址：https://unknown.example\nAPI Key: key\n账号：sample',
      );
      expect(parsed.unassigned, hasLength(1));
      expect(parsed.ai.containsKey('baseUrl'), isFalse);
      expect(parsed.webDav.containsKey('baseUrl'), isFalse);
      final duplicate = ConfigurationTransfer.parse(
        '[AI]\n地址：https://first.example\n地址：https://second.example',
      );
      expect(duplicate.ai['baseUrl'], 'https://first.example');
      expect(duplicate.unassigned, hasLength(1));
    });
    test(
      'damaged codes, invalid schemas and oversized input never apply defaults',
      () {
        final code = ConfigurationTransfer.encode(
          ConfigurationTransfer.payload(_newAi, null, ConfigurationScope.ai),
        );
        for (final value in [
          '${code.substring(0, code.length - 3)}abc',
          'BGA2:abc',
          '{"version":2,"ai":{}}',
          '{"ai":{"apiKey":123}}',
          '{bad json}',
          'hello',
          List.filled(65537, 'x').join(),
        ]) {
          expect(
            () => ConfigurationTransfer.parse(value),
            throwsA(isA<ConfigurationTransferException>()),
          );
        }
      },
    );
    test(
      'missing fields preserve existing values except credentials for a changed URL',
      () {
        expect(
          ConfigurationTransfer.prepareAi({
            'model': 'gpt-6-astra',
          }, _oldAi)['apiKey'],
          _oldAi.apiKey,
        );
        expect(
          ConfigurationTransfer.prepareAi({
            'baseUrl': _newAi.baseUrl,
          }, _oldAi)['apiKey'],
          isEmpty,
        );
        final dav = ConfigurationTransfer.prepareWebDav({
          'baseUrl': _newDav.baseUrl,
        }, _oldDav);
        expect(dav['password'], isEmpty);
        expect(dav['username'], isEmpty);
        expect(
          ConfigurationTransfer.prepareWebDav({
            'username': 'edited',
          }, _oldDav)['password'],
          _oldDav.password,
        );
      },
    );
  });

  for (final scope in ConfigurationScope.values) {
    test(
      'applies ${scope.name} offline and preserves unrelated source priority',
      () async {
        final f = _Fixture();
        addTearDown(f.dispose);
        await f.setup();
        await f.service.apply(
          ai: scope == ConfigurationScope.webDav ? null : _newAi,
          dav: scope == ConfigurationScope.ai ? null : _newDav,
        );
        expect(
          f.app.aiApiConfig.baseUrl,
          scope == ConfigurationScope.webDav ? _oldAi.baseUrl : _newAi.baseUrl,
        );
        expect(
          f.dav.saved.baseUrl,
          scope == ConfigurationScope.ai ? _oldDav.baseUrl : _newDav.baseUrl,
        );
        expect(f.tester.calls, 0);
        expect(f.journal.value, isNull);
        if (scope != ConfigurationScope.ai) {
          expect(f.dav.saved.mode, ExternalStorageMode.localOnly);
          expect(
            f.app.assetSourceConfigs.skip(1).map((item) => item.id),
            AssetSourceConfig.defaults.map((item) => item.id),
          );
          await f.service.apply(dav: _newDav);
          expect(
            f.app.assetSourceConfigs.where(
              (item) => item.id == 'configured_webdav',
            ),
            hasLength(1),
          );
        }
      },
    );
  }
  for (final failure in ['ai', 'dav', 'sources', 'commit']) {
    test('rolls back both stores on $failure failure', () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.setup();
      f.preferences.failAi = failure == 'ai';
      f.preferences.failSources = failure == 'sources';
      f.store.failSave = failure == 'dav';
      f.journal.failCommit = failure == 'commit';
      await expectLater(
        f.service.apply(ai: _newAi, dav: _newDav),
        throwsA(isA<ConfigurationTransferException>()),
      );
      expect(f.app.aiApiConfig.toMap(), _oldAi.toMap());
      expect(f.preferences.ai.toMap(), _oldAi.toMap());
      expect(f.dav.saved.mode, _oldDav.mode);
      expect(f.store.value.baseUrl, _oldDav.baseUrl);
      expect(
        f.app.assetSourceConfigs.map((item) => item.id),
        AssetSourceConfig.defaults.map((item) => item.id),
      );
      expect(f.journal.value, isNull);
      expect(f.tester.calls, 0);
    });
  }
  test(
    'committed cleanup failure does not roll back on the next startup',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.setup();
      f.journal.failClear = true;
      await f.service.apply(ai: _newAi, dav: _newDav);
      expect(f.journal.value!['committed'], isTrue);
      f.journal.failClear = false;
      await f.service.recover();
      expect(f.app.aiApiConfig.toMap(), _newAi.toMap());
      expect(f.dav.saved.baseUrl, _newDav.baseUrl);
      expect(f.journal.value, isNull);
    },
  );
  test(
    'recovers an interrupted import before loading user configuration',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.setup();
      f.journal.value = {
        'version': 1,
        'committed': false,
        'ai': _oldAi.toMap(),
        'webdav': {
          'mode': _oldDav.mode.name,
          'baseUrl': _oldDav.baseUrl,
          'username': _oldDav.username,
          'password': _oldDav.password,
        },
        'sources': AssetSourceConfig.defaults.map((e) => e.toMap()).toList(),
      };
      await f.app.saveAiApiConfig(_newAi);
      await f.dav.saveConfiguration(_newDav);
      await f.service.recover();
      expect(f.app.aiApiConfig.toMap(), _oldAi.toMap());
      expect(f.dav.saved.baseUrl, _oldDav.baseUrl);
      expect(f.dav.saved.mode, _oldDav.mode);
      expect(f.journal.value, isNull);
    },
  );

  testWidgets(
    'import previews before saving, can select one scope and preserves credentials masking',
    (tester) async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.setup();
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.buildTheme(f.app.palette),
          home: SettingsTransferScreen(service: f.service),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('transfer-input')),
        ConfigurationTransfer.encode(
          ConfigurationTransfer.payload(
            _newAi,
            _newDav,
            ConfigurationScope.all,
            includeSecrets: true,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('transfer-recognize')));
      await tester.pumpAndSettle();
      expect(f.app.aiApiConfig.toMap(), _oldAi.toMap());
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('transfer-ai-apiKey')))
            .obscureText,
        isTrue,
      );
      final davSelection = find.byKey(const ValueKey('transfer-select-webdav'));
      await tester.ensureVisible(davSelection);
      await tester.tap(davSelection);
      await tester.pumpAndSettle();
      final apply = find.byKey(const ValueKey('transfer-apply'));
      await tester.ensureVisible(apply);
      await tester.tap(apply);
      await tester.pumpAndSettle();
      expect(f.app.aiApiConfig.toMap(), _newAi.toMap());
      expect(f.dav.saved.baseUrl, _oldDav.baseUrl);
      expect(f.tester.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('export clipboard round-trips and omits credentials by default', (
    tester,
  ) async {
    final f = _Fixture();
    addTearDown(f.dispose);
    await f.setup();
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildTheme(f.app.palette),
        home: SettingsTransferScreen(service: f.service, initialExport: true),
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('transfer-copy')),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('transfer-copy')));
    await tester.pumpAndSettle();
    final parsed = ConfigurationTransfer.parse(clipboard!);
    expect(parsed.ai.containsKey('apiKey'), isFalse);
    expect(parsed.webDav.containsKey('password'), isFalse);
    await tester.ensureVisible(
      find.byKey(const ValueKey('transfer-include-secrets')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('transfer-include-secrets')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('transfer-copy')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('transfer-copy')));
    await tester.pumpAndSettle();
    expect(ConfigurationTransfer.parse(clipboard!).ai['apiKey'], _oldAi.apiKey);
    expect(
      ConfigurationTransfer.parse(clipboard!).webDav['password'],
      _oldDav.password,
    );
  });
  testWidgets(
    'ignoring an assigned credential and editing pasted text cannot apply stale values',
    (tester) async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.setup();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.buildTheme(f.app.palette),
          home: SettingsTransferScreen(service: f.service),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('transfer-input')),
        '[AI]\n地址: ${_oldAi.baseUrl}\n备用: temporary-secret',
      );
      await tester.tap(find.byKey(const ValueKey('transfer-recognize')));
      await tester.pumpAndSettle();
      final assignment = find.byKey(const ValueKey('transfer-assign-0'));
      await tester.scrollUntilVisible(
        assignment,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      tester.widget<DropdownButtonFormField<String>>(assignment).onChanged!(
        'ai.apiKey',
      );
      await tester.pumpAndSettle();
      tester.widget<DropdownButtonFormField<String>>(assignment).onChanged!(
        'ignore',
      );
      await tester.pumpAndSettle();
      final url = find.byKey(const ValueKey('transfer-ai-baseUrl'));
      await tester.scrollUntilVisible(
        url,
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(url, _newAi.baseUrl);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('transfer-ai-apiKey')))
            .controller!
            .text,
        isEmpty,
      );
      await tester.scrollUntilVisible(
        find.text('编辑粘贴内容'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑粘贴内容'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('transfer-input')),
        'not a configuration',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('transfer-apply')), findsNothing);
      expect(f.app.aiApiConfig.toMap(), _oldAi.toMap());
      expect(f.tester.calls, 0);
    },
  );
  testWidgets(
    'transfer layouts and settings entries fit compact and desktop sizes',
    (tester) async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.setup();
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final width in [320.0, 390.0, 1280.0]) {
        for (final scale in [1.0, 1.5]) {
          await tester.binding.setSurfaceSize(Size(width, 800));
          await tester.pumpWidget(
            MaterialApp(
              key: UniqueKey(),
              theme: AppTheme.buildTheme(f.app.palette),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: SettingsTransferScreen(service: f.service),
            ),
          );
          await tester.enterText(
            find.byKey(const ValueKey('transfer-input')),
            ConfigurationTransfer.encode(
              ConfigurationTransfer.payload(
                _newAi,
                _newDav,
                ConfigurationScope.all,
                includeSecrets: true,
              ),
            ),
          );
          await tester.tap(find.byKey(const ValueKey('transfer-recognize')));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('transfer-apply')),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          expect(tester.takeException(), isNull);
        }
      }
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          theme: AppTheme.buildTheme(f.app.palette),
          home: MobileSettingsScreen(
            controller: f.app,
            transferService: f.service,
            onOpenAbout: () {},
          ),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('settings-transfer-menu-all')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('粘贴导入'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsTransferScreen), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          theme: AppTheme.buildTheme(f.app.palette),
          home: Scaffold(
            body: DesktopMetricsScope(
              metrics: DesktopResponsive.metricsFor(const Size(1280, 800)),
              child: SingleChildScrollView(
                child: DesktopSettingsPane(
                  controller: f.app,
                  transferService: f.service,
                  webDavSettingsController: f.dav,
                  onOpenAbout: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('settings-transfer-menu-all')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('复制配置'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsTransferScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
