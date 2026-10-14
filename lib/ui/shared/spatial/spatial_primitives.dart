import 'package:flutter/material.dart';
import '../../../core/theme/app_motion.dart';

// Visual primitives adapted from the user-supplied Flutter reference.
class SpatialPoster extends StatefulWidget {
  final String title;
  final String match;
  final String genres;
  final String badge;
  final Widget? image;
  final String imageUrl;
  final List<Color> fallbackGradient;
  final bool isCompact;
  final VoidCallback onSelect;

  const SpatialPoster({
    super.key,
    this.image,
    required this.title,
    required this.match,
    required this.genres,
    required this.badge,
    required this.imageUrl,
    required this.fallbackGradient,
    this.isCompact = false,
    required this.onSelect,
  });

  @override
  State<SpatialPoster> createState() => SpatialPosterState();
}

class SpatialPosterState extends State<SpatialPoster> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: InkWell(
        onFocusChange: (value) => setState(() => _isHovered = value),
        onTap: widget.onSelect,
        child: AnimatedContainer(
          duration: AppMotion.duration(
            context,
            const Duration(milliseconds: 200),
          ),
          curve: Curves.easeOutCubic,
          transform: Matrix4.identity()
            ..translateByDouble(
              0.0,
              AppMotion.reduced(context) ? 0.0 : (_isHovered ? -6.0 : 0.0),
              0.0,
              1.0,
            ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.isCompact ? 11 : 15),
            border: Border.all(
              color: _isHovered
                  ? Colors.white.withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.1),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _isHovered ? 0.6 : 0.25),
                blurRadius: _isHovered ? 24 : 10,
                offset: Offset(0, _isHovered ? 12 : 5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.isCompact ? 11 : 15),
            child: Stack(
              children: [
                // 真实网络图片
                Positioned.fill(
                  child:
                      widget.image ??
                      Image.network(
                        widget.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, error, stack) => Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: widget.fallbackGradient,
                            ),
                          ),
                        ),
                      ),
                ),

                // 底部暗色遮罩与排版文本
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.15),
                          Colors.black.withValues(alpha: 0.96),
                        ],
                        stops: const [0.4, 0.62, 1.0],
                      ),
                    ),
                    padding: EdgeInsets.all(widget.isCompact ? 8 : 12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.badge,
                          style: TextStyle(
                            color: const Color(0xFFE50914),
                            fontSize: widget.isCompact ? 6.5 : 7.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.title,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: widget.isCompact ? 10 : 13,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.match,
                          style: TextStyle(
                            color: const Color(0xFF46DB78),
                            fontSize: widget.isCompact ? 7.5 : 9.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          widget.genres,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: widget.isCompact ? 7.2 : 8.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =========================================================================
// 动效组件 2: 带有 translateX(3px) 的侧边栏动画按钮
// =========================================================================
class SpatialSidebarButton extends StatefulWidget {
  final String title;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const SpatialSidebarButton({
    super.key,
    required this.title,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<SpatialSidebarButton> createState() => SpatialSidebarButtonState();
}

class SpatialSidebarButtonState extends State<SpatialSidebarButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: InkWell(
        onFocusChange: (value) => setState(() => _isHovered = value),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.duration(
            context,
            const Duration(milliseconds: 180),
          ),
          curve: Curves.easeOut,
          transform: Matrix4.identity()
            ..translateByDouble(
              AppMotion.reduced(context) ? 0.0 : (_isHovered ? 3.0 : 0.0),
              0.0,
              0.0,
              1.0,
            ),
          height: 34,
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            color: widget.isActive
                ? Colors.white.withValues(alpha: 0.14)
                : (_isHovered
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.transparent),
            border: Border.all(
              color: widget.isActive
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 14.5,
                color: widget.isActive
                    ? Colors.white
                    : (_isHovered
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.55)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: widget.isActive
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: widget.isActive
                        ? Colors.white
                        : (_isHovered
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.65)),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 基础可复用通用微动效封装
class SpatialHoverBox extends StatefulWidget {
  final Widget child;
  final double hoverOffset;
  const SpatialHoverBox({
    super.key,
    required this.child,
    this.hoverOffset = -4,
  });

  @override
  State<SpatialHoverBox> createState() => SpatialHoverBoxState();
}

class SpatialHoverBoxState extends State<SpatialHoverBox> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: AppMotion.duration(
          context,
          const Duration(milliseconds: 200),
        ),
        curve: Curves.easeOut,
        transform: Matrix4.identity()
          ..translateByDouble(
            0.0,
            AppMotion.reduced(context)
                ? 0.0
                : (_hovered ? widget.hoverOffset : 0.0),
            0.0,
            1.0,
          ),
        child: widget.child,
      ),
    );
  }
}

// =========================================================================
// 环境光影与室内自绘渲染
// =========================================================================
