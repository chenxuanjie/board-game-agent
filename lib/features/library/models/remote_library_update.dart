enum RemoteLibraryResourceType {
  catalog,
  gameManifest,
  image,
  rulebook,
  faq,
  other,
}

class RemoteLibraryUpdate {
  const RemoteLibraryUpdate({
    required this.changedPaths,
    required this.changedGameTitles,
  });

  final List<String> changedPaths;
  final List<String> changedGameTitles;

  int get changedCount => changedPaths.length;

  Map<RemoteLibraryResourceType, int> get changedResourceCounts {
    final Map<RemoteLibraryResourceType, int> counts =
        <RemoteLibraryResourceType, int>{};
    for (final String path in changedPaths) {
      final RemoteLibraryResourceType type = _resourceTypeForPath(path);
      counts[type] = (counts[type] ?? 0) + 1;
    }
    return Map<RemoteLibraryResourceType, int>.unmodifiable(counts);
  }

  static RemoteLibraryResourceType _resourceTypeForPath(String path) {
    final String normalized = path.trim().toLowerCase();
    if (normalized == 'assets/catalog.json') {
      return RemoteLibraryResourceType.catalog;
    }
    if (normalized.endsWith('/game.json')) {
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
