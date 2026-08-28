import 'rule_citation.dart';

/// A rule document selected from the currently active game's knowledge paths.
class RuleDocument {
  const RuleDocument({
    required this.id,
    required this.title,
    required this.path,
    required this.format,
    required this.language,
    required this.sourceType,
    this.derivedFrom = const <String>[],
    this.version,
    this.url,
  });

  final String id;
  final String title;
  final String path;
  final String format;
  final String language;
  final String sourceType;

  /// IDs or paths of the source materials used to derive this document.
  ///
  /// This is kept at the retrieval boundary so a locally translated or
  /// extracted document can still be assigned to the correct provenance
  /// stage instead of being mixed with an unrelated source class.
  final List<String> derivedFrom;
  final String? version;
  final String? url;

  RuleCitation toCitation() => RuleCitation(
    sourceType: sourceType,
    sourceId: id,
    title: title,
    path: path,
    url: url,
    language: language,
  );
}
