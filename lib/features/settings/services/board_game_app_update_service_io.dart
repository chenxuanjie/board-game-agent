import 'dart:io';
import 'package:app_about/app_about.dart';
// ignore: implementation_imports
import 'package:app_ai_client/src/default_http_client.dart';
import 'package:webdav_settings/webdav_settings.dart';
import '../../library/services/board_game_remote_layout.dart';
import 'windows_update_service_io.dart';
import '../../../core/platform/background_transfer_notifications.dart';
import 'android_background_update_service.dart';

AppUpdateTarget? get boardGameUpdateTarget => Platform.isWindows
    ? AppUpdateTarget.windows
    : Platform.isAndroid
    ? AppUpdateTarget.android
    : null;

AppUpdateService createBoardGameUpdateService({
  required WebDavSettings Function() settingsProvider,
  required List<WebDavSettings> Function() settingsCandidates,
  required Future<void> Function() beforeInstall,
  required Future<void> Function() onWindowsInstallerLaunched,
}) {
  if (Platform.isWindows) {
    return createWindowsUpdateService(
      settingsProvider: settingsProvider,
      settingsCandidates: settingsCandidates,
      beforeInstall: beforeInstall,
      onInstallerLaunched: onWindowsInstallerLaunched,
    );
  }
  final notifications = createBackgroundTransferNotifications();
  late AndroidBackgroundUpdateService service;
  final inner = createWebDavAndroidUpdateService(
    settingsProvider: settingsProvider,
    settingsCandidates: settingsCandidates,
    beforeInstall: () => service.beforeInstall(beforeInstall),
    clientFactory: createDefaultAiHttpClient,
    config: const WebDavAndroidUpdateConfig(
      appId: 'board_game_agent',
      manifestPath: BoardGameRemoteLayout.updateManifestPath,
      fallbackVersion: '',
      fallbackBuild: 0,
      directoryName: 'board_game_agent_updates',
    ),
  );
  service = AndroidBackgroundUpdateService(
    inner: inner,
    notifications: notifications,
  );
  return service;
}
