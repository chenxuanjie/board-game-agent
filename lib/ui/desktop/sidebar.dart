import 'package:flutter/material.dart';

import 'theme.dart';

class DesktopSidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final bool compact;
  final double? width;

  const DesktopSidebar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    this.compact = false,
    this.width,
  });

  static const _items = <({String asset, String label})>[
    (asset: 'sidebar_home.png', label: '首页'),
    (asset: 'sidebar_library.png', label: '游戏库'),
    (asset: 'sidebar_ai.png', label: 'AI助手'),
    (asset: 'sidebar_likes.png', label: '我的喜欢'),
    (asset: 'sidebar_community.png', label: '社区'),
    (asset: 'sidebar_settings.png', label: '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey<String>(
        compact ? 'desktop-sidebar-rail' : 'desktop-sidebar-full',
      ),
      width: width ?? (compact ? 76 : 205),
      height: double.infinity,
      decoration: const BoxDecoration(
        color: DesktopColors.sidebar,
        border: Border(right: BorderSide(color: DesktopColors.line)),
      ),
      child: Stack(
        children: [
          if (!compact)
            Positioned.fill(
              top: 520,
              child: Image.asset(
                'assets/desktop/home/sidebar_castle.png',
                key: const ValueKey<String>('desktop-sidebar-art'),
                fit: BoxFit.contain,
                alignment: Alignment.bottomCenter,
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 8 : 10,
              24,
              compact ? 8 : 10,
              18,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(left: compact ? 3 : 21),
                  child: Image.asset(
                    'assets/desktop/home/logo.png',
                    key: const ValueKey<String>('desktop-sidebar-logo'),
                    width: compact ? 48 : 77,
                    height: compact ? 48 : 72,
                    fit: BoxFit.contain,
                  ),
                ),
                if (!compact) ...[
                  const Padding(
                    padding: EdgeInsets.only(left: 22, top: 5),
                    child: Text(
                      '桌游助手',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 22, top: 4, bottom: 16),
                    child: Text(
                      '发现更大的桌游世界',
                      style: TextStyle(
                        color: DesktopColors.secondaryText,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ] else
                  const SizedBox(height: 25),
                for (var i = 0; i < _items.length; i++) ...[
                  _NavTile(
                    asset: _items[i].asset,
                    label: _items[i].label,
                    selected: i == selectedIndex,
                    compact: compact,
                    onTap: i == selectedIndex ? null : () => onSelect(i),
                  ),
                  if (i == 5) const SizedBox(height: 7),
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
    final active = widget.selected;
    final tile = MouseRegion(
      cursor: active ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 44,
          margin: const EdgeInsets.only(bottom: 3),
          padding: EdgeInsets.symmetric(horizontal: widget.compact ? 0 : 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
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
                  width: 24,
                  height: 24,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
              if (!widget.compact) ...[
                const SizedBox(width: 10),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? Colors.white : const Color(0xFF4B4038),
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
