import 'package:flutter/material.dart';
import '../../core/theme/app_motion.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_responsive.dart';

class WindowControls extends StatefulWidget {
  const WindowControls({super.key, this.spatial = false});
  final bool spatial;

  @override
  State<WindowControls> createState() => _WindowControlsState();
}

class _WindowControlsState extends State<WindowControls> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _syncMaximizedState();
  }

  Future<void> _syncMaximizedState() async {
    final maximized = await windowManager.isMaximized();
    if (mounted && maximized != _isMaximized) {
      setState(() => _isMaximized = maximized);
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  @override
  void onWindowRestore() {
    _syncMaximizedState();
  }

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WindowButton(
          spatial: widget.spatial,
          icon: Icons.remove_rounded,
          tooltip: '最小化',
          onTap: windowManager.minimize,
        ),
        _WindowButton(
          spatial: widget.spatial,
          icon: _isMaximized
              ? Icons.filter_none_rounded
              : Icons.crop_square_rounded,
          tooltip: _isMaximized ? '还原' : '最大化',
          onTap: _toggleMaximize,
        ),
        _WindowButton(
          spatial: widget.spatial,
          icon: Icons.close_rounded,
          tooltip: '关闭',
          danger: true,
          onTap: windowManager.close,
        ),
      ],
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final Future<void> Function() onTap;
  final bool danger;
  final bool spatial;

  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
    this.spatial = false,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool hovering = false;
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    final metrics = DesktopMetricsScope.of(context);
    final bg = !hovering && !focused
        ? Colors.transparent
        : widget.danger
        ? const Color(0xFFE94D4D)
        : widget.spatial
        ? Colors.white.withValues(alpha: .10)
        : const Color(0x11000000);
    final fg = widget.danger && (hovering || focused)
        ? Colors.white
        : widget.spatial
        ? Colors.white.withValues(alpha: .72)
        : const Color(0xFF6B625A);

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => hovering = true),
        onExit: (_) => setState(() => hovering = false),
        child: InkWell(
          borderRadius: widget.spatial ? BorderRadius.circular(8) : null,
          onTap: () => widget.onTap(),
          onFocusChange: (value) => setState(() => focused = value),
          child: AnimatedContainer(
            duration: AppMotion.duration(context, AppMotion.feedback),
            width: widget.spatial ? 38 : metrics.px(50),
            height: widget.spatial ? 30 : metrics.px(32),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: widget.spatial ? BorderRadius.circular(8) : null,
            ),
            child: Icon(widget.icon, size: metrics.px(15), color: fg),
          ),
        ),
      ),
    );
  }
}
