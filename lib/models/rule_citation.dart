/// A verified citation resolved by the application from a rule source ID.
class RuleCitation {
  const RuleCitation({
    required this.sourceType,
    required this.sourceId,
    this.title,
    this.path,
    this.url,
    this.language,
    this.page,
    this.lineStart,
    this.lineEnd,
    this.section,
    this.quote,
  });

  final String sourceType;
  final String sourceId;
  final String? title;
  final String? path;
  final String? url;
  final String? language;
  final int? page;
  final int? lineStart;
  final int? lineEnd;
  final String? section;
  final String? quote;

  Map<String, dynamic> toMap({bool includeQuote = true}) => <String, dynamic>{
    'sourceType': sourceType,
    'sourceId': sourceId,
    if (title != null) 'title': title,
    if (path != null) 'path': path,
    if (url != null) 'url': url,
    if (language != null) 'language': language,
    if (page != null) 'page': page,
    if (lineStart != null) 'lineStart': lineStart,
    if (lineEnd != null) 'lineEnd': lineEnd,
    if (section != null) 'section': section,
    if (includeQuote && quote != null) 'quote': quote,
  };

  factory RuleCitation.fromMap(Map<String, dynamic> map) => RuleCitation(
    sourceType: map['sourceType'] as String? ?? 'unknown',
    sourceId: map['sourceId'] as String? ?? '',
    title: map['title'] as String?,
    path: map['path'] as String?,
    url: map['url'] as String?,
    language: map['language'] as String?,
    page: map['page'] as int?,
    lineStart: map['lineStart'] as int?,
    lineEnd: map['lineEnd'] as int?,
    section: map['section'] as String?,
    quote: map['quote'] as String?,
  );
}
