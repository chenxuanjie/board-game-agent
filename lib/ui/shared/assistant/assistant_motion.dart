import 'package:flutter/material.dart';
import '../../../core/theme/app_motion.dart';

/// Keeps one live message list while conversation changes animate. Only the
/// noninteractive welcome illustration may linger briefly after first send.
class AssistantConversationTransition extends StatefulWidget {
  const AssistantConversationTransition({
    super.key,
    required this.identity,
    required this.compact,
    required this.showWelcome,
    required this.welcome,
    required this.messages,
    this.onMetricsChanged,
  });
  final Object identity;
  final bool compact;
  final bool showWelcome;
  final Widget welcome;
  final Widget messages;
  final VoidCallback? onMetricsChanged;

  @override
  State<AssistantConversationTransition> createState() =>
      _AssistantConversationTransitionState();
}

class _AssistantConversationTransitionState
    extends State<AssistantConversationTransition>
    with TickerProviderStateMixin {
  late final _entrance = AnimationController(
    vsync: this,
    duration: AppMotion.content,
    value: 1,
  );
  late final _exit = AnimationController(
    vsync: this,
    duration: AppMotion.exit,
    value: 1,
  )..addStatusListener(_exitChanged);
  late final _opacity = _entrance.drive(CurveTween(curve: AppMotion.curve));
  late final _welcomeOpacity = _exit.drive(
    Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: AppMotion.curve)),
  );
  Widget? _departingWelcome;
  bool _metricsPending = false;

  bool _metricsChanged(ScrollMetricsNotification notification) {
    if (!_metricsPending && widget.onMetricsChanged != null) {
      _metricsPending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _metricsPending = false;
        if (mounted) widget.onMetricsChanged?.call();
      });
    }
    return false;
  }

  void _exitChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed && _departingWelcome != null) {
      setState(() => _departingWelcome = null);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _entrance.value = 1;
      _departingWelcome = null;
      _exit.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant AssistantConversationTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed = oldWidget.identity != widget.identity;
    final firstSend = !changed && oldWidget.showWelcome && !widget.showWelcome;
    if (changed || firstSend) {
      _departingWelcome = null;
      _exit.stop();
      if (AppMotion.reduced(context)) {
        _entrance.value = 1;
      } else {
        if (firstSend) {
          _departingWelcome = oldWidget.welcome;
          _exit.forward(from: 0);
        }
        _entrance.forward(from: .35);
      }
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: _metricsChanged,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FadeTransition(
              key: const ValueKey('assistant-conversation-transition'),
              opacity: _opacity,
              child: AnimatedBuilder(
                animation: _opacity,
                builder: (context, child) => Transform.translate(
                  offset: Offset(
                    0,
                    widget.compact ? 6 * (1 - _opacity.value) : 0,
                  ),
                  child: child,
                ),
                child: widget.showWelcome ? widget.welcome : widget.messages,
              ),
            ),
            if (_departingWelcome != null)
              IgnorePointer(
                child: ExcludeFocus(
                  child: ExcludeSemantics(
                    child: FadeTransition(
                      key: const ValueKey('assistant-welcome-exit'),
                      opacity: _welcomeOpacity,
                      child: _departingWelcome,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

/// Initial history is immediately readable; only newly available details grow.
class AssistantResponseReveal extends StatelessWidget {
  const AssistantResponseReveal({
    super.key,
    required this.visible,
    required this.child,
  });
  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: AnimatedSize(
      duration: AppMotion.duration(context, AppMotion.content),
      curve: AppMotion.curve,
      alignment: Alignment.topLeft,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: AppMotion.duration(context),
        curve: AppMotion.curve,
        child: visible ? child : const SizedBox.shrink(),
      ),
    ),
  );
}

class AssistantHistoryRemoval extends StatelessWidget {
  const AssistantHistoryRemoval({
    super.key,
    required this.removing,
    required this.onRemoved,
    required this.child,
  });
  final bool removing;
  final VoidCallback onRemoved;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: removing,
    child: ExcludeSemantics(
      excluding: removing,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 1, end: removing ? 0 : 1),
        duration: removing
            ? AppMotion.duration(context, AppMotion.content)
            : Duration.zero,
        curve: AppMotion.curve,
        onEnd: removing ? onRemoved : null,
        child: child,
        builder: (context, value, child) => ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: value,
            child: Opacity(opacity: value, child: child),
          ),
        ),
      ),
    ),
  );
}

/// A keyed entrance is played once, never once per streamed text delta.
class AssistantMessageEntrance extends StatelessWidget {
  const AssistantMessageEntrance({
    super.key,
    required this.child,
    this.animate = true,
  });
  final Widget child;
  final bool animate;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: animate ? 0 : 1, end: 1),
    duration: AppMotion.duration(context),
    curve: AppMotion.curve,
    child: child,
    builder: (context, value, child) => Opacity(
      opacity: value,
      child: Transform.translate(
        offset: Offset(0, 6 * (1 - value)),
        child: child,
      ),
    ),
  );
}
