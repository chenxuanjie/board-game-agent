import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_motion.dart';

import '../../features/games/models/game_info.dart';
import '../../features/games/models/game_metadata_text.dart';
import '../../features/games/services/related_game_recommender.dart';
import '../../app/state/app_controller.dart';
import 'desktop_resolved_image.dart';
import 'content_primitives.dart';
import 'desktop_responsive.dart';
import 'theme.dart';
import '../shared/hover_horizontal_scrollbar.dart';
import '../shared/favorite_feedback.dart';
import '../shared/content_entrance.dart';
import '../shared/game_comments.dart';

class DesktopGameDetailPane extends StatefulWidget {
  const DesktopGameDetailPane({
    super.key,
    required this.controller,
    required this.game,
    required this.backTooltip,
    required this.onBack,
    required this.onOpenRules,
    required this.onAskAi,
    required this.onToggleFavorite,
    required this.onOpenGame,
    this.coverKey,
    this.favoriteSaving = false,
  });

  final AppController controller;
  final GameInfo game;
  final String backTooltip;
  final VoidCallback onBack;
  final VoidCallback onOpenRules;
  final VoidCallback onAskAi;
  final ValueChanged<GameInfo> onToggleFavorite;
  final ValueChanged<GameInfo> onOpenGame;
  final Key? coverKey;
  final bool favoriteSaving;

  @override
  State<DesktopGameDetailPane> createState() => _DesktopGameDetailPaneState();
}

class _DesktopGameDetailPaneState extends State<DesktopGameDetailPane> {
  int _tab = 0;
  int get _galleryIndex =>
      widget.controller.gameGalleryIndex(game, _galleryPaths());

  static const _tabs = ['游戏介绍', '规则摘要'];

  @override
  void didUpdateWidget(covariant DesktopGameDetailPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.game.id != widget.game.id) {
      _tab = 0;
    }
  }

  GameInfo get game => widget.game;
  String value(String text) => desktopContentValue(text);

  void _selectGalleryImage(int index, int count) {
    if (count <= 0 || index < 0 || index >= count || index == _galleryIndex) {
      return;
    }
    _persistGalleryImage(_galleryPaths()[index]);
    setState(() {});
  }

  void _persistGalleryImage(String path) {
    unawaited(
      widget.controller.rememberGameGalleryImage(game, path).catchError((
        Object _,
      ) {
        if (!mounted) return;
        final copy = widget.controller.copy;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              copy.localized('图片位置未保存', 'Image position was not saved'),
            ),
            action: SnackBarAction(
              label: copy.localized('重试', 'Retry'),
              onPressed: () {
                if (!mounted) return;
                final paths = _galleryPaths();
                if (paths.isNotEmpty) {
                  _persistGalleryImage(paths[_galleryIndex]);
                }
              },
            ),
          ),
        );
      }),
    );
  }

  void _stepGallery(int delta, int count) {
    if (count <= 1) return;
    final next = (_galleryIndex + delta + count) % count;
    _selectGalleryImage(next, count);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey<String>('desktop-game-detail'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ContentEntrance(key: ValueKey(game.id), child: _hero()),
        _gallery(),
        Container(
          margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
          decoration: BoxDecoration(
            color: DesktopColors.card,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: DesktopColors.line),
          ),
          child: Column(
            children: [
              LayoutBuilder(
                builder: (context, constraints) => constraints.maxWidth < 650
                    ? SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(width: 650, child: _tabBar()),
                      )
                    : _tabBar(),
              ),
              AnimatedSwitcher(
                duration: AppMotion.duration(context, AppMotion.menu),
                child: Padding(
                  key: ValueKey<int>(_tab),
                  padding: const EdgeInsets.all(16),
                  child: _tabBody(),
                ),
              ),
            ],
          ),
        ),
        _relatedSection(),
        Container(
          key: const ValueKey('desktop-game-comments-section'),
          margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: DesktopColors.card,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: DesktopColors.line),
          ),
          child: GameCommentsPanel(
            key: ValueKey('comments-${game.slug}'),
            gameSlug: game.slug,
            gameTitle: game.title,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _hero() {
    final paths = _galleryPaths();
    final galleryIndex = paths.isEmpty
        ? 0
        : _galleryIndex.clamp(0, paths.length - 1).toInt();
    final heroPath = paths.isEmpty ? '' : paths[galleryIndex];
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = DesktopMetricsScope.of(context);
        final condensed =
            constraints.maxWidth < DesktopResponsive.narrowBreakpoint;
        final showTags = constraints.maxWidth >= 1100;
        final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
        final imageHeight = DesktopResponsive.detailHeroHeightFor(
          constraints.maxWidth,
        );
        final minimumHeight = metrics.px(condensed ? 360 : 440) * textScale;
        return Focus(
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent && paths.length > 1) {
              if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                _stepGallery(-1, paths.length);
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                _stepGallery(1, paths.length);
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: SizedBox(
            key: widget.coverKey,
            height: imageHeight > minimumHeight ? imageHeight : minimumHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                DesktopResolvedImage(
                  key: ValueKey<String>(
                    'desktop-detail-gallery-image-$galleryIndex',
                  ),
                  controller: widget.controller,
                  assetPath: heroPath,
                  palette: widget.controller.palette,
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0xB319110D),
                        Color(0x6718100D),
                        Color(0x0018100D),
                      ],
                      stops: [0, .4, 1],
                    ),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x1A000000),
                        Colors.transparent,
                        Color(0x99000000),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: metrics.insets(
                    condensed
                        ? const EdgeInsets.fromLTRB(20, 16, 20, 16)
                        : const EdgeInsets.fromLTRB(34, 24, 32, 24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _RoundIcon(
                            icon: Icons.arrow_back_rounded,
                            tooltip: widget.backTooltip,
                            onTap: widget.onBack,
                          ),
                        ],
                      ),
                      const Spacer(),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: metrics.px(640)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              key: const ValueKey('desktop-detail-title'),
                              value(game.title),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: metrics.font(condensed ? 34 : 42),
                                height: 1.15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (game.subtitle.trim().isNotEmpty &&
                                game.subtitle.trim() != game.title.trim()) ...[
                              SizedBox(height: metrics.px(4)),
                              Text(
                                value(game.subtitle),
                                style: TextStyle(
                                  color: Color(0xFFF2E7DF),
                                  fontSize: metrics.font(condensed ? 16 : 19),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            if (game.heroTagline.trim().isNotEmpty &&
                                game.heroTagline.trim() !=
                                    game.summary.trim()) ...[
                              SizedBox(height: metrics.px(condensed ? 10 : 16)),
                              Text(
                                '“ ${value(game.heroTagline)} ”',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: metrics.font(condensed ? 14 : 16),
                                  height: 1.45,
                                ),
                              ),
                            ],
                            SizedBox(height: metrics.px(condensed ? 12 : 18)),
                            Row(
                              children: [
                                Icon(
                                  Icons.star_rounded,
                                  color: Color(0xFFFFD12D),
                                  size: metrics.px(condensed ? 24 : 28),
                                ),
                                SizedBox(width: metrics.px(7)),
                                Text(
                                  value(game.score),
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: metrics.font(condensed ? 22 : 26),
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                SizedBox(width: metrics.px(10)),
                                Flexible(
                                  child: Text(
                                    '(${value(game.scoreCountLabel)})',
                                    style: TextStyle(
                                      color: Color(0xFFD9CEC7),
                                      fontSize: metrics.font(
                                        condensed ? 11 : 13,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: metrics.px(condensed ? 12 : 20)),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: metrics.px(480),
                              ),
                              child: LayoutBuilder(
                                builder: (context, bounds) {
                                  final columns = textScale > 1.4 ? 2 : 3;
                                  final width = bounds.maxWidth / columns;
                                  return Wrap(
                                    runSpacing: metrics.px(12),
                                    children: [
                                      _HeroMetric(
                                        Icons.group_rounded,
                                        GameMetadataText.players(
                                          game.playerCount,
                                        ),
                                        '推荐人数',
                                        width: width,
                                        compact: condensed,
                                      ),
                                      _HeroMetric(
                                        Icons.schedule_rounded,
                                        GameMetadataText.playTime(
                                          game.playTime,
                                        ),
                                        '游戏时长',
                                        width: width,
                                        compact: condensed,
                                      ),
                                      _HeroMetric(
                                        Icons.bar_chart_rounded,
                                        value(game.complexity),
                                        '游戏难度',
                                        width: width,
                                        compact: condensed,
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                            if (showTags) ...[
                              const SizedBox(height: 15),
                              Wrap(
                                spacing: 7,
                                runSpacing: 7,
                                children: [
                                  for (final tag in _tags().take(6))
                                    _HeroTag(tag),
                                ],
                              ),
                            ],
                            SizedBox(height: metrics.px(18)),
                            Wrap(
                              spacing: metrics.px(14),
                              runSpacing: metrics.px(12),
                              children: [
                                _HeroButton(
                                  key: const ValueKey<String>(
                                    'desktop-detail-favorite-button',
                                  ),
                                  label: widget.controller.isFavorite(game)
                                      ? '已喜欢'
                                      : '喜欢',
                                  icon: widget.controller.isFavorite(game)
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  onTap: widget.favoriteSaving
                                      ? null
                                      : () => widget.onToggleFavorite(game),
                                  busy: widget.favoriteSaving,
                                  pendingLabel: widget.controller.copy
                                      .localized('保存中', 'Saving'),
                                  width: condensed ? 128 : 144,
                                  compact: condensed,
                                ),
                                _HeroButton(
                                  label: '询问 AI',
                                  icon: Icons.auto_awesome_rounded,
                                  onTap: widget.onAskAi,
                                  light: true,
                                  compact: condensed,
                                  width: condensed ? 120 : 134,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<String> _tags() {
    final tags = <String>{...game.keywords};
    if (game.categoryLine.trim().isNotEmpty) tags.add(game.categoryLine);
    if (tags.isEmpty) tags.add('-');
    return tags.toList();
  }

  List<String> _galleryPaths() {
    final paths = <String>{};
    if (game.bannerAssetPath.trim().isNotEmpty) {
      paths.add(game.bannerAssetPath);
    }
    paths.addAll(
      game.galleryAssetPaths.where((path) => path.trim().isNotEmpty),
    );
    if (game.coverAssetPath.trim().isNotEmpty) paths.add(game.coverAssetPath);
    return paths.toList();
  }

  Widget _gallery() {
    final paths = _galleryPaths();
    if (paths.isEmpty) {
      return const SizedBox(
        height: 96,
        child: Center(
          child: Text(
            '暂无图片',
            style: TextStyle(color: DesktopColors.secondaryText),
          ),
        ),
      );
    }
    return Container(
      height: 108,
      color: const Color(0xFFFFF9F2),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: paths.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) => Tooltip(
          message: '查看第 ${index + 1} 张图片',
          child: Semantics(
            button: true,
            selected: index == _galleryIndex,
            label: '第 ${index + 1} 张图片',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: InkWell(
                key: ValueKey<String>(
                  'desktop-detail-gallery-thumbnail-$index',
                ),
                onTap: () => _selectGalleryImage(index, paths.length),
                borderRadius: BorderRadius.circular(9),
                child: Container(
                  width: 146,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: index == _galleryIndex
                          ? DesktopColors.orange
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: DesktopResolvedImage(
                      controller: widget.controller,
                      assetPath: paths[index],
                      palette: widget.controller.palette,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabBar() => Row(
    children: [
      for (var index = 0; index < _tabs.length; index++)
        Expanded(
          child: InkWell(
            key: ValueKey<String>('detail-tab-$index'),
            onTap: () => setState(() => _tab = index),
            child: AnimatedContainer(
              duration: AppMotion.duration(context, AppMotion.exit),
              height: 57,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: index == _tab
                        ? DesktopColors.orange
                        : DesktopColors.line,
                    width: index == _tab ? 2 : 1,
                  ),
                ),
              ),
              child: Text(
                _tabs[index],
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: index == _tab ? FontWeight.w800 : FontWeight.w500,
                  color: index == _tab
                      ? DesktopColors.text
                      : DesktopColors.secondaryText,
                ),
              ),
            ),
          ),
        ),
    ],
  );

  Widget _tabBody() => switch (_tab) {
    0 => _introduction(),
    1 => _rules(),
    _ => const SizedBox.shrink(),
  };

  Widget _relatedSection() => Container(
    key: const ValueKey<String>('desktop-related-games-section'),
    margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: DesktopColors.card,
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: DesktopColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '相关游戏',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 14),
        _relatedGames(),
      ],
    ),
  );

  Widget _relatedGames() {
    final results = const RelatedGameRecommender().recommend(
      source: game,
      catalog: widget.controller.games,
    );
    if (results.isEmpty) {
      return const SizedBox(height: 120, child: Center(child: Text('暂无其他游戏')));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return HoverHorizontalScrollbar(
          enabled: true,
          keyPrefix: 'desktop-detail-related',
          builder: (scrollController) => SingleChildScrollView(
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final result in results)
                  Padding(
                    padding: EdgeInsets.only(
                      right: result == results.last ? 0 : 12,
                    ),
                    child: SizedBox(
                      width: width,
                      child: InkWell(
                        key: ValueKey<String>('related-game-${result.game.id}'),
                        onTap: () => widget.onOpenGame(result.game),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFCF9),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: DesktopColors.line),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: SizedBox(
                                  width: 62,
                                  height: 82,
                                  child: DesktopResolvedImage(
                                    controller: widget.controller,
                                    assetPath: result.game.coverAssetPath,
                                    palette: widget.controller.palette,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      result.game.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      _relatedReason(result.reason),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: DesktopColors.secondaryText,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      result.game.score,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: DesktopColors.orange,
                                        fontWeight: FontWeight.w700,
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
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _relatedReason(String reason) => switch (reason) {
    'players' => '适合相近人数',
    'difficulty' => '难度相近',
    'rating' => '按评分推荐',
    _ => '共同特色：$reason',
  };

  Widget _introduction() => LayoutBuilder(
    builder: (context, constraints) {
      final description = value(
        game.summary.trim().isNotEmpty ? game.summary : game.mentorPitch,
      );
      final copy = _IntroCopy(
        title: game.title,
        description: description,
        game: game,
        controller: widget.controller,
      );
      final highlights = _Highlights(game: game);
      if (constraints.maxWidth < 760) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [copy, const SizedBox(height: 14), highlights],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: copy),
          const SizedBox(width: 14),
          Expanded(flex: 2, child: highlights),
        ],
      );
    },
  );

  Widget _rules() {
    final available = game.resources
        .where(
          (resource) =>
              resource.enabled &&
              resource.isAvailable &&
              resource.isRenderableDocument,
        )
        .toList();
    final labels = available.isEmpty
        ? <String>['暂无可用规则资料']
        : available.map((resource) => resource.fileName).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '规则资料',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            if (available.isNotEmpty) ...[
              const SizedBox(width: 10),
              Text(
                '${available.length} 份',
                style: const TextStyle(color: DesktopColors.secondaryText),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        for (final label in labels.take(5))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                const Icon(
                  Icons.description_outlined,
                  size: 17,
                  color: DesktopColors.orange,
                ),
                const SizedBox(width: 7),
                Expanded(child: Text(label)),
              ],
            ),
          ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: widget.onOpenRules,
          icon: const Icon(Icons.menu_book_rounded),
          label: const Text('打开规则资料'),
        ),
      ],
    );
  }
}

class _IntroCopy extends StatelessWidget {
  const _IntroCopy({
    required this.title,
    required this.description,
    required this.game,
    required this.controller,
  });
  final String title;
  final String description;
  final GameInfo game;
  final AppController controller;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFFCF9),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: DesktopColors.line),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 112,
            height: 150,
            child: DesktopResolvedImage(
              controller: controller,
              assetPath: game.coverAssetPath,
              palette: controller.palette,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$title · 游戏介绍',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.75,
                  color: Color(0xFF625851),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '设计师：${game.designers.isEmpty ? '-' : game.designers.join('、')}',
                style: const TextStyle(
                  fontSize: 11,
                  color: DesktopColors.secondaryText,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '发行：${game.publishers.isEmpty ? '-' : game.publishers.join('、')}',
                style: const TextStyle(
                  fontSize: 11,
                  color: DesktopColors.secondaryText,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Highlights extends StatelessWidget {
  const _Highlights({required this.game});
  final GameInfo game;
  @override
  Widget build(BuildContext context) {
    final data = <(IconData, String, String)>[
      (
        Icons.casino_outlined,
        '回合流程',
        game.roundFlow.isEmpty ? '-' : game.roundFlow.first,
      ),
      (
        Icons.psychology_alt_outlined,
        '学习难度',
        desktopContentValue(game.learningDifficulty),
      ),
      (
        Icons.translate_rounded,
        '语言需求',
        desktopContentValue(game.languageRequirement),
      ),
      (
        Icons.workspace_premium_outlined,
        '版本',
        game.editionLabel?.trim().isNotEmpty == true ? game.editionLabel! : '-',
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F5EF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '游戏亮点',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.25,
            children: [
              for (final item in data)
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: DesktopColors.line),
                  ),
                  child: Row(
                    children: [
                      Icon(item.$1, size: 19, color: DesktopColors.orange),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.$2,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              item.$3,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 9,
                                color: DesktopColors.secondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric(
    this.icon,
    this.value,
    this.label, {
    required this.width,
    required this.compact,
  });
  final IconData icon;
  final String value;
  final String label;
  final double width;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final metrics = DesktopMetricsScope.of(context);
    return Container(
      width: width,
      padding: EdgeInsets.only(right: metrics.px(16)),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Color(0x55FFFFFF))),
      ),
      child: Row(
        children: [
          Icon(icon, size: metrics.px(compact ? 20 : 24), color: Colors.white),
          SizedBox(width: metrics.px(10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 2,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: metrics.font(compact ? 14 : 16),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    color: Color(0xFFD7CBC3),
                    fontSize: metrics.font(compact ? 10 : 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroTag extends StatelessWidget {
  const _HeroTag(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0x553D2C24),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0x66FFFFFF)),
    ),
    child: Text(
      label,
      style: const TextStyle(color: Colors.white, fontSize: 10),
    ),
  );
}

class _HeroButton extends StatefulWidget {
  const _HeroButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.light = false,
    this.width,
    this.busy = false,
    this.pendingLabel,
    this.compact = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool busy;
  final String? pendingLabel;
  final bool light;
  final double? width;
  final bool compact;
  @override
  State<_HeroButton> createState() => _HeroButtonState();
}

class _HeroButtonState extends State<_HeroButton> {
  bool hover = false;
  bool? _confirmed;
  @override
  Widget build(BuildContext context) {
    final metrics = DesktopMetricsScope.of(context);
    final heart =
        widget.icon == Icons.favorite_rounded ||
        widget.icon == Icons.favorite_border_rounded;
    _confirmed ??= widget.icon == Icons.favorite_rounded;
    if (!widget.busy) _confirmed = widget.icon == Icons.favorite_rounded;
    final color = widget.light ? const Color(0xFF59463B) : Colors.white;
    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(11),
        child: AnimatedContainer(
          duration: AppMotion.duration(context),
          curve: AppMotion.curve,
          transform: Matrix4.translationValues(
            0,
            hover && !AppMotion.reduced(context) && !widget.busy ? -2 : 0,
            0,
          ),
          constraints: BoxConstraints(minWidth: metrics.px(widget.width ?? 0)),
          height: metrics.px(widget.compact ? 48 : 56),
          padding: EdgeInsets.symmetric(horizontal: metrics.px(20)),
          decoration: BoxDecoration(
            color: widget.light
                ? const Color(0xEFFCF7F3)
                : DesktopColors.orange,
            borderRadius: BorderRadius.circular(metrics.radius(12)),
            boxShadow: hover
                ? const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: widget.busy ? 0 : 1,
                    child: heart
                        ? FavoriteFeedbackIcon(
                            selected: _confirmed!,
                            color: color,
                            size: metrics.px(24),
                          )
                        : Icon(widget.icon, color: color, size: metrics.px(24)),
                  ),
                  if (widget.busy)
                    SizedBox(
                      width: metrics.px(24),
                      height: metrics.px(24),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: color,
                      ),
                    ),
                ],
              ),
              SizedBox(width: metrics.px(10)),
              Text(
                widget.busy
                    ? widget.pendingLabel ?? widget.label
                    : widget.label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: metrics.font(widget.compact ? 14 : 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: IconButton(
      onPressed: onTap,
      style: IconButton.styleFrom(
        backgroundColor: const Color(0x9953443B),
        foregroundColor: Colors.white,
      ),
      icon: Icon(icon),
    ),
  );
}
