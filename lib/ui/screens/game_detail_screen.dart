import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/game_info.dart';
import '../../models/resolved_document.dart';
import '../../state/app_controller.dart';
import '../../theme/app_palette.dart';
import 'assistant_chat_screen.dart';
import 'markdown_document_screen.dart';
import 'pdf_document_screen.dart';

class GameDetailScreen extends StatefulWidget {
  const GameDetailScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<GameDetailScreen> createState() => _GameDetailScreenState();
}

class _GameDetailScreenState extends State<GameDetailScreen> {
  late final PageController _galleryController;
  int _galleryIndex = 0;
  _PlayerStripMode _playerStripMode = _PlayerStripMode.supported;
  bool _openingRulebook = false;
  bool _openingFaq = false;

  @override
  void initState() {
    super.initState();
    _galleryController = PageController(viewportFraction: 0.9);
  }

  @override
  void dispose() {
    _galleryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final copy = controller.copy;
    final game = controller.selectedGame;
    final palette = AppPalette.of(context);
    final editionLabel = game.editionLabel ?? '';

    return Scaffold(
      backgroundColor: palette.pageBackground,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: _RemoteGameImage(
              controller: controller,
              remotePath: game.bannerAssetPath,
              palette: palette,
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    palette.surfaceVariant,
                    palette.surfaceContainer,
                    palette.pageBackground,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
              children: <Widget>[
                _DetailTopBar(title: copy.detailPageTitle, palette: palette),
                const SizedBox(height: 18),
                _ImageGallery(
                  controller: _galleryController,
                  appController: controller,
                  game: game,
                  palette: palette,
                  pageLabel: copy.imagePageLabel,
                  coverLabel: copy.imageCoverLabel,
                  sceneLabel: copy.imageSceneLabel,
                  currentIndex: _galleryIndex,
                  onPageChanged: (value) =>
                      setState(() => _galleryIndex = value),
                ),
                const SizedBox(height: 18),
                _ScorePanel(
                  controller: controller,
                  mode: _playerStripMode,
                  onModeChanged: (mode) =>
                      setState(() => _playerStripMode = mode),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: game.rankBadges
                      .map((badge) => _RankChip(text: badge, palette: palette))
                      .toList(),
                ),
                const SizedBox(height: 18),
                Text(
                  editionLabel.isEmpty
                      ? game.title
                      : copy.isChinese
                      ? '${game.title}：$editionLabel'
                      : '${game.title}: $editionLabel',
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    color: palette.textPrimary,
                    fontSize: 30,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${game.subtitle} (${game.releaseYear})',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: palette.textPrimary.withValues(alpha: 0.78),
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 14),
                _MetaLine(
                  value: '${game.releaseYear} / ${game.categoryLine}',
                  emphasis: true,
                  palette: palette,
                ),
                _MetaRow(
                  label: copy.learningDifficultyLabel,
                  value: game.learningDifficulty,
                  palette: palette,
                ),
                _MetaRow(
                  label: copy.perPlayerTimeLabel,
                  value: game.perPlayerTime,
                  palette: palette,
                ),
                _MetaRow(
                  label: copy.setupTimeLabel,
                  value: game.setupTime,
                  palette: palette,
                ),
                _MetaRow(
                  label: copy.languageRequirementLabel,
                  value: game.languageRequirement,
                  palette: palette,
                ),
                const SizedBox(height: 22),
                _ActionButton(
                  icon: Icons.menu_book_rounded,
                  label: copy.rulesBook,
                  palette: palette,
                  isLoading: _openingRulebook,
                  onTap: _openingRulebook
                      ? null
                      : () => _openRulebook(controller, game, copy.rulesBook),
                ),
                const SizedBox(height: 12),
                _ActionButton(
                  icon: Icons.quiz_rounded,
                  label: copy.faq,
                  palette: palette,
                  isLoading: _openingFaq,
                  onTap: _openingFaq
                      ? null
                      : () => _openFaq(controller, game, copy.faq),
                ),
                const SizedBox(height: 12),
                _ActionButton(
                  icon: Icons.smart_toy_rounded,
                  label: copy.askAiAssistant,
                  palette: palette,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            AssistantChatScreen(controller: controller),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openRulebook(
    AppController controller,
    GameInfo game,
    String title,
  ) async {
    setState(() => _openingRulebook = true);
    try {
      final ResolvedDocument? document = await controller
          .resolveRulebookDocument(game);
      if (!mounted || document == null) {
        return;
      }
      await _openResolvedDocument(controller, document, title);
    } finally {
      if (mounted) {
        setState(() => _openingRulebook = false);
      }
    }
  }

  Future<void> _openFaq(
    AppController controller,
    GameInfo game,
    String title,
  ) async {
    setState(() => _openingFaq = true);
    try {
      final ResolvedDocument? document = await controller.resolveFaqDocument(
        game,
      );
      if (!mounted || document == null) {
        return;
      }
      await _openResolvedDocument(controller, document, title);
    } finally {
      if (mounted) {
        setState(() => _openingFaq = false);
      }
    }
  }

  Future<void> _openResolvedDocument(
    AppController controller,
    ResolvedDocument document,
    String title,
  ) async {
    if (document.renderType == DocumentRenderType.markdown) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MarkdownDocumentScreen(
            controller: controller,
            remotePath: document.remotePath,
            title: title,
          ),
        ),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PdfDocumentScreen(
          controller: controller,
          title: title,
          remotePath: document.remotePath,
        ),
      ),
    );
  }
}

class _RemoteGameImage extends StatefulWidget {
  const _RemoteGameImage({
    required this.controller,
    required this.remotePath,
    required this.palette,
    required this.fit,
  });

  final AppController controller;
  final String remotePath;
  final AppPalette palette;
  final BoxFit fit;

  @override
  State<_RemoteGameImage> createState() => _RemoteGameImageState();
}

class _RemoteGameImageState extends State<_RemoteGameImage> {
  String? _resolvedPath;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _RemoteGameImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.remotePath != widget.remotePath) {
      _resolvedPath = null;
      _resolve();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_resolvedPath == null) {
      return DecoratedBox(
        decoration: BoxDecoration(color: widget.palette.surfaceVariant),
        child: Center(
          child: Icon(
            Icons.image_not_supported_outlined,
            color: widget.palette.textSecondary,
            size: 34,
          ),
        ),
      );
    }
    return Image.file(File(_resolvedPath!), fit: widget.fit);
  }

  Future<void> _resolve() async {
    final String? path = await widget.controller.resolveImagePath(
      widget.remotePath,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _resolvedPath = path;
    });
  }
}

enum _PlayerStripMode { both, supported, recommended }

class _DetailTopBar extends StatelessWidget {
  const _DetailTopBar({required this.title, required this.palette});

  final String title;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: palette.textPrimary,
            size: 30,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Center(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: palette.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        Container(
          width: 58,
          height: 46,
          decoration: BoxDecoration(
            color: palette.textPrimary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(
            Icons.more_horiz_rounded,
            color: palette.textPrimary.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

class _ImageGallery extends StatelessWidget {
  const _ImageGallery({
    required this.controller,
    required this.appController,
    required this.game,
    required this.palette,
    required this.pageLabel,
    required this.coverLabel,
    required this.sceneLabel,
    required this.currentIndex,
    required this.onPageChanged,
  });

  final PageController controller;
  final AppController appController;
  final GameInfo game;
  final AppPalette palette;
  final String pageLabel;
  final String coverLabel;
  final String sceneLabel;
  final int currentIndex;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: <Widget>[
        SizedBox(
          height: 390,
          child: PageView.builder(
            controller: controller,
            itemCount: game.galleryAssetPaths.length,
            onPageChanged: onPageChanged,
            itemBuilder: (context, index) {
              final assetPath = game.galleryAssetPaths[index];
              final isCover = assetPath == game.coverAssetPath;
              final fallbackPath = game.galleryAssetPaths.firstWhere(
                (path) => path != assetPath,
                orElse: () => game.coverAssetPath,
              );
              return Padding(
                padding: EdgeInsets.only(
                  left: index == 0 ? 0 : 6,
                  right: index == game.galleryAssetPaths.length - 1 ? 0 : 6,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: palette.shadow.withValues(alpha: 0.52),
                        blurRadius: 28,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        _GalleryImage(
                          controller: appController,
                          assetPath: assetPath,
                          fallbackPath: fallbackPath,
                          palette: palette,
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                palette.shadow.withValues(alpha: 0.04),
                                Colors.transparent,
                                palette.shadow.withValues(alpha: 0.42),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          top: 16,
                          left: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: palette.surfaceContainer.withValues(
                                alpha: 0.86,
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              isCover ? coverLabel : sceneLabel,
                              style: textTheme.labelLarge?.copyWith(
                                color: palette.textPrimary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 18,
                          right: 18,
                          bottom: 18,
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  '$pageLabel ${index + 1}',
                                  style: textTheme.titleMedium?.copyWith(
                                    color: palette.textPrimary,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                              Text(
                                '${index + 1}/${game.galleryAssetPaths.length}',
                                style: textTheme.bodyMedium?.copyWith(
                                  color: palette.textSecondary,
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
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List<Widget>.generate(
            game.galleryAssetPaths.length,
            (index) => AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: currentIndex == index ? 28 : 9,
              height: 9,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: currentIndex == index
                    ? palette.primary
                    : palette.textPrimary.withValues(alpha: 0.26),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GalleryImage extends StatefulWidget {
  const _GalleryImage({
    required this.controller,
    required this.assetPath,
    required this.fallbackPath,
    required this.palette,
  });

  final AppController controller;
  final String assetPath;
  final String fallbackPath;
  final AppPalette palette;

  @override
  State<_GalleryImage> createState() => _GalleryImageState();
}

class _GalleryImageState extends State<_GalleryImage> {
  String? _resolvedPath;
  bool _triedFallback = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _GalleryImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPath != widget.assetPath) {
      _resolvedPath = null;
      _triedFallback = false;
      _resolve();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_resolvedPath == null) {
      return DecoratedBox(
        decoration: BoxDecoration(color: widget.palette.surfaceVariant),
        child: Center(
          child: Icon(
            Icons.photo_library_outlined,
            color: widget.palette.textSecondary,
            size: 44,
          ),
        ),
      );
    }
    return Image.file(
      File(_resolvedPath!),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        if (!_triedFallback && widget.fallbackPath != widget.assetPath) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) {
              return;
            }
            _triedFallback = true;
            final String? fallback = await widget.controller.resolveImagePath(
              widget.fallbackPath,
            );
            if (!mounted) {
              return;
            }
            setState(() {
              _resolvedPath = fallback;
            });
          });
        }
        return Center(
          child: Icon(
            Icons.photo_library_outlined,
            color: widget.palette.textSecondary,
            size: 44,
          ),
        );
      },
    );
  }

  Future<void> _resolve() async {
    final String? path = await widget.controller.resolveImagePath(
      widget.assetPath,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _resolvedPath = path;
    });
  }
}

class _ScorePanel extends StatelessWidget {
  const _ScorePanel({
    required this.controller,
    required this.mode,
    required this.onModeChanged,
  });

  final AppController controller;
  final _PlayerStripMode mode;
  final ValueChanged<_PlayerStripMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final game = controller.selectedGame;
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: palette.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.outline),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: palette.shadow.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 102,
            height: 126,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              color: palette.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  game.score,
                  style: GoogleFonts.notoSerifSc(
                    color: palette.onPrimary,
                    fontSize: 38,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  game.scoreCountLabel,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansSc(
                    color: palette.onPrimary.withValues(alpha: 0.96),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    height: 1.05,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _PlayerNumberStrip(
                  supportedPlayers: game.supportedPlayers,
                  recommendedPlayer: game.recommendedPlayer,
                  mode: _PlayerStripMode.both,
                ),
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _PlayerModeButton(
                        label: controller.copy.supportPlayersLabel,
                        selected: true,
                        selectedColor: palette.primary,
                        textAlign: TextAlign.left,
                        onTap: () => onModeChanged(_PlayerStripMode.supported),
                      ),
                    ),
                    Expanded(
                      child: _PlayerModeButton(
                        label: controller.copy.recommendedPlayersLabel,
                        selected: true,
                        selectedColor: palette.secondary,
                        textAlign: TextAlign.right,
                        onTap: () =>
                            onModeChanged(_PlayerStripMode.recommended),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerModeButton extends StatelessWidget {
  const _PlayerModeButton({
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.textAlign,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color selectedColor;
  final TextAlign textAlign;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          label,
          textAlign: textAlign,
          style: GoogleFonts.notoSansSc(
            color: selected
                ? selectedColor
                : selectedColor.withValues(alpha: 0.5),
            fontSize: 16,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.1,
          ),
        ),
      ),
    );
  }
}

class _PlayerNumberStrip extends StatelessWidget {
  const _PlayerNumberStrip({
    required this.supportedPlayers,
    required this.recommendedPlayer,
    required this.mode,
  });

  final List<int> supportedPlayers;
  final int recommendedPlayer;
  final _PlayerStripMode mode;

  @override
  Widget build(BuildContext context) {
    const itemWidth = 22.0;
    const itemHeight = 30.0;
    const spacing = 4.0;
    final cells = <Widget>[
      ...List<Widget>.generate(12, (index) {
        final number = index + 1;
        final isSupported = supportedPlayers.contains(number);
        final isRecommended = number == recommendedPlayer;
        Color? fillColor;
        if (isRecommended) {
          fillColor = Theme.of(context).colorScheme.secondary;
        } else if (isSupported) {
          fillColor = Theme.of(context).colorScheme.primary;
        }
        final isActive = fillColor != null;
        return Container(
          width: itemWidth,
          height: itemHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive
                ? fillColor
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '$number',
            style: GoogleFonts.notoSansSc(
              color: isActive
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              height: 1,
            ),
          ),
        );
      }),
      Container(
        width: itemWidth,
        height: itemHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '+',
          style: GoogleFonts.notoSansSc(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 10,
            fontWeight: FontWeight.w500,
            height: 1,
          ),
        ),
      ),
    ];
    return Wrap(spacing: spacing, runSpacing: spacing, children: cells);
  }
}

class _RankChip extends StatelessWidget {
  const _RankChip({required this.text, required this.palette});

  final String text;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final Color chipTextColor = palette.onSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: palette.secondary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(color: chipTextColor, fontSize: 16),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({
    required this.value,
    required this.palette,
    this.emphasis = false,
  });

  final String value;
  final AppPalette palette;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: emphasis ? 18 : 12),
      child: Text(
        value,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: emphasis
              ? palette.textPrimary.withValues(alpha: 0.8)
              : palette.textPrimary,
          fontSize: emphasis ? 19 : 17,
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.label,
    required this.value,
    required this.palette,
  });

  final String label;
  final String value;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: '$label：',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: palette.textPrimary.withValues(alpha: 0.72),
                fontSize: 17,
              ),
            ),
            TextSpan(
              text: value,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: palette.textPrimary,
                fontSize: 17,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.palette,
    required this.onTap,
    this.isLoading = false,
  });

  final IconData icon;
  final String label;
  final AppPalette palette;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final Color foregroundColor = palette.primary;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 18),
          side: BorderSide(color: palette.primary, width: 1.8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          foregroundColor: foregroundColor,
          backgroundColor: palette.surface.withValues(alpha: 0.18),
        ),
        icon: isLoading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
                ),
              )
            : Icon(icon, size: 22),
        label: Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: foregroundColor,
            fontSize: 20,
          ),
        ),
      ),
    );
  }
}
