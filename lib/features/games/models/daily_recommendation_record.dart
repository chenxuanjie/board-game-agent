class DailyRecommendationRecord {
  const DailyRecommendationRecord({required this.date, required this.gameIds});

  final String date;
  final List<String> gameIds;

  static DailyRecommendationRecord? tryFromMap(Map<String, dynamic> map) {
    final date = map['date'];
    final ids = map['gameIds'];
    if (date is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        ids is! List) {
      return null;
    }
    final normalized = ids
        .whereType<String>()
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalized.isEmpty) return null;
    return DailyRecommendationRecord(date: date, gameIds: normalized);
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
    'date': date,
    'gameIds': gameIds,
  };
}
