enum DesktopLibraryResourceType {
  rulebook,
  faq,
  // Kept for source compatibility with older callers and cached data. New
  // resources use the specific type when the manifest declares one.
  assetIndex,
  reference,
  playerAid,
  supplement,
  other,
}

enum DesktopLibraryResourceFormat { markdown, pdf, html, text, image, other }

/// A document shown in the desktop library.
///
/// [isRemote] distinguishes a resource discovered from WebDAV from the local
/// bundled fallback used when the remote index cannot be reached.
class DesktopLibraryResource {
  const DesktopLibraryResource({
    required this.id,
    required this.gameSlug,
    required this.gameTitle,
    required this.remotePath,
    required this.title,
    required this.language,
    required this.type,
    required this.format,
    required this.isRemote,
    this.status = 'available',
    this.enabled = true,
    this.sourceClass = 'unknown',
  });

  final String id;
  final String gameSlug;
  final String gameTitle;
  final String remotePath;
  final String title;
  final String language;
  final DesktopLibraryResourceType type;
  final DesktopLibraryResourceFormat format;
  final bool isRemote;
  final String status;
  final bool enabled;
  final String sourceClass;

  /// Creates a copy while keeping the resource's stable identity by default.
  DesktopLibraryResource copyWith({
    String? id,
    String? gameSlug,
    String? gameTitle,
    String? remotePath,
    String? title,
    String? language,
    DesktopLibraryResourceType? type,
    DesktopLibraryResourceFormat? format,
    bool? isRemote,
    String? status,
    bool? enabled,
    String? sourceClass,
  }) {
    return DesktopLibraryResource(
      id: id ?? this.id,
      gameSlug: gameSlug ?? this.gameSlug,
      gameTitle: gameTitle ?? this.gameTitle,
      remotePath: remotePath ?? this.remotePath,
      title: title ?? this.title,
      language: language ?? this.language,
      type: type ?? this.type,
      format: format ?? this.format,
      isRemote: isRemote ?? this.isRemote,
      status: status ?? this.status,
      enabled: enabled ?? this.enabled,
      sourceClass: sourceClass ?? this.sourceClass,
    );
  }

  /// Stable enum codes used by the persisted desktop library index.
  String get typeCode {
    switch (type) {
      case DesktopLibraryResourceType.rulebook:
        return 'rulebook';
      case DesktopLibraryResourceType.faq:
        return 'faq';
      case DesktopLibraryResourceType.assetIndex:
      case DesktopLibraryResourceType.reference:
      case DesktopLibraryResourceType.supplement:
      case DesktopLibraryResourceType.other:
        return 'other';
      case DesktopLibraryResourceType.playerAid:
        return 'player_aid';
    }
  }

  String get formatCode {
    switch (format) {
      case DesktopLibraryResourceFormat.markdown:
        return 'markdown';
      case DesktopLibraryResourceFormat.pdf:
        return 'pdf';
      case DesktopLibraryResourceFormat.html:
        return 'html';
      case DesktopLibraryResourceFormat.text:
        return 'text';
      case DesktopLibraryResourceFormat.image:
        return 'image';
      case DesktopLibraryResourceFormat.other:
        return 'other';
    }
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'gameSlug': gameSlug,
      'gameTitle': gameTitle,
      'remotePath': remotePath,
      'title': title,
      'language': language,
      'type': typeCode,
      'format': formatCode,
      'isRemote': isRemote,
      'status': status,
      'enabled': enabled,
      'sourceClass': sourceClass,
    };
  }

  /// Parses one persisted index entry. Invalid entries are ignored by the
  /// preference service instead of making the whole app fail to start.
  static DesktopLibraryResource? fromMap(Map<String, dynamic> map) {
    String? stringValue(Object? value) {
      if (value is! String) return null;
      final String normalized = value.trim();
      return normalized.isEmpty ? null : normalized;
    }

    final String? id = stringValue(map['id']);
    final String? gameSlug = stringValue(map['gameSlug']);
    final String? gameTitle = stringValue(map['gameTitle']);
    final String? remotePath = stringValue(map['remotePath']);
    final String? title = stringValue(map['title']);
    final String? language = stringValue(map['language']);
    if (id == null ||
        gameSlug == null ||
        gameTitle == null ||
        remotePath == null ||
        title == null ||
        language == null) {
      return null;
    }

    return DesktopLibraryResource(
      id: id,
      gameSlug: gameSlug,
      gameTitle: gameTitle,
      remotePath: remotePath,
      title: title,
      language: language,
      type: _typeFromCode(map['type'] ?? map['typeCode']),
      format: _formatFromCode(map['format'] ?? map['formatCode']),
      isRemote: map['isRemote'] is bool ? map['isRemote'] as bool : true,
      status: stringValue(map['status']) ?? 'available',
      enabled: map['enabled'] is bool ? map['enabled'] as bool : true,
      sourceClass: stringValue(map['sourceClass']) ?? 'unknown',
    );
  }

  static DesktopLibraryResourceType _typeFromCode(Object? raw) {
    final String code = raw?.toString().trim().toLowerCase() ?? '';
    switch (code) {
      case 'rulebook':
      case 'how_to_play':
        return DesktopLibraryResourceType.rulebook;
      case 'faq':
      case 'ruling':
      case 'errata':
        return DesktopLibraryResourceType.faq;
      case 'player_aid':
      case 'player-aid':
      case 'playeraid':
      case 'aid':
      case 'quick_reference':
        return DesktopLibraryResourceType.playerAid;
      case 'supplement':
        return DesktopLibraryResourceType.supplement;
      case 'reference':
      case 'rules_reference':
        return DesktopLibraryResourceType.reference;
      case 'asset_index':
        return DesktopLibraryResourceType.assetIndex;
      default:
        // The desktop library intentionally exposes only three categories.
        return DesktopLibraryResourceType.other;
    }
  }

  static DesktopLibraryResourceFormat _formatFromCode(Object? raw) {
    switch (raw?.toString().trim().toLowerCase()) {
      case 'markdown':
      case 'md':
        return DesktopLibraryResourceFormat.markdown;
      case 'pdf':
        return DesktopLibraryResourceFormat.pdf;
      case 'html':
      case 'htm':
        return DesktopLibraryResourceFormat.html;
      case 'text':
      case 'txt':
        return DesktopLibraryResourceFormat.text;
      case 'image':
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'webp':
        return DesktopLibraryResourceFormat.image;
      default:
        return DesktopLibraryResourceFormat.other;
    }
  }

  bool get canOpen =>
      format == DesktopLibraryResourceFormat.markdown ||
      format == DesktopLibraryResourceFormat.pdf ||
      format == DesktopLibraryResourceFormat.html ||
      format == DesktopLibraryResourceFormat.text ||
      format == DesktopLibraryResourceFormat.image;

  String get fileName {
    final String normalized = remotePath.replaceAll('\\', '/');
    final int separator = normalized.lastIndexOf('/');
    return separator < 0 ? normalized : normalized.substring(separator + 1);
  }

  String get typeLabel {
    switch (type) {
      case DesktopLibraryResourceType.rulebook:
        return '规则书';
      case DesktopLibraryResourceType.faq:
        return 'FAQ';
      case DesktopLibraryResourceType.assetIndex:
      case DesktopLibraryResourceType.reference:
      case DesktopLibraryResourceType.supplement:
      case DesktopLibraryResourceType.other:
        return '其他';
      case DesktopLibraryResourceType.playerAid:
        return '玩家辅助';
    }
  }

  String get formatLabel {
    switch (format) {
      case DesktopLibraryResourceFormat.markdown:
        return 'Markdown';
      case DesktopLibraryResourceFormat.pdf:
        return 'PDF';
      case DesktopLibraryResourceFormat.html:
        return 'HTML';
      case DesktopLibraryResourceFormat.text:
        return '文本';
      case DesktopLibraryResourceFormat.image:
        return '图片';
      case DesktopLibraryResourceFormat.other:
        return '文件';
    }
  }
}
