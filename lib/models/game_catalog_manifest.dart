import 'app_language.dart';
import 'game_info.dart';

class GameCatalogManifest {
  GameCatalogManifest({required this.version, required this.games});

  final int version;
  final List<GameCatalogEntry> games;

  factory GameCatalogManifest.fromJson(Map<String, dynamic> json) {
    final List<dynamic> gamesJson =
        json['games'] as List<dynamic>? ?? const <dynamic>[];
    return GameCatalogManifest(
      version: json['version'] as int? ?? 1,
      games: gamesJson
          .map(
            (item) => GameCatalogEntry.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

class GameCatalogEntry {
  GameCatalogEntry({
    required this.slug,
    required this.order,
    required this.enabled,
  });

  final String slug;
  final int order;
  final bool enabled;

  factory GameCatalogEntry.fromJson(Map<String, dynamic> json) {
    return GameCatalogEntry(
      slug: json['slug'] as String,
      order: json['order'] as int? ?? 0,
      enabled: json['enabled'] as bool? ?? false,
    );
  }
}

class GameManifest {
  GameManifest({
    required this.id,
    required this.slug,
    required this.editionLabels,
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
    required this.locales,
  });

  final String id;
  final String slug;
  final Map<String, String> editionLabels;
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
  final Map<String, GameLocaleContent> locales;

  factory GameManifest.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> documents =
        json['documents'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final Map<String, dynamic> locales =
        json['locales'] as Map<String, dynamic>? ?? <String, dynamic>{};

    return GameManifest(
      id: json['id'] as String,
      slug: json['slug'] as String,
      editionLabels: _localizedStringMap(json['editionLabel']),
      coverAsset: json['coverAsset'] as String? ?? '',
      bannerAsset: json['bannerAsset'] as String? ?? '',
      galleryAssets: _stringList(json['galleryAssets']),
      cardAccent: _parseColor(json['cardAccent']),
      score: json['score'] as String? ?? '',
      supportedPlayers: _intList(json['supportedPlayers']),
      recommendedPlayer: json['recommendedPlayer'] as int? ?? 0,
      rulebookPaths: _localizedStringMap(documents['rulebook']),
      faqPaths: _localizedStringMap(documents['faq']),
      knowledgePaths: _localizedStringListMap(documents['knowledge']),
      locales: locales.map(
        (key, value) => MapEntry(
          key,
          GameLocaleContent.fromJson(value as Map<String, dynamic>),
        ),
      ),
    );
  }

  GameInfo toGameInfo(AppLanguage language) {
    final String localeKey = language == AppLanguage.zhHans ? 'zhHans' : 'en';
    final GameLocaleContent content = _resolveLocaleContent(localeKey);
    final String rulebookPath = _resolveLocalizedPath(rulebookPaths, localeKey);
    final String faqPath = _resolveLocalizedPath(faqPaths, localeKey);
    final List<String> knowledge = _resolveLocalizedList(
      knowledgePaths,
      localeKey,
    );

    return GameInfo(
      id: id,
      slug: slug,
      title: content.title,
      subtitle: content.subtitle,
      editionLabel:
          editionLabels[localeKey] ??
          editionLabels['en'] ??
          editionLabels['zhHans'],
      coverAssetPath: _assetPath(coverAsset),
      bannerAssetPath: _assetPath(bannerAsset),
      galleryAssetPaths: _resolveAssetList(galleryAssets),
      cardAccent: cardAccent,
      score: score,
      scoreCountLabel: content.scoreCountLabel,
      releaseYear: content.releaseYear,
      categoryLine: content.categoryLine,
      learningDifficulty: content.learningDifficulty,
      perPlayerTime: content.perPlayerTime,
      setupTime: content.setupTime,
      languageRequirement: content.languageRequirement,
      supportedPlayers: supportedPlayers,
      recommendedPlayer: recommendedPlayer,
      rankBadges: content.rankBadges,
      rulebookAssetPath: _assetPath(rulebookPath),
      faqAssetPath: _assetPath(faqPath),
      knowledgeAssetPaths: _resolveAssetList(knowledge),
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
    if (relativeOrAbsolutePath.trim().isEmpty) {
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

  static Map<String, String> _localizedStringMap(dynamic value) {
    final Map<String, dynamic> map =
        value as Map<String, dynamic>? ?? <String, dynamic>{};
    return map.map((key, dynamic value) => MapEntry(key, value as String));
  }

  static Map<String, List<String>> _localizedStringListMap(dynamic value) {
    final Map<String, dynamic> map =
        value as Map<String, dynamic>? ?? <String, dynamic>{};
    return map.map((key, dynamic value) => MapEntry(key, _stringList(value)));
  }

  static List<String> _stringList(dynamic value) {
    final List<dynamic> list = value as List<dynamic>? ?? const <dynamic>[];
    return list.map((item) => item as String).toList();
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

  factory GameLocaleContent.fromJson(Map<String, dynamic> json) {
    return GameLocaleContent(
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      scoreCountLabel: json['scoreCountLabel'] as String? ?? '',
      releaseYear: json['releaseYear'] as String? ?? '',
      categoryLine: json['categoryLine'] as String? ?? '',
      learningDifficulty: json['learningDifficulty'] as String? ?? '',
      perPlayerTime: json['perPlayerTime'] as String? ?? '',
      setupTime: json['setupTime'] as String? ?? '',
      languageRequirement: json['languageRequirement'] as String? ?? '',
      rankBadges: GameManifest._stringList(json['rankBadges']),
      heroTagline: json['heroTagline'] as String? ?? '',
      assistantIntro: json['assistantIntro'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      mentorPitch: json['mentorPitch'] as String? ?? '',
      playTime: json['playTime'] as String? ?? '',
      playerCount: json['playerCount'] as String? ?? '',
      complexity: json['complexity'] as String? ?? '',
      roundFlow: GameManifest._stringList(json['roundFlow']),
      assistantSkills: GameManifest._stringList(json['assistantSkills']),
      quickPrompts: GameManifest._stringList(json['quickPrompts']),
    );
  }
}
