import 'dart:convert';

import 'rule_citation.dart';

/// A document declared in the remote rule source catalog.
class RuleSourceDocument {
  const RuleSourceDocument({
    required this.id,
    required this.title,
    required this.path,
    required this.format,
    required this.language,
    this.version,
    this.url,
    required this.sourceType,
  });

  final String id;
  final String title;
  final String path;
  final String format;
  final String language;
  final String? version;
  final String? url;
  final String sourceType;

  RuleCitation toCitation() => RuleCitation(
    sourceType: sourceType,
    sourceId: id,
    title: title,
    path: path,
    url: url,
    language: language,
  );
}

/// Source catalog entry for one game.
class RuleGameSourceCatalog {
  const RuleGameSourceCatalog({
    required this.slug,
    this.aliases = const <String>[],
    this.terms = const <String, List<String>>{},
    this.official = const <RuleSourceDocument>[],
    this.community = const <RuleSourceDocument>[],
  });

  final String slug;
  final List<String> aliases;
  final Map<String, List<String>> terms;
  final List<RuleSourceDocument> official;
  final List<RuleSourceDocument> community;

  List<String> get terminologyLines => terms.entries
      .expand((entry) => entry.value.map((value) => '${entry.key} = $value'))
      .toList(growable: false);
}

/// Parsed `apps/board_game_agent/board-game-lib/rule_sources.json`.
class RuleSourceCatalog {
  const RuleSourceCatalog({required this.version, required this.games});

  final int version;
  final Map<String, RuleGameSourceCatalog> games;

  RuleGameSourceCatalog? forGame(String slug) => games[slug];

  factory RuleSourceCatalog.fromJson(String source) {
    final Map<String, dynamic> json =
        jsonDecode(source) as Map<String, dynamic>;
    final Map<String, dynamic> rawGames =
        (json['games'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final Map<String, RuleGameSourceCatalog> games =
        <String, RuleGameSourceCatalog>{};
    for (final MapEntry<String, dynamic> entry in rawGames.entries) {
      final Map<String, dynamic> raw =
          (entry.value as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      games[entry.key] = RuleGameSourceCatalog(
        slug: entry.key,
        aliases: _strings(raw['aliases']),
        terms: _terms(raw['terms']),
        official: _documents(raw['official'], sourceType: 'official'),
        community: _documents(raw['community'], sourceType: 'community'),
      );
    }
    return RuleSourceCatalog(
      version: (json['version'] as num?)?.toInt() ?? 1,
      games: Map<String, RuleGameSourceCatalog>.unmodifiable(games),
    );
  }

  static List<RuleSourceDocument> _documents(
    dynamic value, {
    required String sourceType,
  }) {
    if (value is! List) return const <RuleSourceDocument>[];
    return value
        .whereType<Map>()
        .map((rawValue) {
          final Map<String, dynamic> raw = rawValue.cast<String, dynamic>();
          return RuleSourceDocument(
            id: raw['id'] as String? ?? '',
            title: raw['title'] as String? ?? raw['id'] as String? ?? '',
            path: raw['path'] as String? ?? '',
            format: raw['format'] as String? ?? 'md',
            language: raw['language'] as String? ?? 'en',
            version: raw['version'] as String?,
            url: raw['url'] as String?,
            sourceType: sourceType,
          );
        })
        .where((item) => item.id.isNotEmpty && item.path.isNotEmpty)
        .toList();
  }

  static List<String> _strings(dynamic value) => value is List
      ? value
            .whereType<String>()
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList()
      : const <String>[];

  static Map<String, List<String>> _terms(dynamic value) {
    if (value is! Map) return const <String, List<String>>{};
    return Map<String, List<String>>.unmodifiable(
      value.map((key, rawValue) => MapEntry('$key', _strings(rawValue))),
    );
  }
}
