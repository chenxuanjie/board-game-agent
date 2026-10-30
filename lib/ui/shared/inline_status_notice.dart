import 'dart:async';
import 'package:flutter/material.dart';

import '../../core/theme/app_motion.dart';
import '../../core/theme/ui_tokens.dart';

/// A transient, nonblocking status lane. Blocking page failures retain their
/// own recovery control instead of relying on this dismissible presentation.
class InlineStatusNotice extends StatefulWidget {
  const InlineStatusNotice({
    super.key,
    required this.message,
    required this.revision,
    required this.onDismiss,
    this.onRetry,
    this.retryLabel = '重试',
    this.dismissLabel = '关闭提示',
    this.keyPrefix = 'status',
    this.loading = false,
  });
  final String message;
  final Object revision;
  final VoidCallback onDismiss;
  final Future<void> Function()? onRetry;
  final String retryLabel;
  final String dismissLabel;
  final String keyPrefix;
  final bool loading;

  @override
  State<InlineStatusNotice> createState() => _InlineStatusNoticeState();
}

class _InlineStatusNoticeState extends State<InlineStatusNotice>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(vsync: this, value: 1);
  Timer? _expiry;
  bool _hovered = false, _focused = false, _touching = false;
  bool _retrying = false, _hidden = false, _closing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion.duration = AppMotion.duration(context, AppMotion.menu);
    _motion.reverseDuration = AppMotion.duration(context, AppMotion.exit);
    _arm();
  }

  @override
  void didUpdateWidget(covariant InlineStatusNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.revision != oldWidget.revision ||
        widget.loading != oldWidget.loading) {
      _hidden = _closing = false;
      _motion.forward();
      _arm();
    }
  }

  void _arm() {
    _expiry?.cancel();
    if (_hidden ||
        _closing ||
        widget.loading ||
        _retrying ||
        _hovered ||
        _focused ||
        _touching ||
        MediaQuery.accessibleNavigationOf(context)) {
      return;
    }
    _expiry = Timer(AppMotion.notice, _dismiss);
  }

  Future<void> _dismiss() async {
    if (_closing || _hidden || widget.loading) return;
    _closing = true;
    _expiry?.cancel();
    try {
      await _motion.reverse().orCancel;
      if (!mounted || !_closing) return;
      setState(() => _hidden = true);
      widget.onDismiss();
    } on TickerCanceled {
      // A new attempt or disposal superseded this presentation.
    }
  }

  Future<void> _retry() async {
    if (_retrying || widget.onRetry == null) return;
    setState(() => _retrying = true);
    _arm();
    try {
      await widget.onRetry!();
    } catch (_) {
      // The caller owns the failure state and its message.
    } finally {
      if (mounted) {
        setState(() => _retrying = false);
        _arm();
      }
    }
  }

  @override
  void dispose() {
    _expiry?.cancel();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final busy = widget.loading || _retrying;
    final actions = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (widget.onRetry != null)
          TextButton.icon(
            key: ValueKey('${widget.keyPrefix}-retry'),
            onPressed: busy ? null : _retry,
            icon: busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 18),
            label: Text(widget.retryLabel),
          ),
        if (!widget.loading)
          IconButton(
            key: ValueKey('${widget.keyPrefix}-dismiss'),
            tooltip: widget.dismissLabel,
            onPressed: _dismiss,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
      ],
    );
    final content = Padding(
      padding: const EdgeInsets.only(bottom: UiTokens.itemGap),
      child: Material(
        color: widget.loading
            ? colors.surfaceContainerHighest
            : colors.error.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(UiTokens.controlRadius),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: LayoutBuilder(
            builder: (context, box) {
              final text = Row(
                children: [
                  if (widget.loading)
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      Icons.error_outline_rounded,
                      color: colors.error,
                      size: 22,
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.message,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              );
              return box.maxWidth < 480 ||
                      MediaQuery.textScalerOf(context).scale(14) > 20
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        text,
                        Align(alignment: Alignment.centerRight, child: actions),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: text),
                        actions,
                      ],
                    );
            },
          ),
        ),
      ),
    );
    return MouseRegion(
      onEnter: (_) {
        _hovered = true;
        _arm();
      },
      onExit: (_) {
        _hovered = false;
        _arm();
      },
      child: Focus(
        canRequestFocus: false,
        onFocusChange: (focused) {
          _focused = focused;
          _arm();
        },
        child: Listener(
          onPointerDown: (_) {
            _touching = true;
            _arm();
          },
          onPointerUp: (_) {
            _touching = false;
            _arm();
          },
          onPointerCancel: (_) {
            _touching = false;
            _arm();
          },
          child: SizeTransition(
            sizeFactor: _motion.drive(CurveTween(curve: AppMotion.curve)),
            axisAlignment: -1,
            child: FadeTransition(
              opacity: _motion,
              child: Semantics(
                liveRegion: true,
                child: Dismissible(
                  key: ValueKey('${widget.keyPrefix}-swipe-${widget.revision}'),
                  direction: widget.loading
                      ? DismissDirection.none
                      : DismissDirection.horizontal,
                  movementDuration: AppMotion.duration(context, AppMotion.menu),
                  resizeDuration: AppMotion.duration(context, AppMotion.exit),
                  onDismissed: (_) {
                    _expiry?.cancel();
                    setState(() => _hidden = true);
                    widget.onDismiss();
                  },
                  child: content,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
