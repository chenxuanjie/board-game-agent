import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_about/app_about.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remote_update/remote_update.dart';
import 'package:webdav_settings/webdav_settings.dart';

import 'package:board_game_agent/features/library/services/board_game_remote_layout.dart';
import 'package:board_game_agent/features/settings/services/windows_update_service_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late WebDavSettings settings;
  late List<int> bytes;
  late Map<String, Object?> manifest;
  late RecordingInstaller installer;
  late List<Uri> requests;
  late WindowsWebDavUpdateService service;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('bga-update-test-');
    settings = const WebDavSettings(
      mode: ExternalStorageMode.webDav,
      baseUrl: 'https://update.example/friend/',
      username: 'test-user',
      password: 'test-password',
    );
    bytes = [0x4d, 0x5a, ...List.generate(256, (i) => i)];
    manifest = {
      'schemaVersion': 1,
      'appId': 'board_game_agent',
      'channel': 'stable',
      'versionName': '2.1.0',
      'buildNumber': 24,
      'releaseNotes': {
        'zh-CN': ['支持 Windows 应用内更新'],
      },
      'artifacts': [
        {
          'platform': 'windows',
          'architecture': 'x64',
          'path': 'board_game_agent-2.1.0+24-windows-x64-setup.exe',
          'size': bytes.length,
          'sha256': sha256.convert(bytes).toString(),
          'mimeType': 'application/octet-stream',
        },
      ],
    };
    installer = RecordingInstaller();
    requests = [];
    service = WindowsWebDavUpdateService(
      settingsProvider: () => settings,
      installedVersion: () async => ('2.1.0', 23),
      downloadDirectory: temporary,
      installer: installer,
      isWindows: true,
      clientFactory: () => MockClient((request) async {
        requests.add(request.url);
        expect(
          request.headers['authorization'],
          'Basic ${base64Encode(utf8.encode('test-user:test-password'))}',
        );
        return request.url.path.endsWith('manifest.json')
            ? http.Response(
                jsonEncode(manifest),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              )
            : http.Response.bytes(bytes, 200);
      }),
    );
  });
  tearDown(() async {
    service.dispose();
    await temporary.delete(recursive: true);
  });

  Map<String, Object?> getArtifact() =>
      (manifest['artifacts'] as List).single as Map<String, Object?>;

  test(
    'checks Windows-only manifest, verifies download and reports progress',
    () async {
      final info = await service.check();
      expect(info.status, AppUpdateStatus.available);
      expect(info.latestBuild, 24);
      expect(info.releaseNotes, ['支持 Windows 应用内更新']);
      expect(
        requests.single.path,
        '/friend/${BoardGameRemoteLayout.windowsUpdateManifestPath}',
      );
      final progress = <AppUpdateProgress>[];
      await service.install(info, onProgress: progress.add);
      expect(
        installer.artifacts.single.sha256,
        sha256.convert(bytes).toString(),
      );
      expect(progress.last.fraction, 1);
      expect(
        Uri.decodeComponent(requests.last.path),
        endsWith('+24-windows-x64-setup.exe'),
      );
      await expectLater(service.install(info), throwsStateError);
    },
  );

  test('equal or older build does not offer update', () async {
    manifest['buildNumber'] = 23;
    expect((await service.check()).status, AppUpdateStatus.upToDate);
    manifest['buildNumber'] = 22;
    expect((await service.check()).status, AppUpdateStatus.upToDate);
    expect(installer.artifacts, isEmpty);
  });

  test(
    'missing configuration and unsafe HTTP never send credentials',
    () async {
      settings = settings.copyWith(mode: ExternalStorageMode.localOnly);
      expect((await service.check()).status, AppUpdateStatus.notConfigured);
      settings = settings.copyWith(
        mode: ExternalStorageMode.webDav,
        baseUrl: 'http://update.example/friend/',
      );
      expect((await service.check()).status, AppUpdateStatus.notConfigured);
      expect(requests, isEmpty);
    },
  );

  for (final change in ['identity', 'platform', 'architecture', 'path']) {
    test('rejects incorrect manifest $change', () async {
      switch (change) {
        case 'identity':
          manifest['appId'] = 'other-app';
        case 'platform':
          getArtifact()['platform'] = 'android';
        case 'architecture':
          getArtifact()['architecture'] = 'any';
        case 'path':
          getArtifact()['path'] = '../payload.exe';
      }
      expect((await service.check()).status, AppUpdateStatus.failed);
      expect(installer.artifacts, isEmpty);
    });
  }

  for (final mismatch in ['checksum', 'size']) {
    test(
      'rejects $mismatch mismatch, removes partial file and permits retry',
      () async {
        if (mismatch == 'checksum') getArtifact()['sha256'] = '0' * 64;
        if (mismatch == 'size') getArtifact()['size'] = bytes.length + 1;
        final info = await service.check();
        await expectLater(service.install(info), throwsStateError);
        expect(installer.artifacts, isEmpty);
        expect(temporary.listSync(), isEmpty);
        getArtifact()['sha256'] = sha256.convert(bytes).toString();
        getArtifact()['size'] = bytes.length;
        await service.install(await service.check());
        expect(installer.artifacts.length, 1);
      },
    );
  }

  test('changing connection after check requires a fresh check', () async {
    final info = await service.check();
    settings = settings.copyWith(baseUrl: 'https://new.example/friend/');
    await expectLater(service.install(info), throwsStateError);
    expect(requests.length, 1);
    expect(installer.artifacts, isEmpty);
  });

  test(
    'installer failure can retry a verified cache without downloading twice',
    () async {
      installer.fail = true;
      final info = await service.check();
      await expectLater(service.install(info), throwsStateError);
      installer.fail = false;
      await service.install(info);
      expect(requests.where((uri) => uri.path.endsWith('.exe')).length, 1);
      expect(installer.artifacts.length, 1);
    },
  );

  for (final status in [401, 403, 404, 429, 503]) {
    test(
      'HTTP $status is retryable and does not expose server response or credentials',
      () async {
        service.dispose();
        var responseStatus = status;
        service = WindowsWebDavUpdateService(
          settingsProvider: () => settings,
          installedVersion: () async => ('2.1.0', 23),
          downloadDirectory: temporary,
          installer: installer,
          isWindows: true,
          clientFactory: () => MockClient(
            (_) async => responseStatus == 200
                ? http.Response(
                    jsonEncode(manifest),
                    200,
                    headers: {
                      'content-type': 'application/json; charset=utf-8',
                    },
                  )
                : http.Response(
                    'test-password internal response',
                    responseStatus,
                  ),
          ),
        );
        final failed = await service.check();
        expect(failed.status, AppUpdateStatus.failed);
        expect(failed.message, isNot(contains('test-password')));
        expect(failed.message, isNot(contains('internal response')));
        responseStatus = 200;
        expect((await service.check()).status, AppUpdateStatus.available);
      },
    );
  }

  test(
    'invalid JSON, TLS and timeout errors stay retryable and sanitized',
    () async {
      service.dispose();
      var mode = 'json';
      service = WindowsWebDavUpdateService(
        settingsProvider: () => settings,
        installedVersion: () async => ('2.1.0', 23),
        downloadDirectory: temporary,
        installer: installer,
        isWindows: true,
        requestTimeout: const Duration(milliseconds: 20),
        clientFactory: () => MockClient((_) async {
          if (mode == 'tls') {
            throw const HandshakeException('private diagnostic');
          }
          if (mode == 'timeout') {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          return mode == 'ok'
              ? http.Response(
                  jsonEncode(manifest),
                  200,
                  headers: {'content-type': 'application/json; charset=utf-8'},
                )
              : http.Response('not json private diagnostic', 200);
        }),
      );
      for (mode in ['json', 'tls', 'timeout']) {
        final info = await service.check();
        expect(info.status, AppUpdateStatus.failed);
        expect(info.message, isNot(contains('private diagnostic')));
      }
      mode = 'ok';
      expect((await service.check()).status, AppUpdateStatus.available);
    },
  );

  test(
    'duplicate check and disposed operation cannot replace or install a candidate',
    () async {
      service.dispose();
      final response = Completer<http.Response>();
      service = WindowsWebDavUpdateService(
        settingsProvider: () => settings,
        installedVersion: () async => ('2.1.0', 23),
        downloadDirectory: temporary,
        installer: installer,
        isWindows: true,
        clientFactory: () => MockClient((_) => response.future),
      );
      final first = service.check();
      await Future<void>.delayed(Duration.zero);
      expect((await service.check()).status, AppUpdateStatus.failed);
      service.dispose();
      response.complete(
        http.Response(
          jsonEncode(manifest),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      expect((await first).status, AppUpdateStatus.failed);
      expect(installer.artifacts, isEmpty);
    },
  );

  test(
    'installer rechecks integrity, flushes writes, preserves custom install path and exits only after launch',
    () async {
      final file = File('${temporary.path}/verified setup.exe');
      await file.writeAsBytes(bytes);
      final installedDir = Directory('${temporary.path}/custom installation');
      await installedDir.create();
      await File('${installedDir.path}/unins000.exe').writeAsString('marker');
      final steps = <String>[];
      final native = WindowsUpdateInstaller(
        executablePath: '${installedDir.path}/board_game_agent.exe',
        beforeInstall: () async => steps.add('flush'),
        launch: (path, args) async {
          expect(path, file.absolute.path);
          expect(args, contains('/DIR=${installedDir.absolute.path}'));
          expect(args, contains('/NOFORCECLOSEAPPLICATIONS'));
          expect(args.any((arg) => arg.contains('SILENT')), false);
          steps.add('launch');
        },
        onInstallerLaunched: () async => steps.add('close'),
      );
      final downloaded = DownloadedUpdateArtifact(
        artifact: UpdateArtifact.fromJson(getArtifact()),
        filePath: file.path,
        size: bytes.length,
        sha256: sha256.convert(bytes).toString(),
      );
      await native.install(downloaded);
      expect(steps, ['flush', 'launch', 'close']);
      steps.clear();
      await file.writeAsBytes([0x4d, 0x5a]);
      await expectLater(native.install(downloaded), throwsStateError);
      expect(steps, isEmpty);
    },
  );

  test('download deadline cancels stream and preserves partial data', () async {
    service.dispose();
    final stream = StreamController<List<int>>();
    var opened = false;
    service = WindowsWebDavUpdateService(
      settingsProvider: () => settings,
      installedVersion: () async => ('2.1.0', 23),
      downloadDirectory: temporary,
      installer: installer,
      isWindows: true,
      downloadTimeout: const Duration(milliseconds: 40),
      clientFactory: () => StreamingClient(
        manifest: manifest,
        stream: stream,
        onOpen: () {
          opened = true;
          stream.add(bytes.take(2).toList());
        },
      ),
    );
    final info = await service.check();
    await expectLater(service.install(info), throwsStateError);
    expect(opened, true);
    expect(installer.artifacts, isEmpty);
    final retained = temporary.listSync().whereType<File>().single;
    expect(retained.path, endsWith('.part'));
    expect(await retained.readAsBytes(), bytes.take(2).toList());
  });

  test(
    'dispose during download cancels it and never launches installer',
    () async {
      service.dispose();
      final stream = StreamController<List<int>>();
      final opened = Completer<void>();
      service = WindowsWebDavUpdateService(
        settingsProvider: () => settings,
        installedVersion: () async => ('2.1.0', 23),
        downloadDirectory: temporary,
        installer: installer,
        isWindows: true,
        clientFactory: () => StreamingClient(
          manifest: manifest,
          stream: stream,
          onOpen: opened.complete,
        ),
      );
      final info = await service.check();
      final download = service.install(info);
      final failed = expectLater(download, throwsStateError);
      await opened.future;
      service.dispose();
      await failed;
      expect(installer.artifacts, isEmpty);
      expect(temporary.listSync(), isEmpty);
    },
  );

  test(
    'launch failure keeps app open, development run does not overwrite its folder',
    () async {
      final file = File('${temporary.path}/verified.exe');
      await file.writeAsBytes(bytes);
      var closed = false;
      final native = WindowsUpdateInstaller(
        executablePath: '${temporary.path}/board_game_agent.exe',
        beforeInstall: () async {},
        launch: (_, args) async {
          expect(args.any((arg) => arg.startsWith('/DIR=')), false);
          throw const ProcessException('installer', [], 'could not launch');
        },
        onInstallerLaunched: () async => closed = true,
      );
      await expectLater(
        native.install(
          DownloadedUpdateArtifact(
            artifact: UpdateArtifact.fromJson(getArtifact()),
            filePath: file.path,
            size: bytes.length,
            sha256: sha256.convert(bytes).toString(),
          ),
        ),
        throwsA(isA<ProcessException>()),
      );
      expect(closed, false);
    },
  );

  testWidgets(
    'about page offers actual Windows update and completes download action',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppAboutPage(
            config: const AppAboutConfig(
              appName: 'Test',
              subtitle: '',
              appIcon: Icon(Icons.casino),
              fallbackVersion: '2.1.0',
              fallbackBuild: '23',
            ),
            updateService: service,
          ),
        ),
      );
      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();
      expect(find.text('下载并安装'), findsOneWidget);
      await tester.ensureVisible(find.text('下载并安装'));
      await tester.runAsync(() async {
        await tester.tap(find.text('下载并安装'));
        for (var i = 0; i < 100 && installer.artifacts.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(installer.artifacts.length, 1);
    },
  );
}

class RecordingInstaller implements UpdateInstaller {
  final artifacts = <DownloadedUpdateArtifact>[];
  bool fail = false;
  @override
  Future<UpdateInstallResult> install(DownloadedUpdateArtifact artifact) async {
    if (fail) throw StateError('launch failed');
    artifacts.add(artifact);
    return const UpdateInstallResult(
      status: UpdateInstallStatus.launched,
      message: 'started',
    );
  }
}

class StreamingClient extends http.BaseClient {
  StreamingClient({
    required this.manifest,
    required this.stream,
    required this.onOpen,
  });
  final Map<String, Object?> manifest;
  final StreamController<List<int>> stream;
  final void Function() onOpen;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path.endsWith('manifest.json')) {
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(manifest))),
        200,
      );
    }
    onOpen();
    return http.StreamedResponse(stream.stream, 200);
  }

  @override
  void close() {
    if (!stream.isClosed) {
      stream.addError(http.ClientException('client closed'));
      unawaited(stream.close());
    }
  }
}
