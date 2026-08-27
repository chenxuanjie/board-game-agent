import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/asset_source_config.dart';
import '../models/cached_asset.dart';
import '../models/game_catalog_manifest.dart';
import '../models/game_resource.dart';
import 'remote_asset_service.dart';

class GameManifestService {
  Future<List<GameManifest>> loadEnabledGames({
    required RemoteAssetService remoteAssetService,
    List<AssetSourceConfig> sources = const [],
    bool preferRemote = false,
  }) async {
    final GameCatalogManifest catalog = await loadMergedCatalogManifest(
      remoteAssetService: remoteAssetService,
    );

    final List<GameCatalogEntry> entries = List<GameCatalogEntry>.from(
      catalog.games,
    )..sort((a, b) => a.order.compareTo(b.order));

    final List<GameManifest> manifests = <GameManifest>[];
    for (final GameCatalogEntry entry in entries) {
      if (!entry.enabled) {
        continue;
      }
      final String gamePath = 'assets/games/${entry.slug}/game.json';
      final String resourceManifestPath =
          'assets/games/${entry.slug}/manifest.json';
      try {
        final String gameSource = await loadManifestSource(
          remotePath: gamePath,
          remoteAssetService: remoteAssetService,
          sources: sources,
          preferRemote: preferRemote,
        );
        GameResourceManifest? resourceManifest;
        try {
          final String resourceSource = await loadManifestSource(
            remotePath: resourceManifestPath,
            remoteAssetService: remoteAssetService,
            sources: sources,
            preferRemote: preferRemote,
          );
          resourceManifest = GameResourceManifest.fromJson(
            jsonDecode(resourceSource) as Map<String, dynamic>,
          );
        } catch (error) {
          debugPrint(
            '[manifests] resource manifest unavailable for ${entry.slug}: $error',
          );
        }
        final GameManifest manifest = GameManifest.fromJson(
          jsonDecode(gameSource) as Map<String, dynamic>,
          resourceManifest: resourceManifest,
        );
        manifests.add(manifest);
      } catch (error) {
        debugPrint(
          '[manifests] skipping ${entry.slug} because game.json could not be loaded: $error',
        );
      }
    }
    return manifests;
  }

  Future<String> loadCatalogSource({
    required RemoteAssetService remoteAssetService,
  }) {
    return loadManifestSource(
      remotePath: 'assets/catalog.json',
      remoteAssetService: remoteAssetService,
    );
  }

  Future<String> loadManifestSource({
    required String remotePath,
    required RemoteAssetService remoteAssetService,
    List<AssetSourceConfig> sources = const [],
    bool preferRemote = false,
  }) async {
    if (isOtherStoragePath(remotePath)) {
      throw StateError(
        'Resources under docs/others are excluded from runtime.',
      );
    }

    // 1. Check local cache
    final File? cached = await remoteAssetService.cachedFileFor(remotePath);
    if (cached != null && await cached.exists()) {
      debugPrint('[manifests] using cached source: $remotePath');
      return cached.readAsString();
    }

    // 2. Try fetching from remote only when explicitly requested.
    if (preferRemote && sources.isNotEmpty) {
      try {
        final CachedAsset? asset = await remoteAssetService.ensureCached(
          sources: sources,
          remotePath: remotePath,
          allowCachedFallback: false,
        );
        if (asset != null && asset.exists) {
          debugPrint('[manifests] using remote source: $remotePath');
          return File(asset.localPath).readAsString();
        }
      } catch (e) {
        debugPrint('[manifests] remote fetch failed for $remotePath: $e');
      }
    }

    // 3. Fall back to bundled
    debugPrint('[manifests] using bundled source: $remotePath');
    return rootBundle.loadString(remotePath);
  }

  Future<GameCatalogManifest> loadCatalogManifest({
    required RemoteAssetService remoteAssetService,
  }) async {
    final String catalogSource = await loadCatalogSource(
      remoteAssetService: remoteAssetService,
    );
    return GameCatalogManifest.fromJson(
      jsonDecode(catalogSource) as Map<String, dynamic>,
    );
  }

  Future<GameCatalogManifest> loadBundledCatalogManifest() async {
    final String source = await rootBundle.loadString('assets/catalog.json');
    return GameCatalogManifest.fromJson(
      jsonDecode(source) as Map<String, dynamic>,
    );
  }

  Future<GameCatalogManifest> loadMergedCatalogManifest({
    required RemoteAssetService remoteAssetService,
  }) async {
    final GameCatalogManifest local = await loadBundledCatalogManifest();
    final File? cached = await remoteAssetService.cachedFileFor(
      'assets/catalog.json',
    );
    if (cached == null || !await cached.exists()) {
      debugPrint('[manifests] merged catalog uses bundled catalog only');
      return local;
    }

    try {
      final String remoteSource = await cached.readAsString();
      final GameCatalogManifest remote = GameCatalogManifest.fromJson(
        jsonDecode(remoteSource) as Map<String, dynamic>,
      );
      debugPrint(
        '[manifests] merged catalog base=${local.games.length} overlay=${remote.games.length}',
      );
      return mergeCatalogs(base: local, overlay: remote);
    } catch (_) {
      debugPrint(
        '[manifests] failed to parse cached remote catalog, falling back to bundled',
      );
      return local;
    }
  }

  GameCatalogManifest mergeCatalogs({
    required GameCatalogManifest base,
    required GameCatalogManifest overlay,
  }) {
    final Map<String, GameCatalogEntry> merged = <String, GameCatalogEntry>{
      for (final GameCatalogEntry entry in base.games) entry.slug: entry,
    };

    for (final GameCatalogEntry entry in overlay.games) {
      merged[entry.slug] = entry;
    }

    return GameCatalogManifest(
      version: overlay.version >= base.version ? overlay.version : base.version,
      games: merged.values.toList(),
    );
  }
}
