import '../../../core/localization/app_language.dart';
import 'game_info.dart';
import '../../library/models/game_resource.dart';

class GameManifest {
  GameManifest({
    required this.id,
    required this.slug,
    required this.editionLabels,
    required this.aliases,
    required this.designers,
    required this.publishers,
    required this.keywords,
    required this.coverAsset,
    required this.bannerAsset,
    required this.galleryAssets,
    required this.cardAccent,
    required this.score,
    required this.supportedPlayers,
    required this.recommendedPlayer,
    required this.rulebookPaths,
    required this.faqPaths,
    required this.knowledgePaths,
    required this.resources,
    this.browseCategories = const <String>[],
    required this.locales,
  });

  final String id;
  final String slug;
  final Map<String, String> editionLabels;
  final Map<String, List<String>> aliases;
  final Map<String, List<String>> designers;
  final Map<String, List<String>> publishers;
  final Map<String, List<String>> keywords;
  final String coverAsset;
  final String bannerAsset;
  final List<String> galleryAssets;
  final int cardAccent;
  final String score;
  final List<int> supportedPlayers;
  final int recommendedPlayer;
  final Map<String, String> rulebookPaths;
  final Map<String, String> faqPaths;
  final Map<String, List<String>> knowledgePaths;
  final List<GameResource> resources;
  final List<String> browseCategories;
  final Map<String, GameLocaleContent> locales;

  /// Published SQL edition data. No game.json/manifest.json conversion occurs here.
  factory GameManifest.fromCatalog(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final slug = json['slug'] as String;
    final localeData = (json['locales'] as Map).cast<String, dynamic>();
    if (id.isEmpty ||
        slug.isEmpty ||
        localeData.isEmpty ||
        json['enabled'] != true) {
      throw const FormatException('Invalid published edition');
    }
    final resources = (json['resources'] as List)
        .map(
          (value) =>
              GameResource.fromCatalog((value as Map).cast<String, dynamic>()),
        )
        .toList(growable: false);
    final byId = {for (final resource in resources) resource.id: resource};
    if (byId.length != resources.length) {
      throw const FormatException('Duplicate resource identity');
    }
    final bindings =
        (json['bindings'] as List)
            .map((value) => (value as Map).cast<String, dynamic>())
            .toList()
          ..sort(
            (a, b) => (a['position'] as int).compareTo(b['position'] as int),
          );
    String image(String kind) {
      for (final binding in bindings) {
        if (binding['kind'] == kind) {
          final resource = byId[binding['resource_id']];
          if (resource == null) {
            throw const FormatException('Unknown image binding');
          }
          return resource.path;
        }
      }
      return '';
    }

    Map<String, String> documents(String kind) => {
      for (final binding in bindings)
        if (binding['kind'] == kind && byId.containsKey(binding['resource_id']))
          binding['locale'] as String: byId[binding['resource_id']]!.path,
    };
    Map<String, List<String>> localizedList(String field) => {
      for (final entry in localeData.entries)
        entry.key: _stringList((entry.value as Map)[field]),
    };
    return GameManifest(
      id: id,
      slug: slug,
      editionLabels: {
        for (final entry in localeData.entries)
          entry.key: (entry.value as Map)['edition_label'] as String? ?? '',
      },
      aliases: localizedList('aliases'),
      designers: localizedList('designers'),
      publishers: localizedList('publishers'),
      keywords: localizedList('keywords'),
      coverAsset: image('cover'),
      bannerAsset: image('hero'),
      galleryAssets: [
        for (final binding in bindings)
          if (binding['kind'] == 'gallery' &&
              byId.containsKey(binding['resource_id']))
            byId[binding['resource_id']]!.path,
      ],
      cardAccent: _parseColor(json['card_accent']),
      score: json['external_score_text'] as String,
      supportedPlayers: _intList(json['supported_players']),
      recommendedPlayer: json['recommended_player'] as int,
      rulebookPaths: documents('rulebook'),
      faqPaths: documents('faq'),
      knowledgePaths: {
        for (final locale in localeData.keys)
          locale: [
            for (final binding in bindings)
              if (binding['kind'] == 'knowledge' &&
                  binding['locale'] == locale &&
                  byId.containsKey(binding['resource_id']))
                byId[binding['resource_id']]!.path,
          ],
      },
      resources: resources,
      browseCategories: _stringList(json['categories']),
      locales: {
        for (final entry in localeData.entries)
          entry.key: GameLocaleContent.fromCatalog(
            (entry.value as Map).cast<String, dynamic>(),
          ),
      },
    );
  }

  GameInfo toGameInfo(AppLanguage language) {
    final String localeKey = language == AppLanguage.zhHans ? 'zhHans' : 'en';
    final GameLocaleContent content = _resolveLocaleContent(localeKey);
    final GameResource? rulebookResource = _selectDocumentResource(
      documentTypes: const <String>{'rulebook', 'how_to_play'},
      localeKey: localeKey,
      preferOfficialPdf: true,
    );
    final GameResource? faqResource = _selectDocumentResource(
      documentTypes: const <String>{'faq'},
      localeKey: localeKey,
    );
    final String rulebookPath =
        rulebookResource?.assetPathFor(slug) ??
        _assetPath(_resolveLocalizedPath(rulebookPaths, localeKey));
    final String faqPath =
        faqResource?.assetPathFor(slug) ??
        _assetPath(_resolveLocalizedPath(faqPaths, localeKey));
    final List<String> knowledge = _selectKnowledgeResources(
      localeKey,
    ).map((resource) => resource.assetPathFor(slug)).toList(growable: false);
    final List<String> fallbackKnowledge =
        _resolveLocalizedList(knowledgePaths, localeKey)
            .map(_assetPath)
            .where((path) => path.trim().isNotEmpty)
            .toList(growable: false);

    return GameInfo(
      id: id,
      slug: slug,
      title: content.title,
      subtitle: content.subtitle,
      editionLabel:
          editionLabels[localeKey] ??
          editionLabels['en'] ??
          editionLabels['zhHans'],
      aliases: <String>{
        ..._resolveLocalizedList(aliases, localeKey),
        ...content.aliases,
      }.toList(growable: false),
      designers: <String>{
        ..._resolveLocalizedList(designers, localeKey),
        ...content.designers,
      }.toList(growable: false),
      publishers: <String>{
        ..._resolveLocalizedList(publishers, localeKey),
        ...content.publishers,
      }.toList(growable: false),
      keywords: <String>{
        ..._resolveLocalizedList(keywords, localeKey),
        ...content.keywords,
      }.toList(growable: false),
      coverAssetPath: _assetPath(coverAsset),
      bannerAssetPath: _assetPath(bannerAsset),
      galleryAssetPaths: _resolveAssetList(galleryAssets),
      cardAccent: cardAccent,
      score: score,
      scoreCountLabel: content.scoreCountLabel,
      browseCategories: browseCategories,
      releaseYear: content.releaseYear,
      categoryLine: content.categoryLine,
      learningDifficulty: content.learningDifficulty,
      perPlayerTime: content.perPlayerTime,
      setupTime: content.setupTime,
      languageRequirement: content.languageRequirement,
      supportedPlayers: supportedPlayers,
      recommendedPlayer: recommendedPlayer,
      rankBadges: content.rankBadges,
      rulebookAssetPath: rulebookPath,
      faqAssetPath: faqPath,
      knowledgeAssetPaths: knowledge.isNotEmpty ? knowledge : fallbackKnowledge,
      resources: resources,
      heroTagline: content.heroTagline,
      assistantIntro: content.assistantIntro,
      summary: content.summary,
      mentorPitch: content.mentorPitch,
      playTime: content.playTime,
      playerCount: content.playerCount,
      complexity: content.complexity,
      roundFlow: content.roundFlow,
      assistantSkills: content.assistantSkills,
      quickPrompts: content.quickPrompts,
    );
  }

  GameResource? _selectDocumentResource({
    required Set<String> documentTypes,
    required String localeKey,
    bool preferOfficialPdf = false,
  }) {
    final List<GameResource> candidates = resources
        .where(
          (resource) =>
              documentTypes.contains(resource.documentType) &&
              resource.isAvailable &&
              resource.enabled &&
              !resource.isInOthersDirectory &&
              resource.isRenderableDocument &&
              resource.path.trim().isNotEmpty,
        )
        .toList();
    _sortResources(candidates, localeKey, preferOfficialPdf: preferOfficialPdf);
    return candidates.isEmpty ? null : candidates.first;
  }

  List<GameResource> _selectKnowledgeResources(String localeKey) {
    final List<GameResource> candidates = resources
        .where(
          (resource) =>
              resource.aiEnabled &&
              resource.isAvailable &&
              !resource.isInOthersDirectory &&
              resource.isMarkdown &&
              resource.path.trim().isNotEmpty,
        )
        .toList();
    final List<GameResource> preferred = candidates
        .where((resource) => _languageRank(resource.language, localeKey) == 0)
        .toList();
    final List<GameResource> selected = preferred.isNotEmpty
        ? preferred
        : candidates
              .where(
                (resource) => _languageRank(resource.language, localeKey) < 3,
              )
              .toList();
    _sortResources(selected, localeKey);
    return List<GameResource>.unmodifiable(selected);
  }

  void _sortResources(
    List<GameResource> values,
    String localeKey, {
    bool preferOfficialPdf = false,
  }) {
    values.sort((a, b) {
      if (preferOfficialPdf) {
        final int documentFormat = _documentFormatRank(
          a,
        ).compareTo(_documentFormatRank(b));
        if (documentFormat != 0) return documentFormat;
      }
      final int language = _languageRank(
        a.language,
        localeKey,
      ).compareTo(_languageRank(b.language, localeKey));
      if (language != 0) return language;
      final int priority = a.priority.compareTo(b.priority);
      if (priority != 0) return priority;
      return a.id.compareTo(b.id);
    });
  }

  int _documentFormatRank(GameResource resource) {
    if (resource.format == 'pdf' && resource.sourceClass == 'official') {
      return 0;
    }
    if (resource.format == 'pdf') {
      return 1;
    }
    return 2;
  }

  int _languageRank(String language, String localeKey) {
    final String normalized = language.toLowerCase();
    final bool wantsChinese = localeKey == 'zhHans';
    if (wantsChinese) {
      if (normalized == 'cn' || normalized == 'zh' || normalized == 'zhhans') {
        return 0;
      }
      if (normalized == 'multi') return 1;
      if (normalized == 'en') return 2;
      return 3;
    }
    if (normalized == 'en') return 0;
    if (normalized == 'multi') return 1;
    if (normalized == 'cn' || normalized == 'zh' || normalized == 'zhhans') {
      return 2;
    }
    return 3;
  }

  GameLocaleContent _resolveLocaleContent(String localeKey) {
    return locales[localeKey] ??
        locales['en'] ??
        locales['zhHans'] ??
        locales.values.first;
  }

  String _resolveLocalizedPath(Map<String, String> source, String localeKey) {
    if (source[localeKey]?.trim().isNotEmpty ?? false) {
      return source[localeKey]!;
    }
    if (source['en']?.trim().isNotEmpty ?? false) {
      return source['en']!;
    }
    if (source['zhHans']?.trim().isNotEmpty ?? false) {
      return source['zhHans']!;
    }
    for (final String value in source.values) {
      if (value.trim().isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  List<String> _resolveLocalizedList(
    Map<String, List<String>> source,
    String localeKey,
  ) {
    final List<String>? localized = source[localeKey];
    if (localized != null && localized.isNotEmpty) {
      return localized;
    }
    final List<String>? english = source['en'];
    if (english != null && english.isNotEmpty) {
      return english;
    }
    final List<String>? chinese = source['zhHans'];
    if (chinese != null && chinese.isNotEmpty) {
      return chinese;
    }
    for (final List<String> values in source.values) {
      if (values.isNotEmpty) {
        return values;
      }
    }
    return <String>[];
  }

  String _assetPath(String relativeOrAbsolutePath) {
    if (relativeOrAbsolutePath.trim().isEmpty ||
        isOtherStoragePath(relativeOrAbsolutePath)) {
      return '';
    }
    if (relativeOrAbsolutePath.startsWith('assets/')) {
      return relativeOrAbsolutePath;
    }
    return 'assets/games/$slug/$relativeOrAbsolutePath';
  }

  List<String> _resolveAssetList(List<String> relativePaths) {
    final List<String> resolved = relativePaths
        .where((path) => path.trim().isNotEmpty)
        .map(_assetPath)
        .where((path) => path.trim().isNotEmpty)
        .toList();
    if (resolved.isNotEmpty) {
      return resolved;
    }

    final List<String> fallback = <String>[
      _assetPath(coverAsset),
      _assetPath(bannerAsset),
    ].where((path) => path.trim().isNotEmpty).toSet().toList();
    return fallback;
  }

  static List<String> _stringList(dynamic value) {
    if (value is String) {
      final String normalized = value.trim();
      return normalized.isEmpty ? <String>[] : <String>[normalized];
    }
    if (value is! Iterable) {
      return <String>[];
    }
    return value
        .whereType<String>()
        .map((String item) => item.trim())
        .where((String item) => item.isNotEmpty)
        .toList();
  }

  static List<int> _intList(dynamic value) {
    final List<dynamic> list = value as List<dynamic>? ?? const <dynamic>[];
    return list.map((item) => (item as num).toInt()).toList();
  }

  static int _parseColor(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is String) {
      final String normalized = value.trim();
      if (normalized.isEmpty) return 0xFF607D8B;
      if (normalized.startsWith('0x') || normalized.startsWith('0X')) {
        return int.parse(normalized.substring(2), radix: 16);
      }
      return int.parse(normalized);
    }
    return 0xFF607D8B;
  }
}

class GameLocaleContent {
  GameLocaleContent({
    required this.title,
    required this.subtitle,
    required this.aliases,
    required this.designers,
    required this.publishers,
    required this.keywords,
    required this.scoreCountLabel,
    required this.releaseYear,
    required this.categoryLine,
    required this.learningDifficulty,
    required this.perPlayerTime,
    required this.setupTime,
    required this.languageRequirement,
    required this.rankBadges,
    required this.heroTagline,
    required this.assistantIntro,
    required this.summary,
    required this.mentorPitch,
    required this.playTime,
    required this.playerCount,
    required this.complexity,
    required this.roundFlow,
    required this.assistantSkills,
    required this.quickPrompts,
  });

  final String title;
  final String subtitle;
  final List<String> aliases;
  final List<String> designers;
  final List<String> publishers;
  final List<String> keywords;
  final String scoreCountLabel;
  final String releaseYear;
  final String categoryLine;
  final String learningDifficulty;
  final String perPlayerTime;
  final String setupTime;
  final String languageRequirement;
  final List<String> rankBadges;
  final String heroTagline;
  final String assistantIntro;
  final String summary;
  final String mentorPitch;
  final String playTime;
  final String playerCount;
  final String complexity;
  final List<String> roundFlow;
  final List<String> assistantSkills;
  final List<String> quickPrompts;

  factory GameLocaleContent.fromCatalog(Map<String, dynamic> json) {
    return GameLocaleContent(
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      aliases: GameManifest._stringList(json['local_aliases']),
      designers: GameManifest._stringList(json['local_designers']),
      publishers: GameManifest._stringList(json['local_publishers']),
      keywords: GameManifest._stringList(json['local_keywords']),
      scoreCountLabel: json['score_count_label'] as String? ?? '',
      releaseYear: json['release_year'] as String? ?? '',
      categoryLine: json['category_line'] as String? ?? '',
      learningDifficulty: json['learning_difficulty'] as String? ?? '',
      perPlayerTime: json['per_player_time'] as String? ?? '',
      setupTime: json['setup_time'] as String? ?? '',
      languageRequirement: json['language_requirement'] as String? ?? '',
      rankBadges: GameManifest._stringList(json['rank_badges']),
      heroTagline: json['hero_tagline'] as String? ?? '',
      assistantIntro: json['assistant_intro'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      mentorPitch: json['mentor_pitch'] as String? ?? '',
      playTime: json['play_time'] as String? ?? '',
      playerCount: json['player_count'] as String? ?? '',
      complexity: json['complexity'] as String? ?? '',
      roundFlow: GameManifest._stringList(json['round_flow']),
      assistantSkills: GameManifest._stringList(json['assistant_skills']),
      quickPrompts: GameManifest._stringList(json['quick_prompts']),
    );
  }
}
