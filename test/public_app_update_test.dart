import 'dart:convert';
import 'dart:io';
import 'package:app_about/app_about.dart';
import 'package:app_client/updates.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remote_update/remote_update.dart';

class _Installer implements UpdateInstaller {
  bool launched = false;
  @override
  Future<UpdateInstallResult> install(DownloadedUpdateArtifact artifact) async {
    launched = true;
    return const UpdateInstallResult(
      status: UpdateInstallStatus.launched,
      message: 'test installer',
    );
  }
}

void main() {
  final bytes = [80, 75, 3, 4, 1, 2, 3];
  final digest = sha256.convert(bytes).toString();
  late Directory directory;
  late NativeAppUpdateService service;
  late _Installer installer;
  var origin = Uri.parse('https://api.test');
  var corrupt = false;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('board_guest_update_');
    origin = Uri.parse('https://api.test');
    corrupt = false;
    installer = _Installer();
    service = NativeAppUpdateService(
      config: const NativeAppUpdateConfig(
        appId: 'board_game_agent',
        target: AppUpdateTarget.android,
        architecture: 'arm64',
      ),
      isSupported: true,
      installedVersion: () async => ('1.0.0', 1),
      installer: installer,
      failureMessage: (error, _) => 'test: ${error.runtimeType}: $error',
      downloadDirectory: directory,
      connections: () {
        final captured = origin;
        return [
          NativeUpdateEndpoint(
            key: captured.origin,
            source: (client) => PublicReleaseSource(
              appId: 'board_game_agent',
              origin: captured,
              client: client,
              active: () => origin == captured,
            ),
          ),
        ];
      },
      clientFactory: () => MockClient((request) async {
        expect(
          request.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('authorization')),
        );
        if (request.url.path.endsWith('/manifest')) {
          return http.Response(
            jsonEncode({
              'schemaVersion': 1,
              'appId': 'board_game_agent',
              'channel': 'stable',
              'versionName': '2.0.0',
              'buildNumber': 2,
              'minimumSupportedBuild': 0,
              'forceUpdate': false,
              'releaseNotes': {
                'zh-CN': ['公开升级'],
              },
              'artifacts': [
                {
                  'platform': 'android',
                  'architecture': 'arm64',
                  'path': '$digest.apk',
                  'size': bytes.length,
                  'sha256': digest,
                  'mimeType': 'application/vnd.android.package-archive',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response.bytes(
          corrupt ? List.filled(bytes.length, 0) : bytes,
          200,
        );
      }),
    );
  });
  tearDown(() async {
    service.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'a guest checks, verifies and reaches installer without account setup',
    () async {
      final result = await service.check();
      expect(result.status, AppUpdateStatus.available, reason: result.message);
      await service.install(result);
      expect(installer.launched, isTrue);
    },
  );
  test('corrupt bytes cannot reach installer', () async {
    final result = await service.check();
    expect(result.status, AppUpdateStatus.available, reason: result.message);
    corrupt = true;
    await expectLater(
      service.install(result),
      throwsA(isA<AppUpdateFailure>()),
    );
    expect(installer.launched, isFalse);
  });
  test('changing service origin invalidates the checked installer', () async {
    final result = await service.check();
    expect(result.status, AppUpdateStatus.available, reason: result.message);
    origin = Uri.parse('https://other.test');
    await expectLater(
      service.install(result),
      throwsA(isA<AppUpdateFailure>()),
    );
    expect(installer.launched, isFalse);
  });
}
