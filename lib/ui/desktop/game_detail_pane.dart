import 'package:flutter/material.dart';

import '../../models/game_info.dart';
import '../../state/app_controller.dart';
import '../widgets/desktop_resolved_image.dart';
import 'content_primitives.dart';
import 'desktop_responsive.dart';
import 'theme.dart';

class DesktopGameDetailPane extends StatefulWidget {
  const DesktopGameDetailPane({
    super.key,
    required this.controller,
    required this.game,
    required this.backTooltip,
    required this.onBack,
    required this.onSearch,
    required this.onOpenRules,
    required this.onAskAi,
    required this.onToggleFavorite,
  });

  final AppController controller;
  final GameInfo game;
  final String backTooltip;
  final VoidCallback onBack;
  final VoidCallback onSearch;
  final VoidCallback onOpenRules;
  final VoidCallback onAskAi;
  final ValueChanged<GameInfo> onToggleFavorite;

  @override
  State<DesktopGameDetailPane> createState() => _DesktopGameDetailPaneState();
}

class _DesktopGameDetailPaneState extends State<DesktopGameDetailPane> {
  int _tab = 0;

  static const _tabs = ['游戏介绍', '规则摘要', '玩家评价', '相关扩展', '讨论区'];

  GameInfo get game => widget.game;
  String value(String text) => desktopContentValue(text);

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey<String>('desktop-game-detail'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _hero(),
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
                duration: const Duration(milliseconds: 180),
                child: Padding(
                  key: ValueKey<int>(_tab),
                  padding: const EdgeInsets.all(16),
                  child: _tabBody(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _hero() {
    final heroPath = game.bannerAssetPath.trim().isNotEmpty
        ? game.bannerAssetPath
        : game.coverAssetPath;
    return LayoutBuilder(
      builder: (context, constraints) {
        final condensed = constraints.maxWidth < 1100;
        return SizedBox(
          height: DesktopResponsive.detailHeroHeightFor(constraints.maxWidth),
          child: Stack(
            fit: StackFit.expand,
            children: [
              DesktopResolvedImage(
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
                      Color(0xE819110D),
                      Color(0xB018100D),
                      Color(0x3518100D),
                    ],
                    stops: [0, .48, 1],
                  ),
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x33000000),
                      Colors.transparent,
                      Color(0xA6000000),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: condensed
                    ? const EdgeInsets.fromLTRB(20, 16, 20, 16)
                    : const EdgeInsets.fromLTRB(34, 24, 32, 24),
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
                        const SizedBox(width: 12),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 340),
                              child: InkWell(
                                onTap: widget.onSearch,
                                borderRadius: BorderRadius.circular(24),
                                child: Container(
                                  height: 42,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 15,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xC95A4B42),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                      color: const Color(0x55FFFFFF),
                                    ),
                                  ),
                                  child: const Row(
                                    children: [
                                      Icon(
                                        Icons.search_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      SizedBox(width: 9),
                                      Text(
                                        '搜索桌游 / 机制 / 作者',
                                        style: TextStyle(
                                          color: Color(0xFFF2EAE5),
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            value(game.title),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: condensed ? 30 : 42,
                              height: 1.02,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            value(game.subtitle),
                            style: TextStyle(
                              color: Color(0xFFF2E7DF),
                              fontSize: condensed ? 15 : 19,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: condensed ? 8 : 13),
                          Text(
                            '“ ${value(game.heroTagline)} ”',
                            maxLines: condensed ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: condensed ? 12.5 : 15,
                              height: 1.45,
                            ),
                          ),
                          SizedBox(height: condensed ? 10 : 16),
                          Row(
                            children: [
                              Icon(
                                Icons.star_rounded,
                                color: Color(0xFFFFD12D),
                                size: condensed ? 20 : 25,
                              ),
                              SizedBox(width: condensed ? 5 : 7),
                              Text(
                                value(game.score),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: condensed ? 18 : 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              SizedBox(width: condensed ? 7 : 10),
                              Text(
                                '(${value(game.scoreCountLabel)})',
                                style: const TextStyle(
                                  color: Color(0xFFD9CEC7),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: condensed ? 10 : 17),
                          Row(
                            children: [
                              _HeroMetric(
                                Icons.group_rounded,
                                value(game.playerCount),
                                '推荐人数',
                              ),
                              _HeroMetric(
                                Icons.schedule_rounded,
                                value(game.playTime),
                                '游戏时长',
                              ),
                              _HeroMetric(
                                Icons.bar_chart_rounded,
                                value(game.complexity),
                                '游戏难度',
                              ),
                            ],
                          ),
                          if (!condensed) ...[
                            const SizedBox(height: 15),
                            Wrap(
                              spacing: 7,
                              runSpacing: 7,
                              children: [
                                for (final tag in _tags().take(6))
                                  _HeroTag(tag),
                              ],
                            ),
                            const SizedBox(height: 14),
                          ] else
                            const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
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
                                onTap: () => widget.onToggleFavorite(game),
                                width: 108,
                              ),
                              _HeroButton(
                                label: '加入想玩 · 未开放',
                                icon: Icons.add_circle_outline_rounded,
                                onTap: () =>
                                    desktopContentPending(context, '加入想玩'),
                                light: true,
                              ),
                              _HeroButton(
                                label: '询问 AI',
                                icon: Icons.auto_awesome_rounded,
                                onTap: widget.onAskAi,
                                light: true,
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
    final paths = <String>{
      ...game.galleryAssetPaths.where((path) => path.trim().isNotEmpty),
      if (game.bannerAssetPath.trim().isNotEmpty) game.bannerAssetPath,
      if (game.coverAssetPath.trim().isNotEmpty) game.coverAssetPath,
    };
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
        itemBuilder: (context, index) => ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: SizedBox(
            width: 146,
            child: DesktopResolvedImage(
              controller: widget.controller,
              assetPath: paths[index],
              palette: widget.controller.palette,
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
              duration: const Duration(milliseconds: 150),
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
    _ => _UnavailableTab(title: _tabs[_tab]),
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
        const Text(
          '规则资料',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(
          '已接入主项目资料库，共 ${available.length} 份可阅读资料。',
          style: const TextStyle(color: DesktopColors.secondaryText),
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

class _UnavailableTab extends StatelessWidget {
  const _UnavailableTab({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 150,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.hourglass_empty_rounded,
            color: DesktopColors.orange,
            size: 28,
          ),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text(
            '未开放',
            style: TextStyle(color: DesktopColors.secondaryText),
          ),
        ],
      ),
    ),
  );
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric(this.icon, this.value, this.label);
  final IconData icon;
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 105),
    margin: const EdgeInsets.only(right: 10),
    padding: const EdgeInsets.only(right: 10),
    decoration: const BoxDecoration(
      border: Border(right: BorderSide(color: Color(0x55FFFFFF))),
    ),
    child: Row(
      children: [
        Icon(icon, size: 18, color: Colors.white),
        const SizedBox(width: 7),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              style: const TextStyle(color: Color(0xFFD7CBC3), fontSize: 9),
            ),
          ],
        ),
      ],
    ),
  );
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
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool light;
  final double? width;
  @override
  State<_HeroButton> createState() => _HeroButtonState();
}

class _HeroButtonState extends State<_HeroButton> {
  bool hover = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => hover = true),
    onExit: (_) => setState(() => hover = false),
    child: InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(11),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        transform: Matrix4.translationValues(0, hover ? -2 : 0, 0),
        width: widget.width,
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: widget.light ? const Color(0xEFFCF7F3) : DesktopColors.orange,
          borderRadius: BorderRadius.circular(11),
          boxShadow: hover
              ? const [
                  BoxShadow(
                    color: Color(0x44000000),
                    blurRadius: 12,
                    offset: Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          reverseDuration: const Duration(milliseconds: 150),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: Row(
            key: ValueKey<String>('${widget.icon.codePoint}-${widget.label}'),
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.icon,
                color: widget.light ? const Color(0xFF59463B) : Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.light ? const Color(0xFF59463B) : Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
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
