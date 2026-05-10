import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/game_catalog_manifest.dart';
import 'remote_asset_service.dart';

class GameManifestService {
  Future<List<GameManifest>> loadEnabledGames({
    required RemoteAssetService remoteAssetService,
  }) async {
    final GameCatalogManifest catalog = await loadMergedCatalogManifest(
      remoteAssetService: remoteAssetService,
    );

    final List<GameCatalogEntry> entries = List<GameCatalogEntry>.from(
      catalog.games,
    )..sort((a, b) => a.order.compareTo(b.order));

    final List<GameManifest> manifests = <GameManifest>[];
    for (final GameCatalogEntry entry in entries) {
      final String manifestPath = 'assets/games/${entry.slug}/game.json';
      final String raw = await loadManifestSource(
        remotePath: manifestPath,
        remoteAssetService: remoteAssetService,
      );
      final GameManifest manifest = GameManifest.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (entry.enabled) {
        manifests.add(manifest);
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
  }) async {
    final File? cached = await remoteAssetService.cachedFileFor(remotePath);
    if (cached != null && await cached.exists()) {
      debugPrint('[manifests] using cached source: $remotePath');
      return cached.readAsString();
    }
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
      debugPrint('[manifests] failed to parse cached remote catalog, falling back to bundled');
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
