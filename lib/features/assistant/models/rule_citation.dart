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
    this.fileSha256,
    this.edition,
    this.publicationRevision,
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
  final String? fileSha256;
  final String? edition;
  final int? publicationRevision;

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
    if (fileSha256 != null) 'fileSha256': fileSha256,
    if (edition != null) 'edition': edition,
    if (publicationRevision != null) 'publicationRevision': publicationRevision,
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
    fileSha256: map['fileSha256'] as String?,
    edition: map['edition'] as String?,
    publicationRevision: (map['publicationRevision'] as num?)?.toInt(),
  );
}
