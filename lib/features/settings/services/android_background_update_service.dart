import 'dart:async';
import 'package:app_about/app_about.dart';
import '../../../core/platform/background_transfer_notifications.dart';

/// Decorates the shared updater, preserving its size/SHA-256/install checks.
class AndroidBackgroundUpdateService
    implements AppUpdateService, CancellableAppUpdateService {
  AndroidBackgroundUpdateService({
    required this.inner,
    required this.notifications,
  });
  final AppUpdateService inner;
  final BackgroundTransferNotifications notifications;
  Completer<void>? _cancellation;
  bool _waitingForForeground = false, _disposed = false;
  bool _busy = false;
  @override
  Future<AppUpdateInfo> check() => inner.check();
  @override
  bool get canCancel =>
      _waitingForForeground ||
      (inner is CancellableAppUpdateService &&
          (inner as CancellableAppUpdateService).canCancel);
  @override
  void cancel() {
    if (!canCancel) return;
    if (!(_cancellation?.isCompleted ?? true)) _cancellation!.complete();
    if (inner is CancellableAppUpdateService) {
      (inner as CancellableAppUpdateService).cancel();
    }
  }

  Future<void> beforeInstall(Future<void> Function() prepare) async {
    await notifications.finish(id: 'apk', message: '安装包已校验，返回应用安装');
    _waitingForForeground = true;
    try {
      await notifications.waitForForeground(
        cancellation: _cancellation?.future,
      );
      if (_disposed || (_cancellation?.isCompleted ?? false)) {
        throw AppUpdateFailure('安装已取消，安装包已保留');
      }
      await prepare();
      await notifications.waitForForeground(
        cancellation: _cancellation?.future,
      );
      if (_disposed || (_cancellation?.isCompleted ?? false)) {
        throw AppUpdateFailure('安装已取消，安装包已保留');
      }
    } finally {
      _waitingForForeground = false;
    }
  }

  @override
  Future<void> install(
    AppUpdateInfo info, {
    void Function(AppUpdateProgress)? onProgress,
  }) async {
    if (_disposed || _busy) throw AppUpdateFailure('更新操作正在进行或已关闭');
    _busy = true;
    _cancellation = Completer<void>();
    var started = false;
    try {
      await notifications.start(
        id: 'apk',
        title: '应用更新',
        message: '正在下载安装包',
        total: info.artifactSize ?? 0,
      );
      started = true;
      if (_disposed) throw AppUpdateFailure('更新已取消');
      await inner.install(
        info,
        onProgress: (progress) {
          final message = switch (progress.phase) {
            AppUpdatePhase.downloading =>
              progress.totalBytes <= 0
                  ? '正在下载安装包'
                  : '正在下载安装包 ${(progress.receivedBytes / 1048576).toStringAsFixed(1)}/${(progress.totalBytes / 1048576).toStringAsFixed(1)} MB',
            AppUpdatePhase.verifying => '正在校验安装包',
            AppUpdatePhase.preparing => '安装包已下载，正在准备',
            AppUpdatePhase.installing => '正在打开系统安装界面',
          };
          notifications.progress(
            id: 'apk',
            message: message,
            completed: progress.receivedBytes,
            total: progress.totalBytes,
          );
          onProgress?.call(progress);
        },
      );
    } catch (error) {
      if (started) {
        await notifications.finish(
          id: 'apk',
          message: '更新未完成，请返回应用重试',
          failed: true,
        );
      }
      if (error is BackgroundTransferFailure) {
        throw AppUpdateFailure(error.message.toString());
      }
      rethrow;
    } finally {
      _busy = false;
      _cancellation = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (!(_cancellation?.isCompleted ?? true)) _cancellation!.complete();
    inner.dispose();
  }
}
