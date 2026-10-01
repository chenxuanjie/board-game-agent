import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/state/app_controller.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_palette.dart';

/// A compact choice backed by the existing answer-mode preference.
class AssistantAnswerModeSelector extends StatefulWidget {
  const AssistantAnswerModeSelector({
    super.key,
    required this.controller,
    required this.useGlobalMode,
    required this.enabled,
  });
  final AppController controller;
  final bool useGlobalMode;
  final bool enabled;
  @override
  State<AssistantAnswerModeSelector> createState() =>
      _AssistantAnswerModeSelectorState();
}

class _AssistantAnswerModeSelectorState
    extends State<AssistantAnswerModeSelector> {
  bool _saving = false;
  bool _open = false;

  Future<void> _select(bool value) async {
    if (_saving ||
        value ==
            widget.controller.allowSmartSupplement(
              useGlobalMode: widget.useGlobalMode,
            )) {
      return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final copy = widget.controller.copy;
    try {
      await widget.controller.setAllowSmartSupplement(
        value,
        useGlobalMode: widget.useGlobalMode,
      );
    } catch (_) {
      if (mounted) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              copy.localized(
                '模式未保存，请重试',
                'Mode could not be saved. Try again.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final copy = widget.controller.copy;
    final smart = widget.controller.allowSmartSupplement(
      useGlobalMode: widget.useGlobalMode,
    );
    String label(bool value) => value
        ? copy.smartSupplementLabel
        : copy.localized('知识库', 'Knowledge base');
    IconData icon(bool value) =>
        value ? Icons.auto_awesome_outlined : Icons.menu_book_outlined;
    final textStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w500);
    return PopupMenuButton<bool>(
      key: const ValueKey('desktop-answer-mode-selector'),
      enabled: widget.enabled && !_saving,
      tooltip: copy.desktopAnswerModeTitle,
      popUpAnimationStyle: AppMotion.menuStyle(context),
      position: PopupMenuPosition.over,
      initialValue: smart,
      menuPadding: const EdgeInsets.all(7),
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 280),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      color: palette.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: palette.shadow.withValues(alpha: .18),
      elevation: 12,
      onOpened: () => setState(() => _open = true),
      onCanceled: () => setState(() => _open = false),
      onSelected: (value) {
        setState(() => _open = false);
        unawaited(_select(value));
      },
      itemBuilder: (_) => [
        for (final value in [false, true])
          _RoundedModeEntry(
            key: ValueKey(
              value ? 'assistant-mode-smart' : 'assistant-mode-knowledge',
            ),
            value: value,
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Semantics(
              selected: value == smart,
              child: Row(
                children: [
                  Icon(
                    icon(value),
                    size: 22,
                    color: value == smart
                        ? palette.primary
                        : palette.textSecondary,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      label(value),
                      style: textStyle?.copyWith(
                        fontSize: 16,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  if (value == smart)
                    Icon(Icons.check_rounded, size: 20, color: palette.primary)
                  else
                    const SizedBox(width: 20),
                ],
              ),
            ),
          ),
      ],
      child: AnimatedContainer(
        duration: AppMotion.duration(context),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: _open
              ? palette.primaryContainer.withValues(alpha: .45)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_saving)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: palette.primary,
                ),
              )
            else
              Icon(icon(smart), color: palette.primary, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label(smart),
                style: textStyle?.copyWith(color: palette.textPrimary),
              ),
            ),
            const SizedBox(width: 5),
            AnimatedRotation(
              turns: _open ? .5 : 0,
              duration: AppMotion.duration(context),
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: palette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Clip the framework's ink/focus treatment to each rounded option.
class _RoundedModeEntry extends PopupMenuItem<bool> {
  const _RoundedModeEntry({
    super.key,
    required super.value,
    required super.child,
    super.height,
    super.padding,
  });
  @override
  PopupMenuItemState<bool, _RoundedModeEntry> createState() =>
      _RoundedModeEntryState();
}

class _RoundedModeEntryState
    extends PopupMenuItemState<bool, _RoundedModeEntry> {
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: super.build(context),
  );
}
