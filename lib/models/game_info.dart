class GameInfo {
  factory GameInfo.empty() {
    return GameInfo(
      id: '__empty__',
      slug: '__empty__',
      title: '暂无游戏',
      subtitle: '游戏资料尚未加载',
      coverAssetPath: '',
      bannerAssetPath: '',
      galleryAssetPaths: const <String>[],
      cardAccent: 0xFF607D8B,
      score: '—',
      scoreCountLabel: '',
      releaseYear: '',
      categoryLine: '',
      learningDifficulty: '',
      perPlayerTime: '',
      setupTime: '',
      languageRequirement: '',
      supportedPlayers: const <int>[],
      recommendedPlayer: 0,
      rankBadges: const <String>[],
      rulebookAssetPath: '',
      faqAssetPath: '',
      knowledgeAssetPaths: const <String>[],
      heroTagline: '',
      assistantIntro: '',
      summary: '',
      mentorPitch: '',
      playTime: '',
      playerCount: '',
      complexity: '',
      roundFlow: const <String>[],
      assistantSkills: const <String>[],
      quickPrompts: const <String>[],
    );
  }

  GameInfo({
    required this.id,
    required this.slug,
    required this.title,
    required this.subtitle,
    this.editionLabel,
    required this.coverAssetPath,
    required this.bannerAssetPath,
    List<String>? galleryAssetPaths,
    required this.cardAccent,
    required this.score,
    required this.scoreCountLabel,
    required this.releaseYear,
    required this.categoryLine,
    required this.learningDifficulty,
    required this.perPlayerTime,
    required this.setupTime,
    required this.languageRequirement,
    required this.supportedPlayers,
    required this.recommendedPlayer,
    required this.rankBadges,
    required this.rulebookAssetPath,
    required this.faqAssetPath,
    List<String>? knowledgeAssetPaths,
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
  }) : galleryAssetPaths = List<String>.unmodifiable(
         galleryAssetPaths ?? <String>[coverAssetPath, bannerAssetPath],
       ),
       knowledgeAssetPaths = List<String>.unmodifiable(
         knowledgeAssetPaths ?? <String>[rulebookAssetPath, faqAssetPath],
       );

  final String id;
  final String slug;
  final String title;
  final String subtitle;
  final String? editionLabel;
  final String coverAssetPath;
  final String bannerAssetPath;
  final List<String> galleryAssetPaths;
  final int cardAccent;
  final String score;
  final String scoreCountLabel;
  final String releaseYear;
  final String categoryLine;
  final String learningDifficulty;
  final String perPlayerTime;
  final String setupTime;
  final String languageRequirement;
  final List<int> supportedPlayers;
  final int recommendedPlayer;
  final List<String> rankBadges;
  final String rulebookAssetPath;
  final String faqAssetPath;
  final List<String> knowledgeAssetPaths;
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
}
