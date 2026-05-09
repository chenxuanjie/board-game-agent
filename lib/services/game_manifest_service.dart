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
    final String catalogSource = await loadCatalogSource(
      remoteAssetService: remoteAssetService,
    );
    final GameCatalogManifest catalog = GameCatalogManifest.fromJson(
      jsonDecode(catalogSource) as Map<String, dynamic>,
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
}
