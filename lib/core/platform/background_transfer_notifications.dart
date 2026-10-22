import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class BackgroundTransferFailure extends StateError {
  BackgroundTransferFailure(super.message);
}

/// Keeps the existing transfer/verification owner; this only manages Android
/// execution priority and notifications. It does not claim process-death jobs.
abstract class BackgroundTransferNotifications {
  const BackgroundTransferNotifications();
  Future<void> start({
    required String id,
    required String title,
    required String message,
    int total = 0,
  });
  void progress({
    required String id,
    required String message,
    required int completed,
    required int total,
  });
  Future<void> finish({
    required String id,
    required String message,
    bool failed = false,
  });
  Future<void> waitForForeground({Future<void>? cancellation});
}

class NoBackgroundTransferNotifications
    extends BackgroundTransferNotifications {
  const NoBackgroundTransferNotifications();
  @override
  Future<void> start({
    required String id,
    required String title,
    required String message,
    int total = 0,
  }) async {}
  @override
  void progress({
    required String id,
    required String message,
    required int completed,
    required int total,
  }) {}
  @override
  Future<void> finish({
    required String id,
    required String message,
    bool failed = false,
  }) async {}
  @override
  Future<void> waitForForeground({Future<void>? cancellation}) async {}
}

BackgroundTransferNotifications createBackgroundTransferNotifications() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android
    ? AndroidBackgroundTransferNotifications()
    : const NoBackgroundTransferNotifications();

class AndroidBackgroundTransferNotifications
    extends BackgroundTransferNotifications {
  AndroidBackgroundTransferNotifications({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('board_game_agent/download_progress');
  final MethodChannel _channel;
  final _lastProgress = <String, DateTime>{};
  @override
  Future<void> start({
    required String id,
    required String title,
    required String message,
    int total = 0,
  }) async {
    try {
      await _channel
          .invokeMethod<void>('start', {
            'id': id,
            'title': title,
            'message': message,
            'total': total,
          })
          .timeout(const Duration(minutes: 2));
      _lastProgress.remove(id);
    } catch (_) {
      await _invoke('finish', {
        'id': id,
        'message': '下载未启动，请重试',
        'failed': true,
      });
      throw BackgroundTransferFailure('无法启动后台下载，请允许通知并重试');
    }
  }

  @override
  void progress({
    required String id,
    required String message,
    required int completed,
    required int total,
  }) {
    final now = DateTime.now(), previous = _lastProgress[id];
    if (previous != null &&
        now.difference(previous).inMilliseconds < 500 &&
        completed < total) {
      return;
    }
    _lastProgress[id] = now;
    unawaited(
      _invoke('progress', {
        'id': id,
        'message': message,
        'completed': completed,
        'total': total,
      }),
    );
  }

  Future<void> _invoke(String method, Map<String, Object> args) async {
    try {
      await _channel
          .invokeMethod<void>(method, args)
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Notification transport must never convert a committed download into
      // a failed download. The initial foreground-service start is mandatory.
    }
  }

  @override
  Future<void> finish({
    required String id,
    required String message,
    bool failed = false,
  }) async {
    _lastProgress.remove(id);
    await _invoke('finish', {'id': id, 'message': message, 'failed': failed});
  }

  @override
  Future<void> waitForForeground({Future<void>? cancellation}) async {
    final binding = WidgetsBinding.instance;
    if (binding.lifecycleState == null ||
        binding.lifecycleState == AppLifecycleState.resumed) {
      return;
    }
    final waiter = _ForegroundWaiter();
    binding.addObserver(waiter);
    try {
      await Future.any<void>([
        waiter.ready.future,
        if (cancellation != null)
          cancellation.then(
            (_) => throw BackgroundTransferFailure('安装已取消，安装包已保留'),
          ),
      ]).timeout(
        const Duration(minutes: 15),
        onTimeout: () => throw BackgroundTransferFailure('安装包已保存，请返回应用重新安装'),
      );
    } finally {
      binding.removeObserver(waiter);
    }
  }
}

class _ForegroundWaiter extends WidgetsBindingObserver {
  final ready = Completer<void>();
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !ready.isCompleted) {
      ready.complete();
    }
  }
}
