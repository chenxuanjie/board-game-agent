import 'package:flutter/material.dart';

import '../../core/localization/app_copy.dart';
import 'desktop_responsive.dart';
import 'theme.dart';

class DesktopSidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final bool compact;
  final double? width;
  final AppCopy copy;

  const DesktopSidebar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    required this.copy,
    this.compact = false,
    this.width,
  });

  static const _items = <({String asset, String zh, String en})>[
    (asset: 'sidebar_home.png', zh: '首页', en: 'Home'),
    (asset: 'sidebar_library.png', zh: '游戏库', en: 'Game Library'),
    (asset: 'sidebar_ai.png', zh: 'AI助手', en: 'AI Assistant'),
    (asset: 'sidebar_likes.png', zh: '我的喜欢', en: 'My Likes'),
    (asset: 'sidebar_settings.png', zh: '设置', en: 'Settings'),
  ];
  static const double _headerHeight = 152;

  @override
  Widget build(BuildContext context) {
    final metrics = DesktopMetricsScope.of(context);
    return Container(
      key: ValueKey<String>(
        compact ? 'desktop-sidebar-rail' : 'desktop-sidebar-full',
      ),
      width:
          width ??
          (compact
              ? metrics.px(DesktopResponsive.compactSidebarWidth)
              : metrics.px(DesktopResponsive.fullSidebarWidth)),
      height: double.infinity,
      decoration: const BoxDecoration(
        color: DesktopColors.sidebar,
        border: Border(right: BorderSide(color: DesktopColors.line)),
      ),
      child: Stack(
        children: [
          if (!compact)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AspectRatio(
                aspectRatio: 971 / 1619,
                child: Image.asset(
                  'assets/desktop/home/sidebar_castle.png',
                  key: const ValueKey<String>('desktop-sidebar-art'),
                  width: double.infinity,
                  fit: BoxFit.fitWidth,
                  alignment: Alignment.bottomCenter,
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              metrics.px(compact ? 8 : 10),
              metrics.px(24),
              metrics.px(compact ? 8 : 10),
              metrics.px(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: metrics.px(
                      compact || copy.isChinese ? _headerHeight : 216,
                    ),
                  ),
                  child: compact
                      ? Align(
                          alignment: Alignment.topCenter,
                          child: Image.asset(
                            'assets/desktop/home/logo.png',
                            key: const ValueKey<String>('desktop-sidebar-logo'),
                            width: metrics.px(48),
                            height: metrics.px(48),
                            fit: BoxFit.contain,
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: EdgeInsets.only(left: metrics.px(21)),
                              child: Image.asset(
                                'assets/desktop/home/logo.png',
                                key: const ValueKey<String>(
                                  'desktop-sidebar-logo',
                                ),
                                width: metrics.px(77),
                                height: metrics.px(72),
                                fit: BoxFit.contain,
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.only(
                                left: metrics.px(22),
                                top: metrics.px(5),
                              ),
                              child: Text(
                                copy.localized('桌游助手', 'Board Game Agent'),
                                style: TextStyle(
                                  fontSize: metrics.font(
                                    copy.isChinese ? 25 : 19,
                                  ),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: metrics.px(-0.5),
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.only(
                                left: metrics.px(22),
                                top: metrics.px(4),
                                bottom: metrics.px(16),
                              ),
                              child: Text(
                                copy.localized(
                                  '发现更大的桌游世界',
                                  'Discover more board games',
                                ),
                                style: TextStyle(
                                  color: DesktopColors.secondaryText,
                                  fontSize: metrics.font(
                                    copy.isChinese ? 13 : 11,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
                for (var i = 0; i < _items.length; i++) ...[
                  _NavTile(
                    key: ValueKey<String>(
                      'desktop-sidebar-item-${_items[i].asset}',
                    ),
                    asset: _items[i].asset,
                    label: copy.localized(_items[i].zh, _items[i].en),
                    selected: i == selectedIndex,
                    compact: compact,
                    onTap: i == selectedIndex ? null : () => onSelect(i),
                  ),
                  if (i == 5) SizedBox(height: metrics.px(7)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatefulWidget {
  final String asset;
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool compact;

  const _NavTile({
    super.key,
    required this.asset,
    required this.label,
    required this.selected,
    this.compact = false,
    this.onTap,
  });

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    final metrics = DesktopMetricsScope.of(context);
    final active = widget.selected;
    final tile = MouseRegion(
      cursor: active ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: metrics.px(44),
          margin: EdgeInsets.only(bottom: metrics.px(3)),
          padding: EdgeInsets.symmetric(
            horizontal: metrics.px(widget.compact ? 0 : 14),
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(metrics.radius(11)),
            gradient: active
                ? const LinearGradient(
                    colors: [Color(0xFFFF5D45), Color(0xFFFF9D58)],
                  )
                : null,
            color: !active && hovering ? const Color(0x0B9A5B38) : null,
          ),
          child: Row(
            mainAxisAlignment: widget.compact
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              ColorFiltered(
                colorFilter: active
                    ? const ColorFilter.mode(Colors.white, BlendMode.srcIn)
                    : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
                child: Image.asset(
                  'assets/desktop/home/sidebar_icons/${widget.asset}',
                  key: ValueKey<String>('desktop-sidebar-icon-${widget.asset}'),
                  width: metrics.px(28),
                  height: metrics.px(28),
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
              if (!widget.compact) ...[
                SizedBox(width: metrics.px(10)),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 2,
                    style: TextStyle(
                      fontSize: metrics.font(17),
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? Colors.white : const Color(0xFF4B4038),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return widget.compact ? Tooltip(message: widget.label, child: tile) : tile;
  }
}
