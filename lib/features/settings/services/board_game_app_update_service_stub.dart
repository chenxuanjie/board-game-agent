import 'package:app_about/app_about.dart';
import 'package:webdav_settings/webdav_settings.dart';

AppUpdateTarget? get boardGameUpdateTarget => null;
AppUpdateService createBoardGameUpdateService({
  required WebDavSettings Function() settingsProvider,
  required List<WebDavSettings> Function() settingsCandidates,
  required Future<void> Function() beforeInstall,
  required Future<void> Function() onWindowsInstallerLaunched,
}) => createWebDavAndroidUpdateService(
  settingsProvider: settingsProvider,
  config: const WebDavAndroidUpdateConfig(
    appId: 'board_game_agent',
    manifestPath: '',
    fallbackVersion: '',
    fallbackBuild: 0,
  ),
);
