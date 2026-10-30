part of '../desktop_workspace_test.dart';

Future<void> _warmSpatialPictures(WidgetTester tester, AppController c) async {
  await tester.runAsync(() async {
    final paths = c.games
        .expand((g) => [g.coverAssetPath, g.bannerAssetPath])
        .toSet();
    for (final path in paths) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final stream = FileImage(file.absolute).resolve(ImageConfiguration.empty);
      final ready = Completer<void>();
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          info.dispose();
          if (!ready.isCompleted) ready.complete();
        },
        onError: (Object error, StackTrace? stack) {
          if (!ready.isCompleted) ready.completeError(error, stack);
        },
      );
      stream.addListener(listener);
      try {
        await ready.future.timeout(const Duration(seconds: 8));
      } finally {
        stream.removeListener(listener);
      }
    }
  });
}

class _LocalSpatialAssets extends _NoNetworkAssetService {
  @override
  Future<CachedAsset?> ensureCached({
    required List<AssetSourceConfig> sources,
    required String remotePath,
    bool forceRefresh = false,
    bool allowCachedFallback = true,
  }) async {
    final file = File(remotePath);
    if (!file.existsSync()) return null;
    return CachedAsset(
      remotePath: remotePath,
      localPath: file.absolute.path,
      exists: true,
      fromRemote: false,
    );
  }
}
