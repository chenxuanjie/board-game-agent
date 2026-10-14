import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// Paints the complete client surface with antialiased corners over the host's
/// transparent composition surface. No OS window region or scene margin.
class NativeWindowSurface extends StatefulWidget {
  const NativeWindowSurface({
    super.key,
    required this.enabled,
    required this.child,
  });
  final bool enabled;
  final Widget child;
  static const radius = 32.0;
  @override
  State<NativeWindowSurface> createState() => _NativeWindowSurfaceState();
}

class _NativeWindowSurfaceState extends State<NativeWindowSurface>
    with WindowListener {
  // A closing/replaced host cannot restore opacity after its successor enables
  // transparency. Serialize and coalesce even across widget instances.
  static Future<void>? _hostWrites;
  static int _hostRevision = 0;
  bool _transparent = false,
      _maximized = false,
      _fullscreen = false,
      _docked = false;
  bool _boundsKnown = false;
  int _boundsRevision = 0;
  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  late final bool _listening;

  @override
  void initState() {
    super.initState();
    _listening = _supported;
    if (_listening) {
      windowManager.addListener(this);
      if (widget.enabled) {
        _requestSurface(true);
        unawaited(_readBounds());
      }
    }
  }

  void _requestSurface(bool enabled) {
    final revision = ++_hostRevision;
    late final Future<void> write;
    write = (_hostWrites ?? Future<void>.value())
        .then((_) async {
          if (revision != _hostRevision) return;
          try {
            if (enabled) {
              // Hidden title bars still retain non-client insets in window_manager;
              // a client-drawn rounded surface needs the complete frameless client.
              await windowManager.setAsFrameless().timeout(
                const Duration(seconds: 5),
              );
            } else {
              await windowManager
                  .setTitleBarStyle(
                    TitleBarStyle.hidden,
                    windowButtonVisibility: false,
                  )
                  .timeout(const Duration(seconds: 5));
            }
            await windowManager
                .setBackgroundColor(
                  enabled ? const Color(0x00000000) : const Color(0xFF000000),
                )
                .timeout(const Duration(seconds: 5));
            if (mounted &&
                revision == _hostRevision &&
                widget.enabled == enabled) {
              setState(() => _transparent = enabled);
            }
          } on MissingPluginException {
            await _surfaceFailed(revision);
          } on PlatformException {
            await _surfaceFailed(revision);
          } on TimeoutException {
            await _surfaceFailed(revision);
          }
        })
        .whenComplete(() {
          if (identical(_hostWrites, write)) {
            _hostWrites = null;
          }
        });
    _hostWrites = write;
  }

  Future<void> _surfaceFailed(int revision) async {
    if (mounted && revision == _hostRevision) {
      setState(() => _transparent = false);
    }
    debugPrint('窗口透明合成未就绪，保留矩形界面');
    if (revision != _hostRevision) return;
    try {
      await windowManager
          .setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false)
          .timeout(const Duration(seconds: 5));
    } on MissingPluginException {
      // A host without the window plugin has no altered frame to restore.
    } on PlatformException {
      debugPrint('恢复窗口框架失败');
    } on TimeoutException {
      debugPrint('恢复窗口框架超时');
    }
  }

  Future<void> _readBounds() async {
    final revision = ++_boundsRevision;
    try {
      final states = await Future.wait<Object?>([
        windowManager.isMaximized(),
        windowManager.isFullScreen(),
        windowManager.isDocked(),
      ]).timeout(const Duration(seconds: 5));
      if (!mounted || revision != _boundsRevision) return;
      setState(() {
        _maximized = states[0] as bool;
        _fullscreen = states[1] as bool;
        _docked = states[2] != null;
        _boundsKnown = true;
      });
    } on MissingPluginException {
      // Older hosts keep their rectangular surface until state is known.
    } on PlatformException {
      // Lifecycle events still provide state if a query is unavailable.
    } on TimeoutException {
      debugPrint('窗口状态查询超时');
    }
  }

  void _boundsChanged(VoidCallback update) {
    ++_boundsRevision;
    if (mounted) {
      setState(() {
        update();
        _boundsKnown = true;
      });
    }
  }

  @override
  void onWindowMaximize() => _boundsChanged(() => _maximized = true);
  @override
  void onWindowUnmaximize() => _boundsChanged(() => _maximized = false);
  @override
  void onWindowEnterFullScreen() => _boundsChanged(() => _fullscreen = true);
  @override
  void onWindowLeaveFullScreen() => _boundsChanged(() => _fullscreen = false);
  @override
  void onWindowDocked() => _boundsChanged(() => _docked = true);
  @override
  void onWindowUndocked() => _boundsChanged(() => _docked = false);
  @override
  void onWindowRestore() {
    if (widget.enabled) unawaited(_readBounds());
  }

  @override
  void didUpdateWidget(covariant NativeWindowSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_listening && oldWidget.enabled != widget.enabled) {
      _requestSurface(widget.enabled);
      if (widget.enabled) {
        _boundsKnown = false;
        unawaited(_readBounds());
      }
    }
  }

  @override
  void dispose() {
    if (_listening) {
      windowManager.removeListener(this);
      if (widget.enabled) _requestSurface(false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_listening || !widget.enabled || !_transparent || !_boundsKnown) {
      return widget.child;
    }
    return ClipRRect(
      key: const ValueKey('native-rounded-surface'),
      borderRadius: BorderRadius.circular(
        _maximized || _fullscreen || _docked ? 0 : NativeWindowSurface.radius,
      ),
      clipBehavior: Clip.antiAlias,
      child: widget.child,
    );
  }
}
