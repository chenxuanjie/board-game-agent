import 'dart:async';
import 'package:app_about/app_about.dart';
import 'package:board_game_agent/features/community/services/public_publication.dart';
import 'package:board_game_agent/features/settings/services/public_release_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final origin = Uri.parse('https://api.test');
  const notice = PublicPublication(
    id: 'release',
    topic: 'release',
    revision: 50,
    channel: 'stable',
    platform: 'android',
    architecture: 'arm64',
  );
  const available = AppUpdateInfo(
    status: AppUpdateStatus.available,
    latestBuild: 50,
    latestVersion: '5.0.0',
  );
  late Uri selected;
  late bool enabled;
  late int checks, notices, disposed;
  late Future<AppUpdateInfo> Function() check;
  late PublicReleaseMonitor monitor;
  setUp(() {
    selected = origin;
    enabled = true;
    checks = notices = disposed = 0;
    check = () async => available;
    monitor = PublicReleaseMonitor(
      origin: () => selected,
      enabled: () => enabled,
      platform: 'android',
      service: () => FakeUpdater(() {
        checks++;
        return check();
      }, () => disposed++),
      onAvailable: (_) => notices++,
    );
  });
  tearDown(() => monitor.dispose());
  test(
    'public signal checks current platform once without installing',
    () async {
      await monitor.refresh(origin, [notice]);
      await monitor.refresh(origin, [notice]);
      expect((checks, notices, disposed), (1, 1, 1));
      await monitor.refresh(origin, [
        const PublicPublication(id: 'catalog', topic: 'catalog', revision: 2),
      ]);
      await monitor.refresh(origin, [
        const PublicPublication(
          id: 'windows',
          topic: 'release',
          revision: 100,
          platform: 'windows',
          channel: 'stable',
          architecture: 'x64',
        ),
      ]);
      expect(checks, 1);
    },
  );
  test('failed checks remain unacknowledged for sync retry', () async {
    check = () async => const AppUpdateInfo(status: AppUpdateStatus.failed);
    await expectLater(monitor.refresh(origin, [notice]), throwsStateError);
    check = () async => available;
    await monitor.refresh(origin, [notice]);
    expect((checks, notices, disposed), (2, 1, 2));
  });
  test(
    'a newly activated notification workspace can discover the same version',
    () async {
      await monitor.refresh(origin, [notice]);
      monitor.resetNotificationContext();
      await monitor.refresh(origin, [notice]);
      expect((checks, notices, disposed), (2, 2, 2));
    },
  );
  test('changed origin and disposed shell reject late results', () async {
    final gate = Completer<AppUpdateInfo>();
    check = () => gate.future;
    final pending = monitor.refresh(origin, [notice]);
    selected = Uri.parse('https://other.test');
    gate.complete(available);
    await pending;
    expect(notices, 0);
    selected = origin;
    monitor.dispose();
    await monitor.refresh(origin, [notice]);
    expect(checks, 1);
  });
  test(
    'workspace changes reject pending checks without consuming the new context',
    () async {
      final gate = Completer<AppUpdateInfo>();
      check = () => gate.future;
      final pending = monitor.refresh(origin, [notice]);
      monitor.resetNotificationContext();
      gate.complete(available);
      await pending;
      expect((checks, notices, disposed), (1, 0, 1));
      check = () async => available;
      await monitor.refresh(origin, [notice]);
      expect((checks, notices, disposed), (2, 1, 2));
    },
  );
  test('disabled checks do not consume a public release watermark', () async {
    enabled = false;
    await monitor.refresh(origin, [notice]);
    expect(checks, 0);
    enabled = true;
    await monitor.refresh(origin, [notice]);
    expect(notices, 1);
  });
}

class FakeUpdater implements AppUpdateService {
  FakeUpdater(this.checkResult, this.onDispose);
  final Future<AppUpdateInfo> Function() checkResult;
  final void Function() onDispose;
  @override
  Future<AppUpdateInfo> check() => checkResult();
  @override
  void dispose() => onDispose();
  @override
  Future<void> install(
    AppUpdateInfo info, {
    void Function(AppUpdateProgress)? onProgress,
  }) => throw StateError('Publication notifications must not install');
}
