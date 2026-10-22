class RecentGameRecord {
  const RecentGameRecord({required this.gameSlug, required this.viewedAt});

  final String gameSlug;
  final DateTime viewedAt;

  String get normalizedGameSlug => gameSlug.trim().toLowerCase();

  static RecentGameRecord? tryFromMap(Map<String, dynamic> map) {
    final gameSlug = map['gameSlug'];
    final viewedAt = map['viewedAt'];
    if (gameSlug is! String || viewedAt is! String) return null;

    final normalizedSlug = gameSlug.trim();
    final parsedDate = DateTime.tryParse(viewedAt);
    if (normalizedSlug.isEmpty || parsedDate == null) return null;
    return RecentGameRecord(
      gameSlug: normalizedSlug,
      viewedAt: parsedDate.toUtc(),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
    'gameSlug': gameSlug.trim(),
    'viewedAt': viewedAt.toUtc().toIso8601String(),
  };
}
