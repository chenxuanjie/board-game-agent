class FavoriteGameRecord {
  const FavoriteGameRecord({required this.gameSlug, required this.createdAt});

  final String gameSlug;
  final DateTime createdAt;

  static FavoriteGameRecord? tryFromMap(Map<String, dynamic> map) {
    final slug = map['gameSlug'];
    final createdAt = map['createdAt'];
    if (slug is! String || createdAt is! String) {
      return null;
    }
    final normalizedSlug = slug.trim();
    final parsedDate = DateTime.tryParse(createdAt);
    if (normalizedSlug.isEmpty || parsedDate == null) {
      return null;
    }
    return FavoriteGameRecord(
      gameSlug: normalizedSlug,
      createdAt: parsedDate.toUtc(),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
    'gameSlug': gameSlug,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
}
