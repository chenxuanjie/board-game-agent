import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_palette.dart';

/// Reveals the requested settings section and briefly outlines its destination.
class SettingsSectionFocus extends StatefulWidget {
  const SettingsSectionFocus({
    super.key,
    required this.child,
    this.reveal = false,
  });
  final Widget child;
  final bool reveal;
  @override
  State<SettingsSectionFocus> createState() => _SettingsSectionFocusState();
}

class _SettingsSectionFocusState extends State<SettingsSectionFocus> {
  Timer? _timer;
  bool _highlight = false;
  @override
  void initState() {
    super.initState();
    if (widget.reveal) _reveal();
  }

  @override
  void didUpdateWidget(SettingsSectionFocus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reveal && !oldWidget.reveal) _reveal();
  }

  void _reveal() {
    _highlight = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        alignment: .08,
        duration: AppMotion.duration(context, AppMotion.menu),
      );
      _timer?.cancel();
      _timer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _highlight = false);
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    key: const ValueKey('ai-settings-highlight'),
    duration: AppMotion.duration(context),
    foregroundDecoration: BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        width: 2,
        color: _highlight ? AppPalette.of(context).primary : Colors.transparent,
      ),
    ),
    child: widget.child,
  );
}
