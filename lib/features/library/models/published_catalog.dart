import '../../games/models/game_catalog_manifest.dart';
import 'game_resource.dart';

/// One complete, immutable publication. The disk representation is the new API
/// contract, never an overlay of bundled or legacy resource manifests.
class PublishedCatalog {
  PublishedCatalog._(this.revision, this.editions, this.games, this.files);

  final int revision;
  final Map<String, Map<String, dynamic>> editions;
  final List<GameManifest> games;
  final Map<String, GameResource> files;

  factory PublishedCatalog.fromJson(Map<String, dynamic> json) {
    if (json['protocol'] != 1 ||
        json['revision'] is! int ||
        (json['revision'] as int) < 0 ||
        json['editions'] is! List) {
      throw const FormatException('Invalid catalog snapshot');
    }
    final values = (json['editions'] as List)
        .map((value) => (value as Map).cast<String, dynamic>())
        .toList();
    if (values.length > 10000) throw const FormatException('Catalog too large');
    values.sort((a, b) {
      final order = (a['sort_order'] as int).compareTo(b['sort_order'] as int);
      return order == 0
          ? (a['id'] as String).compareTo(b['id'] as String)
          : order;
    });
    final editions = <String, Map<String, dynamic>>{};
    final games = <GameManifest>[];
    final files = <String, GameResource>{};
    final resourceIds = <String>{};
    for (final value in values) {
      final game = GameManifest.fromCatalog(value);
      if (editions.containsKey(game.id) ||
          games.any((g) => g.slug == game.slug)) {
        throw const FormatException('Duplicate edition');
      }
      editions[game.id] = _freeze(value) as Map<String, dynamic>;
      games.add(game);
      for (final resource in game.resources) {
        final path = resource.assetPathFor(game.slug);
        if (!validCatalogPath(path) ||
            !resourceIds.add(resource.id) ||
            (files[path] != null && files[path]!.sha256 != resource.sha256)) {
          throw const FormatException('Invalid resource identity');
        }
        files[path] = resource;
      }
    }
    if (files.length > 10000) throw const FormatException('Catalog too large');
    return PublishedCatalog._(
      json['revision'] as int,
      Map.unmodifiable(editions),
      List.unmodifiable(games),
      Map.unmodifiable(files),
    );
  }

  Map<String, dynamic> toJson() => {
    'protocol': 1,
    'revision': revision,
    'editions': editions.values.toList(growable: false),
  };
}

bool validCatalogPath(String path) =>
    path.length <= 1024 &&
    path.startsWith('assets/') &&
    !path.contains('\\') &&
    !path.contains(':') &&
    !RegExp(r'[\x00-\x1f\x7f]').hasMatch(path) &&
    !path.split('/').any((part) => part.isEmpty || part.startsWith('.')) &&
    !isOtherStoragePath(path);

Object? _freeze(Object? value) => switch (value) {
  Map() => Map<String, dynamic>.unmodifiable(
    value.map((key, item) => MapEntry(key as String, _freeze(item))),
  ),
  List() => List<Object?>.unmodifiable(value.map(_freeze)),
  _ => value,
};
