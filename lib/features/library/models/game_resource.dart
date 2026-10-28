/// A public resource in a published SQL catalog edition.
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
    this.sha256,
    this.contentUrl,
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
  final String? sha256;
  final String? contentUrl;

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

  factory GameResource.fromCatalog(Map<String, dynamic> json) {
    final digest = json['file_sha256'] as String;
    final url = json['content_url'] as String;
    final uri = Uri.parse(url);
    final id = json['id'] as String;
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.:-]{0,255}$').hasMatch(id) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest) ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.hasFragment ||
        uri.pathSegments.join('/') !=
            'v1/apps/board_game_agent/catalog/resources/$id/content' ||
        uri.queryParametersAll.length != 1 ||
        uri.queryParametersAll['version']?.length != 1 ||
        uri.queryParametersAll['version']?.single != digest ||
        json['visibility'] != 'public' ||
        json['enabled'] != true ||
        json['status'] != 'available') {
      throw const FormatException('Invalid published resource');
    }
    return GameResource(
      id: _stringValue(json['id']),
      path: _stringValue(json['path']),
      documentType: _stringValue(json['document_type'], fallback: 'other'),
      sourceClass: _stringValue(json['source_class'], fallback: 'unknown'),
      origin: _stringValue(json['origin'], fallback: 'unknown'),
      language: _stringValue(json['language'], fallback: 'none'),
      edition: _stringValue(json['edition_code'], fallback: 'unknown'),
      status: _stringValue(json['status'], fallback: 'unverified'),
      enabled: json['enabled'] as bool? ?? false,
      aiEnabled: json['ai_enabled'] as bool? ?? false,
      priority: (json['priority'] as num?)?.toInt() ?? 500,
      derivedFrom: _stringList(json['derived_from']),
      sourceUrl: json['source_url'] as String?,
      reviewStatus: _stringValue(json['review_status'], fallback: 'unreviewed'),
      notes: json['notes'] as String?,
      sha256: digest,
      contentUrl: url,
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
