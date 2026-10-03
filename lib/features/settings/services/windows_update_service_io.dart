import 'dart:async';
import 'dart:io';

import 'package:app_about/app_about.dart';
// Reuse the existing native transport's environment/system proxy policy.
// ignore: implementation_imports
import 'package:app_ai_client/src/default_http_client.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:remote_update/remote_update.dart';
import 'package:remote_update_webdav/remote_update_webdav.dart';
import 'package:webdav_settings/webdav_settings.dart';
import 'package:webdav_storage/webdav_storage.dart';

import '../../library/services/board_game_remote_layout.dart';
import 'windows_update_installer.dart';

AppUpdateService createWindowsUpdateService({
  required WebDavSettings Function() settingsProvider,
  required Future<void> Function() beforeInstall,
  required Future<void> Function() onInstallerLaunched,
}) => WindowsWebDavUpdateService(
  settingsProvider: settingsProvider,
  installer: WindowsUpdateInstaller(
    beforeInstall: beforeInstall,
    onInstallerLaunched: onInstallerLaunched,
  ),
);

class WindowsWebDavUpdateService implements AppUpdateService {
  WindowsWebDavUpdateService({
    required this.settingsProvider,
    required this.installer,
    http.Client Function()? clientFactory,
    Future<(String, int)> Function()? installedVersion,
    this.downloadDirectory,
    bool? isWindows,
    this.requestTimeout = const Duration(seconds: 30),
    this.downloadTimeout = const Duration(minutes: 10),
  }) : _clientFactory = clientFactory ?? createDefaultAiHttpClient,
       _installedVersion = installedVersion ?? _readInstalledVersion,
       _isWindows = isWindows ?? Platform.isWindows;

  final WebDavSettings Function() settingsProvider;
  final UpdateInstaller installer;
  final http.Client Function() _clientFactory;
  final Future<(String, int)> Function() _installedVersion;
  final Directory? downloadDirectory;
  final bool _isWindows;
  final Duration requestTimeout;
  final Duration downloadTimeout;
  http.Client? _client;
  RemoteUpdater? _updater;
  UpdateCandidate? _candidate;
  WebDavSettings? _checkedSettings;
  UpdateCancellationToken? _cancellation;
  bool _busy = false;
  bool _disposed = false;

  static Future<(String, int)> _readInstalledVersion() async {
    // Do not guess an old fallback build when Windows version metadata fails.
    final info = await PackageInfo.fromPlatform();
    final build = int.tryParse(info.buildNumber);
    if (build == null || build <= 0) throw StateError('无法读取当前应用版本');
    return (info.version, build);
  }

  @override
  Future<AppUpdateInfo> check() async {
    if (_disposed) throw StateError('更新检查已关闭');
    if (_busy) {
      return const AppUpdateInfo(
        status: AppUpdateStatus.failed,
        message: '更新操作正在进行，请稍候',
      );
    }
    if (!_isWindows) {
      return const AppUpdateInfo(status: AppUpdateStatus.unsupported);
    }
    _busy = true;
    try {
      await _clear();
      final settings = settingsProvider();
      final uri = Uri.tryParse(settings.baseUrl.trim());
      if (settings.mode != ExternalStorageMode.webDav || !settings.isComplete) {
        return const AppUpdateInfo(
          status: AppUpdateStatus.notConfigured,
          message: '请先在设置中配置 WebDAV',
        );
      }
      if (uri == null ||
          !uri.hasAuthority ||
          (uri.scheme != 'https' &&
              !(uri.scheme == 'http' &&
                  ['localhost', '127.0.0.1', '::1'].contains(uri.host))) ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          settings.username.isEmpty != settings.password.isEmpty) {
        return const AppUpdateInfo(
          status: AppUpdateStatus.notConfigured,
          message: 'Windows 更新需要有效的 HTTPS WebDAV 地址和完整账号',
        );
      }
      final version = await _installedVersion();
      if (_disposed) throw StateError('更新检查已关闭');
      final client = _clientFactory();
      _client = client;
      final storage = WebDavStorageClient(
        config: WebDavConfig(
          baseUri: uri,
          username: settings.username.isEmpty ? null : settings.username,
          password: settings.password.isEmpty ? null : settings.password,
          timeout: requestTimeout,
        ),
        httpClient: client,
      );
      final source = WebDavUpdateSource(
        storage: storage,
        manifestPath: BoardGameRemoteLayout.windowsUpdateManifestPath,
      );
      final updater = downloadDirectory == null
          ? await RemoteUpdater.create(
              source: source,
              installer: installer,
              directoryName: 'board_game_agent_windows_updates',
            )
          : RemoteUpdater(
              source: source,
              installer: installer,
              downloadDirectory: downloadDirectory!,
            );
      if (_disposed) {
        await updater.close();
        throw StateError('更新检查已关闭');
      }
      _updater = updater;
      final candidate = await updater.checkForUpdate(
        request: const UpdateRequest(
          appId: 'board_game_agent',
          channel: 'stable',
          platform: 'windows',
          architecture: 'x64',
        ),
        installedVersion: InstalledAppVersion(
          appId: 'board_game_agent',
          channel: 'stable',
          versionName: version.$1,
          buildNumber: version.$2,
          platform: 'windows',
          architecture: 'x64',
        ),
      );
      if (_disposed) throw StateError('更新检查已关闭');
      _candidate = candidate;
      _checkedSettings = settings;
      if (candidate == null) {
        return const AppUpdateInfo(
          status: AppUpdateStatus.upToDate,
          message: '当前已是最新版本',
        );
      }
      if (candidate.artifact.architecture != 'x64' ||
          !candidate.artifact.path.toLowerCase().endsWith('.exe')) {
        throw const FormatException('Windows 清单未提供 x64 安装包');
      }
      return AppUpdateInfo(
        status: AppUpdateStatus.available,
        latestVersion: candidate.manifest.versionName,
        latestBuild: candidate.manifest.buildNumber,
        releaseNotes: candidate.manifest.releaseNotesFor('zh-CN'),
        required: candidate.required,
      );
    } catch (error) {
      await _clear();
      return AppUpdateInfo(
        status: AppUpdateStatus.failed,
        message: _failureMessage(error),
      );
    } finally {
      _busy = false;
    }
  }

  bool _settingsUnchanged() {
    final old = _checkedSettings;
    final next = settingsProvider();
    return old != null &&
        old.baseUrl == next.baseUrl &&
        old.username == next.username &&
        old.password == next.password &&
        old.mode == next.mode;
  }

  @override
  Future<void> install(
    AppUpdateInfo info, {
    void Function(AppUpdateProgress)? onProgress,
  }) async {
    final updater = _updater;
    final candidate = _candidate;
    if (_disposed ||
        _busy ||
        updater == null ||
        candidate == null ||
        !info.isAvailable ||
        info.latestBuild != candidate.manifest.buildNumber ||
        info.latestVersion != candidate.manifest.versionName) {
      throw StateError('请重新检查更新');
    }
    if (!_settingsUnchanged()) throw StateError('连接设置已改变，请重新检查更新');
    _busy = true;
    final cancellation = UpdateCancellationToken();
    _cancellation = cancellation;
    var timedOut = false;
    final deadline = Timer(downloadTimeout, () {
      timedOut = true;
      cancellation.cancel();
      _client?.close();
    });
    final subscription = updater.states.listen((state) {
      if (state case UpdateDownloading(
        :final receivedBytes,
        :final totalBytes,
      ) when !_disposed) {
        onProgress?.call(
          AppUpdateProgress(
            receivedBytes: receivedBytes,
            totalBytes: totalBytes,
          ),
        );
      }
    });
    try {
      final downloaded = await updater.download(
        candidate,
        cancellationToken: cancellation,
      );
      deadline.cancel();
      if (_disposed || !_settingsUnchanged()) {
        throw StateError('更新已取消或连接设置已改变，请重新检查');
      }
      cancellation.throwIfCancelled();
      await updater.install(downloaded);
      _candidate = null;
    } catch (error) {
      if (timedOut) {
        await _clear();
        throw StateError('下载超时，请重新检查更新后重试');
      }
      if (error is StateError) rethrow;
      throw StateError(_failureMessage(error));
    } finally {
      deadline.cancel();
      await subscription.cancel();
      _cancellation = null;
      _busy = false;
    }
  }

  String _failureMessage(Object error) {
    final cause = error is RemoteUpdateException ? error.cause : error;
    if (cause is WebDavException) {
      return switch (cause.statusCode) {
        401 || 403 => 'WebDAV 认证或访问权限失败，请检查连接设置',
        404 => '尚未发布 Windows 更新，或更新文件已移除',
        429 => '服务器繁忙，请稍后重试',
        _ => '无法连接更新服务器，请检查网络后重试',
      };
    }
    if (error is RemoteUpdateException &&
        [
          RemoteUpdateFailureCode.checksumMismatch,
          RemoteUpdateFailureCode.sizeMismatch,
        ].contains(error.code)) {
      return '安装包校验失败，请重新下载';
    }
    if (error is FormatException ||
        (error is RemoteUpdateException &&
            [
              RemoteUpdateFailureCode.invalidManifest,
              RemoteUpdateFailureCode.appMismatch,
              RemoteUpdateFailureCode.channelMismatch,
              RemoteUpdateFailureCode.targetUnsupported,
            ].contains(error.code))) {
      return '更新清单无效或与当前应用不匹配，请稍后重试';
    }
    return '更新操作失败，请检查网络或关闭安装程序后重试';
  }

  Future<void> _clear() async {
    _client?.close();
    _client = null;
    _candidate = null;
    _checkedSettings = null;
    final updater = _updater;
    _updater = null;
    await updater?.close();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancellation?.cancel();
    unawaited(_clear());
  }
}
