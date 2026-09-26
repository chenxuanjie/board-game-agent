import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import '../../app/state/app_controller.dart';
import '../../features/games/models/game_info.dart';
import '../../features/library/models/resolved_document.dart';
import '../shared/documents/document_viewer_launcher.dart';
import 'assistant_chat_screen.dart';
import 'game_cover.dart';

const _ink = Color(0xFF271D1B);
const _muted = Color(0xFF817B7A);
const _orange = Color(0xFFE9772E);
const _cream = Color(0xFFFFF3E4);

class GameDetailScreen extends StatefulWidget {
  const GameDetailScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<GameDetailScreen> createState() => _GameDetailScreenState();
}

class _GameDetailScreenState extends State<GameDetailScreen> {
  late final PageController _galleryController;
  int _galleryIndex = 0;
  bool _openingRulebook = false;
  bool _openingFaq = false;
  bool _expandedSummary = false;

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
    _galleryController.animateToPage(
      next,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final copy = controller.copy;
    final game = controller.selectedGame;
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
                      Expanded(
                        child: Text(
                          copy.localized(
                            '让好游戏，连接更多人',
                            'Good games bring us together',
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            color: Color(0xFF8C4C31),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
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
                                                mainAxisSize: MainAxisSize.min,
                                                children: List.generate(
                                                  gallery.length,
                                                  (dot) => AnimatedContainer(
                                                    duration: const Duration(
                                                      milliseconds: 180,
                                                    ),
                                                    margin:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 3,
                                                        ),
                                                    width: dot == _galleryIndex
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
                            if (kIsWeb && gallery.length > 1) ...[
                              Positioned(
                                left: 12,
                                top: 0,
                                bottom: 0,
                                child: Center(
                                  child: _GalleryPageArrow(
                                    key: const ValueKey<String>(
                                      'mobile-detail-gallery-previous',
                                    ),
                                    tooltip: copy.localized(
                                      '上一张图片',
                                      'Previous image',
                                    ),
                                    icon: Icons.chevron_left_rounded,
                                    onTap: () =>
                                        _stepGalleryPage(-1, gallery.length),
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 12,
                                top: 0,
                                bottom: 0,
                                child: Center(
                                  child: _GalleryPageArrow(
                                    key: const ValueKey<String>(
                                      'mobile-detail-gallery-next',
                                    ),
                                    tooltip: copy.localized(
                                      '下一张图片',
                                      'Next image',
                                    ),
                                    icon: Icons.chevron_right_rounded,
                                    onTap: () =>
                                        _stepGalleryPage(1, gallery.length),
                                  ),
                                ),
                              ),
                            ],
                          ],
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
                                        if (game.subtitle.trim().isNotEmpty)
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
                            if (game.heroTagline.trim().isNotEmpty)
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
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFF3E8DC),
                                ),
                              ),
                              child: Row(
                                children: [
                                  _stat(
                                    Icons.people_alt_rounded,
                                    game.playerCount,
                                    copy.localized('游戏人数', 'Players'),
                                  ),
                                  _stat(
                                    Icons.schedule_rounded,
                                    game.playTime,
                                    copy.localized('游戏时长', 'Play time'),
                                  ),
                                  _stat(
                                    Icons.bar_chart_rounded,
                                    game.complexity,
                                    copy.localized('游戏难度', 'Difficulty'),
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
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          copy.localized(
                                            '游戏简介',
                                            'About this game',
                                          ),
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w800,
                                            color: _ink,
                                          ),
                                        ),
                                      ),
                                      TextButton.icon(
                                        onPressed: () => setState(
                                          () => _expandedSummary =
                                              !_expandedSummary,
                                        ),
                                        label: Text(
                                          _expandedSummary
                                              ? copy.localized('收起', 'Collapse')
                                              : copy.localized(
                                                  '展开全部',
                                                  'Show all',
                                                ),
                                        ),
                                        icon: Icon(
                                          _expandedSummary
                                              ? Icons.expand_less_rounded
                                              : Icons.expand_more_rounded,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    summary,
                                    maxLines: _expandedSummary ? null : 4,
                                    overflow: _expandedSummary
                                        ? null
                                        : TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF626166),
                                      height: 1.6,
                                    ),
                                  ),
                                  if (game.mentorPitch.trim().isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        _assetIcon(
                                          'assets/mobile/detail/tip.png',
                                          21,
                                        ),
                                        const SizedBox(width: 7),
                                        Expanded(
                                          child: Text(
                                            game.mentorPitch,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF9C6948),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _openingFaq
                                        ? null
                                        : () => _openDocument(game, faq: true),
                                    icon: _openingFaq
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.quiz_outlined),
                                    label: Text(copy.faq),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute<void>(
                                        builder: (_) => AssistantChatScreen(
                                          controller: controller,
                                        ),
                                      ),
                                    ),
                                    icon: const Icon(Icons.smart_toy_outlined),
                                    label: Text(copy.askAiAssistant),
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
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 9, 16, 10),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFF3E8DC))),
          ),
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
                          : () => _openDocument(game, faq: false),
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
                      key: const ValueKey('mobile-detail-wishlist'),
                      onPressed: () =>
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                copy.localized(
                                  '想玩清单暂未开放',
                                  'Wishlist is coming soon',
                                ),
                              ),
                            ),
                          ),
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      label: Text(copy.localized('加入想玩', 'Want to play')),
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
    IconData? icon,
    String? asset,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Material(
      color: _cream,
      borderRadius: BorderRadius.circular(18),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: asset == null
            ? Icon(icon, size: 21, color: const Color(0xFF78431E))
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

  Widget _stat(IconData icon, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: _orange, size: 24),
          const SizedBox(height: 4),
          Text(
            value.trim().isEmpty ? '-' : value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
          Text(label, style: const TextStyle(fontSize: 11, color: _muted)),
        ],
      ),
    );
  }

  Future<void> _openDocument(GameInfo game, {required bool faq}) async {
    final controller = widget.controller;
    final title = faq ? controller.copy.faq : controller.copy.rulesBook;
    setState(() {
      if (faq) {
        _openingFaq = true;
      } else {
        _openingRulebook = true;
      }
    });
    try {
      final ResolvedDocument? document = faq
          ? await controller.resolveFaqDocument(game)
          : await controller.resolveRulebookDocument(game);
      if (!mounted) return;
      if (document == null) {
        _documentUnavailable(title, () => _openDocument(game, faq: faq));
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
        _documentUnavailable(title, () => _openDocument(game, faq: faq));
      }
    } finally {
      if (mounted) {
        setState(() {
          if (faq) {
            _openingFaq = false;
          } else {
            _openingRulebook = false;
          }
        });
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

class _GalleryPageArrow extends StatelessWidget {
  const _GalleryPageArrow({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 28),
      color: Colors.white,
      style: IconButton.styleFrom(
        backgroundColor: Colors.black45,
        minimumSize: const Size.square(44),
        maximumSize: const Size.square(44),
        padding: EdgeInsets.zero,
      ),
    ),
  );
}
