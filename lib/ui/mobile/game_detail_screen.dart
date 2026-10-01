import 'package:flutter/material.dart';
import '../../core/theme/app_motion.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import '../../app/state/app_controller.dart';
import '../../features/games/models/game_info.dart';
import '../../features/games/models/game_metadata_text.dart';
import '../../features/games/services/related_game_recommender.dart';
import '../../features/library/models/resolved_document.dart';
import '../shared/documents/document_viewer_launcher.dart';
import 'assistant_chat_screen.dart';
import 'game_cover.dart';
import '../shared/hover_carousel_controls.dart';
import '../shared/hover_horizontal_scrollbar.dart';

const _ink = Color(0xFF271D1B);
const _muted = Color(0xFF817B7A);
const _orange = Color(0xFFE9772E);
const _cream = Color(0xFFFFF3E4);

class GameDetailScreen extends StatefulWidget {
  const GameDetailScreen({
    super.key,
    required this.controller,
    required this.game,
  });

  final AppController controller;
  final GameInfo game;

  @override
  State<GameDetailScreen> createState() => _GameDetailScreenState();
}

class _GameDetailScreenState extends State<GameDetailScreen> {
  late final PageController _galleryController;
  int _galleryIndex = 0;
  bool _openingRulebook = false;

  @override
  void initState() {
    super.initState();
    _galleryController = PageController(viewportFraction: 0.88);
    widget.controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant GameDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _galleryController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _stepGalleryPage(int delta, int count) {
    if (count <= 1 || !_galleryController.hasClients) return;
    final next = (_galleryIndex + delta + count) % count;
    if (AppMotion.reduced(context)) {
      _galleryController.jumpToPage(next);
    } else {
      _galleryController.animateToPage(
        next,
        duration: AppMotion.scroll,
        curve: AppMotion.curve,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final copy = controller.copy;
    final game = widget.game;
    final gallery = game.galleryAssetPaths.isEmpty
        ? [game.coverAssetPath]
        : game.galleryAssetPaths;
    final tags = game.categoryLine
        .split(RegExp(r'[/／,，·]'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    final summary = game.summary.trim().isEmpty ? '-' : game.summary;

    return Scaffold(
      key: const ValueKey('mobile-game-detail'),
      backgroundColor: const Color(0xFFFFFBF7),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    children: [
                      _roundButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        tooltip: copy.localized('返回', 'Back'),
                        onTap: () => Navigator.of(context).pop(),
                      ),
                      const Spacer(),
                      _roundButton(
                        key: ValueKey('mobile-detail-favorite-${game.id}'),
                        icon: controller.isFavorite(game)
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        iconColor: _orange,
                        tooltip: controller.isFavorite(game)
                            ? copy.localized('取消喜欢', 'Unlike')
                            : copy.localized('喜欢', 'Like'),
                        onTap: () async {
                          final saved = await controller.toggleFavorite(game);
                          if (!saved && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  copy.localized(
                                    '收藏保存失败',
                                    'Could not save favorite',
                                  ),
                                ),
                              ),
                            );
                          }
                        },
                      ),
                      const SizedBox(width: 6),
                      _roundButton(
                        asset: 'assets/mobile/detail/share.png',
                        tooltip: copy.localized('分享', 'Share'),
                        onTap: () async {
                          await Clipboard.setData(
                            ClipboardData(
                              text: '${game.title} — ${game.subtitle}',
                            ),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  copy.localized('已复制游戏信息', 'Game info copied'),
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    key: const ValueKey('mobile-game-detail-scroll'),
                    padding: const EdgeInsets.only(bottom: 18),
                    children: [
                      SizedBox(
                        height: (MediaQuery.sizeOf(context).width * 0.92).clamp(
                          270.0,
                          480.0,
                        ),
                        child: HoverCarouselControls(
                          enabled: kIsWeb && gallery.length > 1,
                          keyPrefix: 'mobile-detail-gallery',
                          onPrevious: () =>
                              _stepGalleryPage(-1, gallery.length),
                          onNext: () => _stepGalleryPage(1, gallery.length),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              PageView.builder(
                                controller: _galleryController,
                                itemCount: gallery.length,
                                onPageChanged: (index) =>
                                    setState(() => _galleryIndex = index),
                                itemBuilder: (context, index) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(22),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        _GalleryAsset(
                                          controller: controller,
                                          game: game,
                                          path: gallery[index],
                                        ),
                                        if (gallery.length > 1)
                                          Positioned(
                                            bottom: 12,
                                            left: 0,
                                            right: 0,
                                            child: Center(
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 7,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.black45,
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: List.generate(
                                                    gallery.length,
                                                    (dot) => AnimatedContainer(
                                                      duration:
                                                          AppMotion.duration(
                                                            context,
                                                          ),
                                                      margin:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 3,
                                                          ),
                                                      width:
                                                          dot == _galleryIndex
                                                          ? 18
                                                          : 6,
                                                      height: 6,
                                                      decoration: BoxDecoration(
                                                        color:
                                                            dot == _galleryIndex
                                                            ? Colors.white
                                                            : Colors.white54,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              6,
                                                            ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 17),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: RichText(
                                    text: TextSpan(
                                      children: [
                                        TextSpan(
                                          text: game.title,
                                          style: const TextStyle(
                                            fontSize: 27,
                                            fontWeight: FontWeight.w900,
                                            color: _ink,
                                          ),
                                        ),
                                        if (game.subtitle.trim().isNotEmpty &&
                                            game.subtitle.trim() !=
                                                game.title.trim())
                                          TextSpan(
                                            text: '  ${game.subtitle}',
                                            style: const TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w600,
                                              color: _muted,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.star_rounded,
                                  size: 28,
                                  color: _orange,
                                ),
                                Text(
                                  game.score.trim().isEmpty ? '-' : game.score,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    color: _orange,
                                  ),
                                ),
                              ],
                            ),
                            if (_isRatingCountLabel(game.scoreCountLabel))
                              Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  game.scoreCountLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: _muted,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 5),
                            Text(
                              game.categoryLine.trim().isEmpty
                                  ? (game.releaseYear.isEmpty
                                        ? '-'
                                        : game.releaseYear)
                                  : game.categoryLine,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                color: _muted,
                              ),
                            ),
                            const SizedBox(height: 14),
                            if (game.heroTagline.trim().isNotEmpty &&
                                game.heroTagline.trim() != game.summary.trim())
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(15),
                                decoration: BoxDecoration(
                                  color: _cream,
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                child: Text(
                                  game.heroTagline,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF756B64),
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF8EF),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFF4E8DA),
                                ),
                              ),
                              child: Row(
                                children: [
                                  _stat(
                                    Icons.people_alt_rounded,
                                    GameMetadataText.players(game.playerCount),
                                    copy.localized('游戏人数', 'Players'),
                                    const Color(0xFFEE8A45),
                                  ),
                                  _statDivider(),
                                  _stat(
                                    Icons.schedule_rounded,
                                    GameMetadataText.playTime(game.playTime),
                                    copy.localized('游戏时长', 'Play time'),
                                    _orange,
                                  ),
                                  _statDivider(),
                                  _stat(
                                    Icons.bar_chart_rounded,
                                    game.complexity,
                                    copy.localized('游戏难度', 'Difficulty'),
                                    const Color(0xFFF6B833),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 13),
                            if (tags.isNotEmpty)
                              Wrap(
                                spacing: 7,
                                runSpacing: 7,
                                children: tags
                                    .map(
                                      (tag) => Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _cream,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Text(
                                          tag,
                                          style: const TextStyle(
                                            color: Color(0xFFD85F2B),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    copy.localized('游戏简介', 'About this game'),
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: _ink,
                                    ),
                                  ),
                                  Text(
                                    summary,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF626166),
                                      height: 1.6,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            _relatedGames(game),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 9, 16, 10),
          decoration: const BoxDecoration(color: Color(0xFFFFFBF7)),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 588),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('mobile-detail-rules'),
                      onPressed: _openingRulebook
                          ? null
                          : () => _openDocument(game),
                      icon: _openingRulebook
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.menu_book_rounded),
                      label: Text(copy.rulesBook),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFBA5D22),
                        backgroundColor: _cream,
                        side: BorderSide.none,
                        minimumSize: const Size(0, 52),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('mobile-detail-ask-ai'),
                      onPressed: () {
                        if (!controller.openGameAssistant(game.id)) return;
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                AssistantChatScreen(controller: controller),
                          ),
                        );
                      },
                      icon: const Icon(Icons.smart_toy_outlined),
                      label: Text(copy.askAiAssistant),
                      style: FilledButton.styleFrom(
                        backgroundColor: _orange,
                        minimumSize: const Size(0, 52),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _roundButton({
    Key? key,
    IconData? icon,
    Color iconColor = const Color(0xFF78431E),
    String? asset,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Material(
      color: _cream,
      borderRadius: BorderRadius.circular(18),
      child: IconButton(
        key: key,
        tooltip: tooltip,
        onPressed: onTap,
        icon: asset == null
            ? Icon(icon, size: 21, color: iconColor)
            : _assetIcon(asset, 23),
      ),
    );
  }

  Widget _assetIcon(String path, double size) => ClipRect(
    child: SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Transform.scale(
          scale: 2.25,
          child: Image.asset(path, width: size, height: size),
        ),
      ),
    ),
  );

  Widget _statDivider() =>
      Container(width: 1, height: 32, color: const Color(0xFFF0E5D9));

  Widget _stat(IconData icon, String value, String label, Color iconColor) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 5),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value.trim().isEmpty ? '-' : value,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9, color: _muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _relatedGames(GameInfo game) {
    final copy = widget.controller.copy;
    final results = const RelatedGameRecommender().recommend(
      source: game,
      catalog: widget.controller.games,
    );
    if (results.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const ValueKey('mobile-related-games-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          copy.localized('相关游戏', 'Related games'),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: _ink,
          ),
        ),
        const SizedBox(height: 10),
        HoverHorizontalScrollbar(
          keyPrefix: 'mobile-detail-related',
          builder: (scrollController) => SizedBox(
            height: 104,
            child: ListView.separated(
              controller: scrollController,
              scrollDirection: Axis.horizontal,
              itemCount: results.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final result = results[index];
                return SizedBox(
                  width: 225,
                  child: Material(
                    color: const Color(0xFFFFF8EF),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      key: ValueKey('mobile-related-game-${result.game.id}'),
                      onTap: () => _openRelatedGame(result.game),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 63,
                                height: 88,
                                child: MobileGameCover(
                                  controller: widget.controller,
                                  game: result.game,
                                ),
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    result.game.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: _ink,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    _relatedReason(result.reason),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: _muted,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.star_rounded,
                                        size: 14,
                                        color: _orange,
                                      ),
                                      Text(
                                        result.game.score,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: _orange,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  String _relatedReason(String reason) => switch (reason) {
    'players' => widget.controller.copy.localized(
      '适合相近人数',
      'Similar player count',
    ),
    'difficulty' => widget.controller.copy.localized(
      '难度相近',
      'Similar difficulty',
    ),
    'rating' => widget.controller.copy.localized(
      '按评分推荐',
      'Recommended by rating',
    ),
    _ => widget.controller.copy.localized(
      '共同特色：$reason',
      'Shared trait: $reason',
    ),
  };

  Future<void> _openRelatedGame(GameInfo game) async {
    final currentGameId = widget.game.id;
    widget.controller.selectGame(game.id);
    await widget.controller.recordRecentlyViewed(game);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            GameDetailScreen(controller: widget.controller, game: game),
      ),
    );
    if (mounted) widget.controller.selectGame(currentGameId);
  }

  Future<void> _openDocument(GameInfo game) async {
    final controller = widget.controller;
    final title = controller.copy.rulesBook;
    setState(() => _openingRulebook = true);
    try {
      final ResolvedDocument? document = await controller
          .resolveRulebookDocument(game);
      if (!mounted) return;
      if (document == null) {
        _documentUnavailable(title, () => _openDocument(game));
        return;
      }
      await DocumentViewerLauncher.open(
        context,
        controller: controller,
        document: document,
        title: title,
      );
    } catch (_) {
      if (mounted) {
        _documentUnavailable(title, () => _openDocument(game));
      }
    } finally {
      if (mounted) {
        setState(() => _openingRulebook = false);
      }
    }
  }

  bool _isRatingCountLabel(String value) {
    return RegExp(
      r'^\d[\d,.]*(?:\s*(?:万|亿|[kKmM]))?\s*(?:人打分|人评分|评分人数|ratings?|votes?)$',
      caseSensitive: false,
    ).hasMatch(value.trim());
  }

  void _documentUnavailable(String title, VoidCallback retry) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(widget.controller.copy.documentUnavailable(title)),
          action: SnackBarAction(
            label: widget.controller.copy.retry,
            onPressed: retry,
          ),
        ),
      );
  }
}

class _GalleryAsset extends StatelessWidget {
  const _GalleryAsset({
    required this.controller,
    required this.game,
    required this.path,
  });

  final AppController controller;
  final GameInfo game;
  final String path;

  @override
  Widget build(BuildContext context) {
    if (path.isEmpty) {
      return MobileGameCover(controller: controller, game: game);
    }
    return Image.asset(
      path,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) =>
          MobileGameCover(controller: controller, game: game),
    );
  }
}
