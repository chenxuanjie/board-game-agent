import 'package:app_about/app_about.dart';
import '../../community/services/public_publication.dart';

/// Checks committed, relevant release signals; never downloads or installs.
final class PublicReleaseMonitor {
  PublicReleaseMonitor({
    required this.origin,
    required this.enabled,
    required this.platform,
    required this.service,
    required this.onAvailable,
  });

  final Uri Function() origin;
  final bool Function() enabled;
  final String? platform;
  final AppUpdateService Function() service;
  final void Function(AppUpdateInfo) onAvailable;
  final _seen = <String, int>{};
  bool _disposed = false;
  int _contextGeneration = 0;

  /// The notification center changes with the local workspace. A new workspace
  /// must be able to discover a version already checked for the previous one.
  void resetNotificationContext() {
    _contextGeneration++;
    _seen.clear();
  }

  Future<void> refresh(Uri source, List<PublicPublication> publications) async {
    if (_disposed ||
        !enabled() ||
        source.origin != origin().origin ||
        platform == null) {
      return;
    }
    final relevant = publications
        .where(
          (item) =>
              item.topic == 'release' &&
              item.channel == 'stable' &&
              item.platform == platform &&
              (_seen['${source.origin}|${item.id}'] ?? -1) < item.revision,
        )
        .toList();
    if (relevant.isEmpty) return;
    final generation = _contextGeneration;
    final updater = service();
    try {
      final info = await updater.check();
      if (_disposed ||
          generation != _contextGeneration ||
          source.origin != origin().origin ||
          !enabled()) {
        return;
      }
      if (info.status == AppUpdateStatus.failed) {
        throw StateError('Public release discovery incomplete');
      }
      if (info.isAvailable &&
          info.latestBuild != null &&
          info.latestVersion != null) {
        onAvailable(info);
      }
      for (final item in relevant) {
        _seen['${source.origin}|${item.id}'] = item.revision;
      }
    } finally {
      updater.dispose();
    }
  }

  void dispose() => _disposed = true;
}
