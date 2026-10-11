import 'dart:io';
import 'package:app_about/app_about.dart';
// ignore: implementation_imports
import 'package:app_ai_client/src/default_http_client.dart';
import 'package:http/http.dart' as http;
import 'package:remote_update/remote_update.dart';
import 'package:webdav_settings/webdav_settings.dart';
import '../../library/services/board_game_remote_layout.dart';

AppUpdateService createWindowsUpdateService({
  required WebDavSettings Function() settingsProvider,
  required Future<void> Function() beforeInstall,
  required Future<void> Function() onInstallerLaunched,
  List<WebDavSettings> Function()? settingsCandidates,
}) {
  late final WindowsWebDavUpdateService service;
  service = WindowsWebDavUpdateService(
    settingsProvider: settingsProvider,
    settingsCandidates: settingsCandidates,
    beforeInstall: beforeInstall,
    installer: WindowsUpdateInstaller(
      beforeInstall: () async {},
      beforeLaunch: () async => service.assertInstallationAllowed(),
      onInstallerLaunched: onInstallerLaunched,
    ),
  );
  return service;
}

/// Compatibility entry point; Windows no longer owns a second update lifecycle.
class WindowsWebDavUpdateService extends WebDavAppUpdateService {
  WindowsWebDavUpdateService({
    required super.settingsProvider,
    required super.installer,
    super.settingsCandidates,
    http.Client Function()? clientFactory,
    super.installedVersion,
    super.downloadDirectory,
    super.beforeInstall,
    bool? isWindows,
    Duration requestTimeout = const Duration(seconds: 30),
    Duration downloadTimeout = const Duration(minutes: 10),
  }) : super(
         clientFactory: clientFactory ?? createDefaultAiHttpClient,
         isSupported: isWindows ?? Platform.isWindows,
         config: WebDavAppUpdateConfig(
           appId: 'board_game_agent',
           target: AppUpdateTarget.windows,
           architecture: 'x64',
           manifestPath: BoardGameRemoteLayout.windowsUpdateManifestPath,
           directoryName: 'board_game_agent_windows_updates',
           requestTimeout: requestTimeout,
           downloadTimeout: downloadTimeout,
           notConfiguredMessage: '请先登录账号并配置服务器与资料',
         ),
       );
}
