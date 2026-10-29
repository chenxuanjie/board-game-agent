import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_motion.dart';

final _activeNotices = Expando<_FailureNotice>();

/// A nonblocking, single top notice. Its lifetime is presentation only.
void showAppFailureNotice(BuildContext context, String message) {
  final overlay =
      Navigator.maybeOf(context, rootNavigator: true)?.overlay ??
      Overlay.maybeOf(context);
  if (overlay == null || !overlay.mounted) return;
  final current = _activeNotices[overlay];
  if (current != null && !current.closed) {
    current.message.value = (
      text: message,
      revision: current.message.value.revision + 1,
    );
    return;
  }
  final notice = _FailureNotice();
  notice.message.value = (text: message, revision: 0);
  final themes = InheritedTheme.capture(from: context, to: overlay.context);
  notice.entry = OverlayEntry(
    builder: (_) => Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: themes.wrap(_FailureNoticeContent(notice: notice)),
    ),
  );
  _activeNotices[overlay] = notice;
  overlay.insert(notice.entry);
}

class _FailureNotice {
  final message = ValueNotifier<({String text, int revision})>((
    text: '',
    revision: 0,
  ));
  late final OverlayEntry entry;
  bool closed = false;
  void close() {
    if (closed) return;
    closed = true;
    entry.remove();
    entry.dispose();
  }
}

class _FailureNoticeContent extends StatefulWidget {
  const _FailureNoticeContent({required this.notice});
  final _FailureNotice notice;
  @override
  State<_FailureNoticeContent> createState() => _FailureNoticeContentState();
}

class _FailureNoticeContentState extends State<_FailureNoticeContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(vsync: this);
  Timer? _expiry;
  bool _started = false;
  bool _swiped = false;
  int _revision = 0;
  @override
  void initState() {
    super.initState();
    widget.notice.message.addListener(_renew);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion.duration = AppMotion.duration(context, AppMotion.menu);
    _motion.reverseDuration = AppMotion.duration(context, AppMotion.exit);
    if (!_started) {
      _started = true;
      _renew();
    }
  }

  void _renew() {
    ++_revision;
    _expiry?.cancel();
    _motion.forward();
    _expiry = Timer(AppMotion.notice, _dismiss);
    if (mounted) setState(() {});
  }

  Future<void> _dismiss() async {
    final revision = _revision;
    _expiry?.cancel();
    try {
      await _motion.reverse().orCancel;
      if (mounted && revision == _revision) widget.notice.close();
    } on TickerCanceled {
      // A new failure renews the current notice, including during exit.
    }
  }

  @override
  void dispose() {
    _expiry?.cancel();
    widget.notice.message.removeListener(_renew);
    widget.notice.message.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_swiped) return const SizedBox.shrink();
    final palette = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: FadeTransition(
              opacity: _motion,
              child: SlideTransition(
                position: _motion.drive(
                  Tween(
                    begin: const Offset(0, -.12),
                    end: Offset.zero,
                  ).chain(CurveTween(curve: AppMotion.curve)),
                ),
                child: Dismissible(
                  key: ValueKey('app-failure-dismissible-$_revision'),
                  direction: DismissDirection.horizontal,
                  movementDuration: AppMotion.duration(context, AppMotion.menu),
                  resizeDuration: null,
                  onDismissed: (_) {
                    setState(() => _swiped = true);
                    widget.notice.close();
                  },
                  child: Semantics(
                    liveRegion: true,
                    child: Material(
                      key: const ValueKey('app-failure-notice'),
                      color: palette.surfaceContainer,
                      elevation: 6,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: palette.outline),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(
                          left: 14,
                          top: 4,
                          bottom: 4,
                          right: 4,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              size: 20,
                              color: palette.error,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                widget.notice.message.value.text,
                                style: TextStyle(
                                  color: palette.onSurface,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: '关闭提示',
                              onPressed: _dismiss,
                              icon: const Icon(Icons.close_rounded, size: 18),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
