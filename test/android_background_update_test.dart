import 'dart:async';
import 'package:app_about/app_about.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:board_game_agent/core/platform/background_transfer_notifications.dart';
import 'package:board_game_agent/features/settings/services/android_background_update_service.dart';

const available = AppUpdateInfo(
  status: AppUpdateStatus.available,
  artifactSize: 100,
);

class _Notices extends NoBackgroundTransferNotifications {
  final events = <String>[];
  bool refuse = false;
  Completer<void>? foreground;
  @override
  Future<void> start({
    required String id,
    required String title,
    required String message,
    int total = 0,
  }) async {
    if (refuse) throw BackgroundTransferFailure('请允许通知');
    events.add('start:$id:$total');
  }

  @override
  void progress({
    required String id,
    required String message,
    required int completed,
    required int total,
  }) {
    events.add('progress:$id:$completed/$total');
  }

  @override
  Future<void> finish({
    required String id,
    required String message,
    bool failed = false,
  }) async {
    events.add('finish:$id:$failed');
  }

  @override
  Future<void> waitForForeground({Future<void>? cancellation}) async {
    if (foreground == null) return;
    await Future.any<void>([
      foreground!.future,
      if (cancellation != null)
        cancellation.then((_) => throw BackgroundTransferFailure('取消安装')),
    ]);
  }
}

class _Updater implements AppUpdateService, CancellableAppUpdateService {
  Future<void> Function()? prepare;
  bool rejectChecksum = false;
  int transfers = 0, installs = 0;
  @override
  Future<AppUpdateInfo> check() async => available;
  @override
  bool get canCancel => true;
  @override
  void cancel() {}
  @override
  void dispose() {}
  @override
  Future<void> install(
    AppUpdateInfo info, {
    void Function(AppUpdateProgress)? onProgress,
  }) async {
    transfers++;
    onProgress?.call(
      const AppUpdateProgress(receivedBytes: 30, totalBytes: 100),
    );
    onProgress?.call(
      const AppUpdateProgress(
        receivedBytes: 100,
        totalBytes: 100,
        phase: AppUpdatePhase.verifying,
      ),
    );
    if (rejectChecksum) throw AppUpdateFailure('校验失败');
    await prepare?.call();
    installs++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'APK download keeps real progress and cannot install until foreground',
    () async {
      final notices = _Notices()..foreground = Completer<void>();
      final inner = _Updater();
      final service = AndroidBackgroundUpdateService(
        inner: inner,
        notifications: notices,
      );
      inner.prepare = () => service.beforeInstall(() async {});
      final progress = <AppUpdateProgress>[];
      final work = service.install(available, onProgress: progress.add);
      await Future<void>.delayed(Duration.zero);
      expect(inner.transfers, 1);
      expect(inner.installs, 0);
      expect(notices.events, contains('progress:apk:30/100'));
      expect(progress.first.receivedBytes, 30);
      expect(notices.events.last, 'finish:apk:false');
      notices.foreground!.complete();
      await work;
      expect(inner.installs, 1);
      service.dispose();
    },
  );
  test(
    'invalid APK releases foreground work and never launches installer',
    () async {
      final notices = _Notices(), inner = _Updater()..rejectChecksum = true;
      final service = AndroidBackgroundUpdateService(
        inner: inner,
        notifications: notices,
      );
      await expectLater(
        service.install(available),
        throwsA(isA<AppUpdateFailure>()),
      );
      expect(inner.installs, 0);
      expect(notices.events.last, 'finish:apk:true');
      service.dispose();
    },
  );
  test(
    'notification refusal prevents starting an unprotected download',
    () async {
      final notices = _Notices()..refuse = true;
      final inner = _Updater();
      final service = AndroidBackgroundUpdateService(
        inner: inner,
        notifications: notices,
      );
      await expectLater(
        service.install(available),
        throwsA(isA<AppUpdateFailure>()),
      );
      expect(inner.transfers, 0);
      service.dispose();
    },
  );
  test(
    'cancel while waiting preserves package and cannot open installer later',
    () async {
      final notices = _Notices()..foreground = Completer<void>();
      final inner = _Updater();
      final service = AndroidBackgroundUpdateService(
        inner: inner,
        notifications: notices,
      );
      inner.prepare = () => service.beforeInstall(() async {});
      final work = service.install(available);
      final failure = expectLater(work, throwsA(isA<AppUpdateFailure>()));
      await Future<void>.delayed(Duration.zero);
      service.cancel();
      await failure;
      notices.foreground!.complete();
      expect(inner.installs, 0);
      service.dispose();
    },
  );
  test(
    'cancel while preparing blocks installer even if app stays foreground',
    () async {
      final notices = _Notices();
      final inner = _Updater();
      final service = AndroidBackgroundUpdateService(
        inner: inner,
        notifications: notices,
      );
      final preparation = Completer<void>();
      inner.prepare = () => service.beforeInstall(() => preparation.future);
      final work = service.install(available);
      final failed = expectLater(work, throwsA(isA<AppUpdateFailure>()));
      await Future<void>.delayed(Duration.zero);
      service.cancel();
      preparation.complete();
      await failed;
      expect(inner.installs, 0);
      service.dispose();
    },
  );
  testWidgets('Android installer waiter follows actual lifecycle', (
    tester,
  ) async {
    final notices = AndroidBackgroundTransferNotifications();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    var installed = false;
    final waiting = notices.waitForForeground().then((_) => installed = true);
    await tester.pump();
    expect(installed, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await waiting;
    expect(installed, isTrue);
  });
  test(
    'native start failure is surfaced and attempts to release any late start',
    () async {
      const channel = MethodChannel('test/download_progress');
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'start') {
              throw PlatformException(code: 'permission_denied');
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final notices = AndroidBackgroundTransferNotifications(channel: channel);
      await expectLater(
        notices.start(id: 'apk', title: '更新', message: '下载'),
        throwsA(isA<BackgroundTransferFailure>()),
      );
      expect(calls, ['start', 'finish']);
    },
  );
}
