import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:board_game_agent/features/games/models/game_catalog_manifest.dart';
import 'package:board_game_agent/features/games/services/game_manifest_service.dart';
import 'package:board_game_agent/features/library/models/asset_source_config.dart';
import 'package:board_game_agent/features/library/services/remote_asset_service.dart';

/// Test-only conversion of checked-in authoring fixtures into the SQL wire
/// contract. Production never reads or converts these JSON authoring files.
Map<String, dynamic> catalogEditionFixture(
  Map<String, dynamic> game, {
  Map<String, dynamic>? resourceManifest,
  List<String> categories = const [],
  int order = 0,
}) {
  final slug = game['slug'] as String;
  List<String> strings(Object? value) => value is List
      ? value.cast<String>()
      : value is String && value.isNotEmpty
      ? [value]
      : [];
  List<String> localized(Object? value, String locale) =>
      strings(value is Map ? value[locale] : value);
  final resources = <Map<String, dynamic>>[];
  for (final raw in resourceManifest?['resources'] as List? ?? []) {
    final r = (raw as Map).cast<String, dynamic>();
    if (r['enabled'] != true ||
        r['status'] != 'available' ||
        '${r['path']}'.contains('docs/others/')) {
      continue;
    }
    final id = r['id'] as String;
    final hash = sha256.convert(utf8.encode('fixture:$id')).toString();
    final type = r['documentType'] as String? ?? 'other';
    resources.add({
      'id': id,
      'edition_id': game['id'],
      'path': r['path'],
      'document_type': ['cover', 'background', 'gallery'].contains(type)
          ? 'image'
          : type,
      'source_class': r['sourceClass'] ?? 'unknown',
      'origin': r['origin'] ?? 'unknown',
      'language': r['language'] ?? 'none',
      'edition_code': r['edition'] ?? 'unknown',
      'status': 'available',
      'enabled': true,
      'ai_enabled': r['aiEnabled'] ?? false,
      'priority': r['priority'] ?? 500,
      'derived_from': r['derivedFrom'] ?? [],
      'source_url': r['sourceUrl'],
      'review_status': r['reviewStatus'] ?? 'unreviewed',
      'notes': r['notes'],
      'visibility': 'public',
      'file_sha256': hash,
      'content_url':
          '/v1/apps/board_game_agent/catalog/resources/$id/content?version=$hash',
    });
  }
  final bindings = <Map<String, dynamic>>[];
  void bind(String kind, String path, {String locale = '', int position = 0}) {
    final local = path.startsWith('assets/games/$slug/')
        ? path.substring('assets/games/$slug/'.length)
        : path;
    final matching = resources.where((r) => r['path'] == local).toList();
    if (matching.isNotEmpty) {
      bindings.add({
        'kind': kind,
        'locale': locale,
        'position': position,
        'resource_id': matching.first['id'],
      });
    }
  }

  if (game['coverAsset'] case final String value) bind('cover', value);
  if (game['bannerAsset'] case final String value) bind('hero', value);
  var position = 0;
  for (final path in strings(game['galleryAssets'])) {
    bind('gallery', path, position: position++);
  }
  final locales = <String, dynamic>{};
  for (final entry in (game['locales'] as Map? ?? {}).entries) {
    final locale = entry.key as String;
    final raw = (entry.value as Map).cast<String, dynamic>();
    final converted = <String, dynamic>{
      for (final field in raw.entries)
        field.key.replaceAllMapped(
          RegExp('[A-Z]'),
          (m) => '_${m[0]!.toLowerCase()}',
        ): field.value,
      'edition_label': (game['editionLabel'] as Map?)?[locale] ?? '',
    };
    for (final field in ['aliases', 'designers', 'publishers', 'keywords']) {
      converted[field] = localized(game[field], locale);
      converted['local_$field'] = strings(raw[field]);
    }
    locales[locale] = converted;
  }
  return {
    'id': game['id'],
    'game_id': game['id'],
    'slug': slug,
    'edition_code': resourceManifest?['game']?['edition'] ?? 'fixture',
    'sort_order': order,
    'enabled': true,
    'card_accent': game['cardAccent'] ?? '0xFF607D8B',
    'external_score_text': game['score'] ?? '',
    'supported_players': game['supportedPlayers'] ?? [],
    'recommended_player': game['recommendedPlayer'] ?? 0,
    'categories': categories,
    'locales': locales,
    'resources': resources,
    'bindings': bindings,
  };
}

GameManifest catalogGameFixture(
  Map<String, dynamic> game, {
  Map<String, dynamic>? resourceManifest,
  List<String> browseCategories = const [],
}) => GameManifest.fromCatalog(
  catalogEditionFixture(
    game,
    resourceManifest: resourceManifest,
    categories: browseCategories,
  ),
);

class FixtureGameManifestService extends GameManifestService {
  @override
  Future<List<GameManifest>> loadEnabledGames({
    required RemoteAssetService remoteAssetService,
    List<AssetSourceConfig> sources = const [],
    bool preferRemote = false,
  }) async {
    final catalog =
        jsonDecode(File('assets/catalog.json').readAsStringSync()) as Map;
    final games = <GameManifest>[];
    for (final raw in catalog['games'] as List) {
      final entry = raw as Map;
      if (entry['enabled'] != true) continue;
      final slug = entry['slug'] as String;
      final game =
          jsonDecode(File('assets/games/$slug/game.json').readAsStringSync())
              as Map<String, dynamic>;
      final file = File('assets/games/$slug/manifest.json');
      final resources = file.existsSync()
          ? jsonDecode(file.readAsStringSync()) as Map<String, dynamic>
          : null;
      games.add(
        catalogGameFixture(
          game,
          resourceManifest: resources,
          browseCategories: (entry['browseCategories'] as List? ?? [])
              .cast<String>(),
        ),
      );
    }
    return games;
  }
}
