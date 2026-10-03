import 'package:app_about/app_about.dart';
import 'package:webdav_settings/webdav_settings.dart';

AppUpdateService createWindowsUpdateService({
  required WebDavSettings Function() settingsProvider,
  required Future<void> Function() beforeInstall,
  required Future<void> Function() onInstallerLaunched,
}) => _UnsupportedWindowsUpdateService();

class _UnsupportedWindowsUpdateService implements AppUpdateService {
  @override
  Future<AppUpdateInfo> check() async => const AppUpdateInfo(
    status: AppUpdateStatus.unsupported,
    message: '浏览器不支持 Windows 应用内安装',
  );

  @override
  Future<void> install(
    AppUpdateInfo info, {
    void Function(AppUpdateProgress)? onProgress,
  }) async => throw UnsupportedError('浏览器不支持 Windows 应用内安装');

  @override
  void dispose() {}
}
