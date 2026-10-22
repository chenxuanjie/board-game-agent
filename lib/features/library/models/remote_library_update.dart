enum RemoteLibraryResourceType {
  catalog,
  gameManifest,
  image,
  rulebook,
  faq,
  other,
}

enum RemoteLibraryChangeKind { added, modified, disabled }

class RemoteLibraryChange {
  const RemoteLibraryChange({
    required this.path,
    required this.title,
    this.kind = RemoteLibraryChangeKind.modified,
    this.fields = const [],
    this.valueChanges = const {},
  });
  final String path;
  final String title;
  final RemoteLibraryChangeKind kind;
  // Semantic field identifiers; the UI translates them, never renders JSON.
  final List<String> fields;
  final Map<String, String> valueChanges;
}

class RemoteLibraryUpdate {
  const RemoteLibraryUpdate({
    required this.changedPaths,
    required this.changedGameTitles,
    this.changes = const [],
  });

  final List<String> changedPaths;
  final List<String> changedGameTitles;
  final List<RemoteLibraryChange> changes;

  int get changedCount => changedPaths.length;

  Map<RemoteLibraryResourceType, int> get changedResourceCounts {
    final Map<RemoteLibraryResourceType, int> counts =
        <RemoteLibraryResourceType, int>{};
    for (final String path in changedPaths) {
      final RemoteLibraryResourceType type = resourceTypeForPath(path);
      counts[type] = (counts[type] ?? 0) + 1;
    }
    return Map<RemoteLibraryResourceType, int>.unmodifiable(counts);
  }

  static RemoteLibraryResourceType resourceTypeForPath(String path) {
    final String normalized = path.trim().toLowerCase();
    if (normalized == 'assets/catalog.json') {
      return RemoteLibraryResourceType.catalog;
    }
    if (normalized.endsWith('/game.json') ||
        normalized.endsWith('/manifest.json')) {
      return RemoteLibraryResourceType.gameManifest;
    }
    if (normalized.contains('/images/')) {
      return RemoteLibraryResourceType.image;
    }
    if (normalized.contains('rulebook')) {
      return RemoteLibraryResourceType.rulebook;
    }
    if (normalized.contains('/faq') || normalized.contains('faq.')) {
      return RemoteLibraryResourceType.faq;
    }
    return RemoteLibraryResourceType.other;
  }
}
