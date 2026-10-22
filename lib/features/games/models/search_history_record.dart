class SearchHistoryRecord {
  const SearchHistoryRecord({required this.query, required this.searchedAt});

  final String query;
  final DateTime searchedAt;

  String get normalizedQuery => query.trim().toLowerCase();

  static SearchHistoryRecord? tryFromMap(Map<String, dynamic> map) {
    final query = map['query'];
    final searchedAt = map['searchedAt'];
    if (query is! String || searchedAt is! String) return null;

    final normalizedQuery = query.trim();
    final parsedDate = DateTime.tryParse(searchedAt);
    if (normalizedQuery.isEmpty || parsedDate == null) return null;
    return SearchHistoryRecord(
      query: normalizedQuery,
      searchedAt: parsedDate.toUtc(),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
    'query': query.trim(),
    'searchedAt': searchedAt.toUtc().toIso8601String(),
  };
}
