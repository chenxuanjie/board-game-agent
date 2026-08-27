import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/game_info.dart';
import '../../models/resolved_document.dart';
import '../../state/app_controller.dart';
import '../../theme/app_palette.dart';
import 'markdown_document_screen.dart';
import 'pdf_document_screen.dart';

/// Wide-screen game details for the Windows workspace.
///
/// The mobile-style [GameDetailScreen] remains unchanged for Android and Web.
/// This pane is deliberately limited to the desktop workspace, where the
/// product currently provides rule lookup and an AI assistant rather than a
/// playable game table.
class DesktopGameDetailPane extends StatefulWidget {
  const DesktopGameDetailPane({
    super.key,
    required this.controller,
    required this.game,
    required this.onBack,
    required this.onAskAi,
  });

  final AppController controller;
  final GameInfo game;
  final VoidCallback onBack;
  final VoidCallback onAskAi;

  @override
  State<DesktopGameDetailPane> createState() => _DesktopGameDetailPaneState();
}

enum _DesktopDetailSection { overview, rules, faq, gallery }

class _DesktopGameDetailPaneState extends State<DesktopGameDetailPane> {
  late final PageController _galleryController;
  int _galleryIndex = 0;
  _DesktopDetailSection _section = _DesktopDetailSection.overview;
  bool _openingRulebook = false;
  bool _openingFaq = false;

  @override
  void initState() {
    super.initState();
    _galleryController = PageController();
  }

  @override
  void dispose() {
    _galleryController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DesktopGameDetailPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.game.id != widget.game.id) {
      _galleryIndex = 0;
      _section = _DesktopDetailSection.overview;
      if (_galleryController.hasClients) {
        _galleryController.jumpToPage(0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppController controller = widget.controller;
    if (!controller.hasGames) {
      return const Center(child: Text('暂无可用的桌游资料'));
    }

    final AppPalette palette = AppPalette.of(context);
    final GameInfo game = widget.game;
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 34),
      children: <Widget>[
        _DesktopBreadcrumb(
          gameTitle: game.title,
          palette: palette,
          onBack: widget.onBack,
        ),
        const SizedBox(height: 18),
        _buildHero(context, game, palette),
        const SizedBox(height: 24),
        _DesktopDetailTabs(
          selected: _section,
          palette: palette,
          onSelected: (value) => setState(() => _section = value),
        ),
        const SizedBox(height: 18),
        _buildSection(context, game, palette),
      ],
    );
  }

  Widget _buildHero(BuildContext context, GameInfo game, AppPalette palette) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wide = constraints.maxWidth >= 1050;
        final bool medium = constraints.maxWidth >= 760;
        final Widget cover = _DesktopGameGallery(
          controller: widget.controller,
          game: game,
          palette: palette,
          galleryController: _galleryController,
          currentIndex: _galleryIndex,
          onPageChanged: (int value) => setState(() => _galleryIndex = value),
        );
        final Widget copy = _DesktopHeroCopy(
          controller: widget.controller,
          game: game,
          palette: palette,
          onAskAi: widget.onAskAi,
          onOpenRulebook: () => _openRulebook(game),
          onOpenFaq: () => _openFaq(game),
          openingRulebook: _openingRulebook,
          openingFaq: _openingFaq,
        );
        final Widget score = _DesktopScoreCard(game: game, palette: palette);

        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(width: 248, height: 280, child: cover),
              const SizedBox(width: 22),
              Expanded(child: copy),
              const SizedBox(width: 22),
              SizedBox(width: 220, height: 280, child: score),
            ],
          );
        }
        if (medium) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(width: 220, height: 250, child: cover),
                  const SizedBox(width: 18),
                  Expanded(child: copy),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(height: 150, child: score),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(height: 280, child: cover),
            const SizedBox(height: 18),
            copy,
            const SizedBox(height: 16),
            SizedBox(height: 150, child: score),
          ],
        );
      },
    );
  }

  Widget _buildSection(
    BuildContext context,
    GameInfo game,
    AppPalette palette,
  ) {
    switch (_section) {
      case _DesktopDetailSection.overview:
        return _DesktopOverview(
          controller: widget.controller,
          game: game,
          palette: palette,
          onAskAi: widget.onAskAi,
          onOpenRulebook: () => _openRulebook(game),
          onOpenFaq: () => _openFaq(game),
          openingRulebook: _openingRulebook,
          openingFaq: _openingFaq,
        );
      case _DesktopDetailSection.rules:
        return _DesktopDocumentPanel(
          title: '规则书',
          description: '在桌面端打开完整规则书，阅读时仍可随时返回询问 AI。',
          icon: Icons.menu_book_rounded,
          palette: palette,
          isLoading: _openingRulebook,
          onOpen: () => _openRulebook(game),
          buttonLabel: '打开规则书',
        );
      case _DesktopDetailSection.faq:
        return _DesktopDocumentPanel(
          title: 'FAQ',
          description: '查看这款桌游的常见问题，并把规则疑问交给 AI 助手。',
          icon: Icons.quiz_rounded,
          palette: palette,
          isLoading: _openingFaq,
          onOpen: () => _openFaq(game),
          buttonLabel: '打开 FAQ',
        );
      case _DesktopDetailSection.gallery:
        return _DesktopGalleryGrid(
          controller: widget.controller,
          game: game,
          palette: palette,
        );
    }
  }

  Future<void> _openRulebook(GameInfo game) async {
    if (_openingRulebook) return;
    setState(() => _openingRulebook = true);
    try {
      final ResolvedDocument? document = await widget.controller
          .resolveRulebookDocument(game);
      if (!mounted || document == null) return;
      await _openResolvedDocument(document, '规则书');
    } finally {
      if (mounted) setState(() => _openingRulebook = false);
    }
  }

  Future<void> _openFaq(GameInfo game) async {
    if (_openingFaq) return;
    setState(() => _openingFaq = true);
    try {
      final ResolvedDocument? document = await widget.controller
          .resolveFaqDocument(game);
      if (!mounted || document == null) return;
      await _openResolvedDocument(document, 'FAQ');
    } finally {
      if (mounted) setState(() => _openingFaq = false);
    }
  }

  Future<void> _openResolvedDocument(
    ResolvedDocument document,
    String title,
  ) async {
    if (document.renderType == DocumentRenderType.markdown) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => MarkdownDocumentScreen(
            controller: widget.controller,
            remotePath: document.remotePath,
            title: title,
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PdfDocumentScreen(
          controller: widget.controller,
          title: title,
          remotePath: document.remotePath,
        ),
      ),
    );
  }
}

class _DesktopBreadcrumb extends StatelessWidget {
  const _DesktopBreadcrumb({
    required this.gameTitle,
    required this.palette,
    required this.onBack,
  });

  final String gameTitle;
  final AppPalette palette;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        IconButton(
          tooltip: '返回',
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 4),
        Text(
          '我的游戏',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: palette.textSecondary),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            '/',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: palette.textSecondary.withValues(alpha: 0.6),
            ),
          ),
        ),
        Expanded(
          child: Text(
            gameTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: palette.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _DesktopGameGallery extends StatelessWidget {
  const _DesktopGameGallery({
    required this.controller,
    required this.game,
    required this.palette,
    required this.galleryController,
    required this.currentIndex,
    required this.onPageChanged,
  });

  final AppController controller;
  final GameInfo game;
  final AppPalette palette;
  final PageController galleryController;
  final int currentIndex;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final List<String> paths = game.galleryAssetPaths.isEmpty
        ? <String>[game.coverAssetPath]
        : game.galleryAssetPaths;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surfaceContainer,
          border: Border.all(color: palette.outline),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: palette.shadow.withValues(alpha: 0.24),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            PageView.builder(
              controller: galleryController,
              itemCount: paths.length,
              onPageChanged: onPageChanged,
              itemBuilder: (BuildContext context, int index) {
                final String path = paths[index];
                return _DesktopResolvedImage(
                  controller: controller,
                  assetPath: path,
                  palette: palette,
                );
              },
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Colors.transparent,
                    palette.shadow.withValues(alpha: 0.46),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 14,
              bottom: 14,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.shadow.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Text(
                    currentIndex == 0 ? '封面图' : '场景图',
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: Colors.white),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 14,
              bottom: 16,
              child: Text(
                '${currentIndex + 1} / ${paths.length}',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopResolvedImage extends StatefulWidget {
  const _DesktopResolvedImage({
    required this.controller,
    required this.assetPath,
    required this.palette,
  });

  final AppController controller;
  final String assetPath;
  final AppPalette palette;

  @override
  State<_DesktopResolvedImage> createState() => _DesktopResolvedImageState();
}

class _DesktopResolvedImageState extends State<_DesktopResolvedImage> {
  late Future<String?> _pathFuture;

  @override
  void initState() {
    super.initState();
    _pathFuture = widget.controller.resolveImagePath(widget.assetPath);
  }

  @override
  void didUpdateWidget(covariant _DesktopResolvedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPath != widget.assetPath) {
      _pathFuture = widget.controller.resolveImagePath(widget.assetPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _pathFuture,
      builder: (BuildContext context, AsyncSnapshot<String?> snapshot) {
        final String? path = snapshot.data;
        if (path == null || path.isEmpty) {
          return DecoratedBox(
            decoration: BoxDecoration(color: widget.palette.surfaceVariant),
            child: Center(
              child: Icon(
                Icons.image_not_supported_outlined,
                size: 38,
                color: widget.palette.textSecondary,
              ),
            ),
          );
        }
        return Image.file(File(path), fit: BoxFit.cover);
      },
    );
  }
}

class _DesktopHeroCopy extends StatelessWidget {
  const _DesktopHeroCopy({
    required this.controller,
    required this.game,
    required this.palette,
    required this.onAskAi,
    required this.onOpenRulebook,
    required this.onOpenFaq,
    required this.openingRulebook,
    required this.openingFaq,
  });

  final AppController controller;
  final GameInfo game;
  final AppPalette palette;
  final VoidCallback onAskAi;
  final VoidCallback onOpenRulebook;
  final VoidCallback onOpenFaq;
  final bool openingRulebook;
  final bool openingFaq;

  @override
  Widget build(BuildContext context) {
    final String kicker = game.categoryLine.trim().isEmpty
        ? game.releaseYear
        : '${game.categoryLine} · ${game.releaseYear}';
    final String subtitle = game.heroTagline.trim().isEmpty
        ? game.subtitle
        : '${game.subtitle} · ${game.heroTagline}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(
          kicker,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: palette.primary,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 9),
        Text(
          game.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            color: palette.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: palette.textSecondary),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _DesktopMetaChip(
              label: '人数',
              value: game.playerCount,
              palette: palette,
            ),
            _DesktopMetaChip(
              label: '时长',
              value: game.playTime,
              palette: palette,
            ),
            _DesktopMetaChip(
              label: '难度',
              value: game.complexity,
              palette: palette,
            ),
          ],
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children: <Widget>[
            FilledButton.icon(
              onPressed: onAskAi,
              icon: const Icon(Icons.auto_awesome_rounded),
              label: const Text('询问 AI'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 19,
                  vertical: 14,
                ),
                backgroundColor: palette.primary,
                foregroundColor: palette.onPrimary,
              ),
            ),
            OutlinedButton.icon(
              onPressed: openingRulebook ? null : onOpenRulebook,
              icon: openingRulebook
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.menu_book_outlined),
              label: const Text('规则书'),
            ),
            OutlinedButton.icon(
              onPressed: openingFaq ? null : onOpenFaq,
              icon: openingFaq
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.quiz_outlined),
              label: const Text('FAQ'),
            ),
          ],
        ),
      ],
    );
  }
}

class _DesktopMetaChip extends StatelessWidget {
  const _DesktopMetaChip({
    required this.label,
    required this.value,
    required this.palette,
  });

  final String label;
  final String value;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfaceContainer,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: RichText(
          text: TextSpan(
            style: Theme.of(context).textTheme.bodyMedium,
            children: <InlineSpan>[
              TextSpan(
                text: '$label  ',
                style: TextStyle(color: palette.textSecondary),
              ),
              TextSpan(
                text: value.trim().isEmpty ? '—' : value,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopScoreCard extends StatelessWidget {
  const _DesktopScoreCard({required this.game, required this.palette});

  final GameInfo game;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final double? score = double.tryParse(game.score);
    final double? progress = score == null ? null : (score / 10).clamp(0, 1);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              '评分',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: palette.textSecondary),
            ),
            Text(
              game.score,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: palette.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              game.scoreCountLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                minHeight: 7,
                value: progress,
                backgroundColor: palette.surfaceVariant,
                valueColor: AlwaysStoppedAnimation<Color>(palette.primary),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text('推荐人数', style: Theme.of(context).textTheme.bodySmall),
                Text(
                  '${game.recommendedPlayer}',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: palette.textPrimary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopDetailTabs extends StatelessWidget {
  const _DesktopDetailTabs({
    required this.selected,
    required this.palette,
    required this.onSelected,
  });

  final _DesktopDetailSection selected;
  final AppPalette palette;
  final ValueChanged<_DesktopDetailSection> onSelected;

  @override
  Widget build(BuildContext context) {
    const List<(String, _DesktopDetailSection)> tabs =
        <(String, _DesktopDetailSection)>[
          ('概览', _DesktopDetailSection.overview),
          ('规则书', _DesktopDetailSection.rules),
          ('FAQ', _DesktopDetailSection.faq),
          ('图库', _DesktopDetailSection.gallery),
        ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: tabs.map(((String, _DesktopDetailSection) tab) {
          final bool active = selected == tab.$2;
          return Padding(
            padding: const EdgeInsets.only(right: 20),
            child: TextButton(
              onPressed: () => onSelected(tab.$2),
              style: TextButton.styleFrom(
                foregroundColor: active
                    ? palette.textPrimary
                    : palette.textSecondary,
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 10),
                shape: const RoundedRectangleBorder(),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: active ? palette.primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  tab.$1,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: active ? palette.textPrimary : palette.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _DesktopOverview extends StatelessWidget {
  const _DesktopOverview({
    required this.controller,
    required this.game,
    required this.palette,
    required this.onAskAi,
    required this.onOpenRulebook,
    required this.onOpenFaq,
    required this.openingRulebook,
    required this.openingFaq,
  });

  final AppController controller;
  final GameInfo game;
  final AppPalette palette;
  final VoidCallback onAskAi;
  final VoidCallback onOpenRulebook;
  final VoidCallback onOpenFaq;
  final bool openingRulebook;
  final bool openingFaq;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool split = constraints.maxWidth >= 900;
        final Widget details = _DesktopOverviewDetails(
          game: game,
          palette: palette,
        );
        final Widget assistant = _DesktopAssistantCard(
          controller: controller,
          game: game,
          palette: palette,
          onAskAi: onAskAi,
        );
        final Widget resources = _DesktopResourcesCard(
          palette: palette,
          onOpenRulebook: onOpenRulebook,
          onOpenFaq: onOpenFaq,
          openingRulebook: openingRulebook,
          openingFaq: openingFaq,
        );
        if (!split) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              details,
              const SizedBox(height: 16),
              assistant,
              const SizedBox(height: 16),
              resources,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(flex: 14, child: details),
            const SizedBox(width: 18),
            Expanded(
              flex: 8,
              child: Column(
                children: <Widget>[
                  assistant,
                  const SizedBox(height: 14),
                  resources,
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DesktopOverviewDetails extends StatelessWidget {
  const _DesktopOverviewDetails({required this.game, required this.palette});

  final GameInfo game;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final String summary = game.summary.trim().isEmpty
        ? '暂无简介，先从规则书或 FAQ 开始了解这款桌游。'
        : game.summary.trim();
    final List<String> flow = game.roundFlow.isEmpty
        ? <String>['准备', '选择角色', '执行阶段', '结算']
        : game.roundFlow;
    return _DesktopPanel(
      palette: palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('游戏简介', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Text(
            summary,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: palette.textSecondary,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 18),
          Text('一局流程', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final int columns = constraints.maxWidth >= 700 ? 4 : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: flow.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: columns == 4 ? 2.2 : 2.7,
                ),
                itemBuilder: (BuildContext context, int index) {
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.surfaceContainer,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(11),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            (index + 1).toString().padLeft(2, '0'),
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(color: palette.primary),
                          ),
                          const SizedBox(height: 4),
                          Expanded(
                            child: Text(
                              flow[index],
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: palette.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DesktopAssistantCard extends StatelessWidget {
  const _DesktopAssistantCard({
    required this.controller,
    required this.game,
    required this.palette,
    required this.onAskAi,
  });

  final AppController controller;
  final GameInfo game;
  final AppPalette palette;
  final VoidCallback onAskAi;

  @override
  Widget build(BuildContext context) {
    final List<String> prompts = game.quickPrompts.take(2).toList();
    return _DesktopPanel(
      palette: palette,
      color: palette.primary.withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.primary,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(9),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: palette.onPrimary,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${game.title}助手',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '规则书与 FAQ 已接入',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '直接询问规则、阶段顺序或当前局面。',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
          ),
          if (prompts.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...prompts.map(
              (String prompt) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton(
                  onPressed: onAskAi,
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                  ),
                  child: Text(
                    prompt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: onAskAi,
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: Text(controller.copy.askAiAssistant),
          ),
        ],
      ),
    );
  }
}

class _DesktopResourcesCard extends StatelessWidget {
  const _DesktopResourcesCard({
    required this.palette,
    required this.onOpenRulebook,
    required this.onOpenFaq,
    required this.openingRulebook,
    required this.openingFaq,
  });

  final AppPalette palette;
  final VoidCallback onOpenRulebook;
  final VoidCallback onOpenFaq;
  final bool openingRulebook;
  final bool openingFaq;

  @override
  Widget build(BuildContext context) {
    return _DesktopPanel(
      palette: palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('资料', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          _DesktopResourceButton(
            icon: Icons.menu_book_outlined,
            label: '官方规则书',
            palette: palette,
            isLoading: openingRulebook,
            onPressed: onOpenRulebook,
          ),
          _DesktopResourceButton(
            icon: Icons.quiz_outlined,
            label: '常见问题 FAQ',
            palette: palette,
            isLoading: openingFaq,
            onPressed: onOpenFaq,
          ),
        ],
      ),
    );
  }
}

class _DesktopResourceButton extends StatelessWidget {
  const _DesktopResourceButton({
    required this.icon,
    required this.label,
    required this.palette,
    required this.isLoading,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final AppPalette palette;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: isLoading ? null : onPressed,
      style: TextButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(vertical: 9),
        foregroundColor: palette.textPrimary,
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18),
          const SizedBox(width: 9),
          Expanded(child: Text(label)),
          if (isLoading)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            const Icon(Icons.chevron_right_rounded, size: 18),
        ],
      ),
    );
  }
}

class _DesktopDocumentPanel extends StatelessWidget {
  const _DesktopDocumentPanel({
    required this.title,
    required this.description,
    required this.icon,
    required this.palette,
    required this.isLoading,
    required this.onOpen,
    required this.buttonLabel,
  });

  final String title;
  final String description;
  final IconData icon;
  final AppPalette palette;
  final bool isLoading;
  final VoidCallback onOpen;
  final String buttonLabel;

  @override
  Widget build(BuildContext context) {
    return _DesktopPanel(
      palette: palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: palette.primary),
              const SizedBox(width: 10),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: palette.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: isLoading ? null : onOpen,
            icon: isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(icon),
            label: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}

class _DesktopGalleryGrid extends StatelessWidget {
  const _DesktopGalleryGrid({
    required this.controller,
    required this.game,
    required this.palette,
  });

  final AppController controller;
  final GameInfo game;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final List<String> paths = game.galleryAssetPaths.isEmpty
        ? <String>[game.coverAssetPath]
        : game.galleryAssetPaths;
    return _DesktopPanel(
      palette: palette,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: paths.length,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 300,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.35,
        ),
        itemBuilder: (BuildContext context, int index) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: _DesktopResolvedImage(
              controller: controller,
              assetPath: paths[index],
              palette: palette,
            ),
          );
        },
      ),
    );
  }
}

class _DesktopPanel extends StatelessWidget {
  const _DesktopPanel({required this.palette, required this.child, this.color});

  final AppPalette palette;
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.outline),
      ),
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    );
  }
}
