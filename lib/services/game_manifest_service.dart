import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/game_catalog_manifest.dart';

class GameManifestService {
  Future<List<GameManifest>> loadEnabledGames() async {
    final String catalogSource = await rootBundle.loadString('assets/catalog.json');
    final GameCatalogManifest catalog = GameCatalogManifest.fromJson(
      jsonDecode(catalogSource) as Map<String, dynamic>,
    );

    final List<GameCatalogEntry> entries = List<GameCatalogEntry>.from(
      catalog.games,
    )..sort((a, b) => a.order.compareTo(b.order));

    final List<GameManifest> manifests = <GameManifest>[];
    for (final GameCatalogEntry entry in entries) {
      final String manifestPath = 'assets/games/${entry.slug}/game.json';
      final String raw = await rootBundle.loadString(manifestPath);
      final GameManifest manifest = GameManifest.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (entry.enabled) {
        manifests.add(manifest);
      }
    }
    return manifests;
  }
}
