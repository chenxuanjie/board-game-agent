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
    this.version,
    this.url,
  });

  final String id;
  final String title;
  final String path;
  final String format;
  final String language;
  final String sourceType;
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
