import 'package:flutter/material.dart';

import 'v4_theme.dart';

class V4Sidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  const V4Sidebar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
  });

  static const _items = <({IconData icon, String label})>[
    (icon: Icons.home_rounded, label: '首页'),
    (icon: Icons.casino_rounded, label: '游戏库'),
    (icon: Icons.smart_toy_rounded, label: 'AI助手'),
    (icon: Icons.emoji_events_rounded, label: '排行榜'),
    (icon: Icons.favorite_rounded, label: '我的收藏'),
    (icon: Icons.chat_bubble_rounded, label: '社区'),
    (icon: Icons.settings_rounded, label: '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 205,
      height: double.infinity,
      decoration: const BoxDecoration(
        color: V4Colors.sidebar,
        border: Border(right: BorderSide(color: V4Colors.line)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            top: 520,
            child: Image.asset(
              'assets/v4/sidebar_art.png',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 24, 10, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 21),
                  child: Image.asset(
                    'assets/v4/logo.png',
                    width: 77,
                    height: 72,
                    fit: BoxFit.contain,
                  ),
                ),
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
                      color: V4Colors.secondaryText,
                      fontSize: 13,
                    ),
                  ),
                ),
                for (var i = 0; i < _items.length; i++) ...[
                  _NavTile(
                    icon: _items[i].icon,
                    label: _items[i].label,
                    selected: i == selectedIndex,
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
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _NavTile({
    required this.icon,
    required this.label,
    required this.selected,
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
    return MouseRegion(
      cursor: active ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 44,
          margin: const EdgeInsets.only(bottom: 3),
          padding: const EdgeInsets.symmetric(horizontal: 18),
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
            children: [
              Icon(
                widget.icon,
                size: 22,
                color: active ? Colors.white : V4Colors.brown,
              ),
              const SizedBox(width: 15),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? Colors.white : const Color(0xFF4B4038),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
