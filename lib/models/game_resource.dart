/// A resource registered in a game's manifest.json.
///
/// Paths are relative to `assets/games/<slug>/` in the manifest. The runtime
/// converts them to Flutter asset paths when it creates a GameInfo instance.
class GameResource {
  const GameResource({
    required this.id,
    required this.path,
    required this.documentType,
    required this.sourceClass,
    required this.origin,
    required this.language,
    required this.edition,
    required this.status,
    required this.enabled,
    required this.aiEnabled,
    required this.priority,
    required this.derivedFrom,
    required this.sourceUrl,
    required this.reviewStatus,
    required this.notes,
  });

  final String id;
  final String path;
  final String documentType;
  final String sourceClass;
  final String origin;
  final String language;
  final String edition;
  final String status;
  final bool enabled;
  final bool aiEnabled;
  final int priority;
  final List<String> derivedFrom;
  final String? sourceUrl;
  final String reviewStatus;
  final String? notes;

  bool get isAvailable => status == 'available';

  /// Resources under `docs/others/` are retained for archive or cleanup work
  /// and must never become runtime-readable application resources.
  bool get isInOthersDirectory => isOtherStoragePath(path);

  String get fileName {
    final String normalized = path.replaceAll('\\', '/');
    final int slash = normalized.lastIndexOf('/');
    return slash == -1 ? normalized : normalized.substring(slash + 1);
  }

  String get format {
    final int dot = fileName.lastIndexOf('.');
    return dot == -1 ? 'bin' : fileName.substring(dot + 1).toLowerCase();
  }

  bool get isMarkdown => format == 'md' || format == 'markdown';

  bool get isRenderableDocument => format == 'pdf' || isMarkdown;

  String assetPathFor(String slug) {
    if (isInOthersDirectory) {
      return '';
    }
    if (path.startsWith('assets/')) {
      return path;
    }
    return 'assets/games/$slug/$path';
  }

  factory GameResource.fromJson(Map<String, dynamic> json) {
    return GameResource(
      id: _stringValue(json['id']),
      path: _stringValue(json['path']),
      documentType: _stringValue(json['documentType'], fallback: 'other'),
      sourceClass: _stringValue(json['sourceClass'], fallback: 'unknown'),
      origin: _stringValue(json['origin'], fallback: 'unknown'),
      language: _stringValue(json['language'], fallback: 'none'),
      edition: _stringValue(json['edition'], fallback: 'unknown'),
      status: _stringValue(json['status'], fallback: 'unverified'),
      enabled: json['enabled'] as bool? ?? false,
      aiEnabled: json['aiEnabled'] as bool? ?? false,
      priority: (json['priority'] as num?)?.toInt() ?? 500,
      derivedFrom: _stringList(json['derivedFrom']),
      sourceUrl: json['sourceUrl'] as String?,
      reviewStatus: _stringValue(json['reviewStatus'], fallback: 'unreviewed'),
      notes: json['notes'] as String?,
    );
  }
}

bool isOtherStoragePath(String path) {
  final List<String> segments = path
      .replaceAll('\\', '/')
      .trim()
      .toLowerCase()
      .split('/');
  for (int index = 0; index + 1 < segments.length; index++) {
    if (segments[index] == 'docs' && segments[index + 1] == 'others') {
      return true;
    }
  }
  return false;
}

class GameResourceManifest {
  const GameResourceManifest({
    required this.schemaVersion,
    required this.gameId,
    required this.gameSlug,
    required this.edition,
    required this.resources,
  });

  final int schemaVersion;
  final String gameId;
  final String gameSlug;
  final String edition;
  final List<GameResource> resources;

  factory GameResourceManifest.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> game = _mapValue(json['game']);
    final List<dynamic> resourcesJson =
        json['resources'] as List<dynamic>? ?? const <dynamic>[];

    return GameResourceManifest(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      gameId: _stringValue(game['id']),
      gameSlug: _stringValue(game['slug']),
      edition: _stringValue(game['edition'], fallback: 'unknown'),
      resources: List<GameResource>.unmodifiable(
        resourcesJson.whereType<Map<String, dynamic>>().map(
          GameResource.fromJson,
        ),
      ),
    );
  }
}

Map<String, dynamic> _mapValue(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  return <String, dynamic>{};
}

String _stringValue(dynamic value, {String fallback = ''}) {
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  return fallback;
}

List<String> _stringList(dynamic value) {
  final List<dynamic> list = value is List<dynamic> ? value : const <dynamic>[];
  return List<String>.unmodifiable(list.whereType<String>());
}
