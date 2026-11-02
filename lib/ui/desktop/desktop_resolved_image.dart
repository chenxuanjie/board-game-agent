import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter/material.dart';
import '../shared/game_cover_motion.dart';
import '../shared/image_reveal.dart';

import '../../app/state/app_controller.dart';
import '../../core/theme/app_palette.dart';

/// Resolves a logical asset path through the controller's remote/cache layer.
///
/// Native workspaces use the verified file cache; Web uses public same-origin
/// resource URLs. Both resolve through the current SQL publication.
class DesktopResolvedImage extends StatefulWidget {
  const DesktopResolvedImage({
    super.key,
    required this.controller,
    required this.assetPath,
    required this.palette,
    this.placeholderBuilder,
    this.continuityImage,
    this.fit = BoxFit.cover,
  });

  final AppController controller;
  final String assetPath;
  final AppPalette palette;
  final WidgetBuilder? placeholderBuilder;
  final Widget? continuityImage;
  final BoxFit fit;

  @override
  State<DesktopResolvedImage> createState() => _DesktopResolvedImageState();
}

class _DesktopResolvedImageState extends State<DesktopResolvedImage> {
  late Future<String?> _pathFuture;
  int _revision = 0;
  void _refreshContent() {
    final next = widget.controller.libraryContentRevision;
    if (next == _revision) return;
    _revision = next;
    setState(
      () => _pathFuture = widget.controller.resolveImagePath(widget.assetPath),
    );
  }

  @override
  void initState() {
    super.initState();
    _revision = widget.controller.libraryContentRevision;
    widget.controller.addListener(_refreshContent);
    _pathFuture = widget.controller.resolveImagePath(widget.assetPath);
  }

  @override
  void didUpdateWidget(covariant DesktopResolvedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.assetPath != widget.assetPath) {
      if (oldWidget.controller != widget.controller) {
        oldWidget.controller.removeListener(_refreshContent);
        widget.controller.addListener(_refreshContent);
      }
      _revision = widget.controller.libraryContentRevision;
      _pathFuture = widget.controller.resolveImagePath(widget.assetPath);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refreshContent);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _image(context);

  Widget _image(BuildContext context) {
    return SizedBox.expand(
      child: FutureBuilder<String?>(
        future: _pathFuture,
        builder: (BuildContext context, AsyncSnapshot<String?> snapshot) {
          Widget source(Widget child) =>
              GameCoverSource(path: widget.assetPath, child: child);
          final String? path = snapshot.data;
          if (snapshot.connectionState != ConnectionState.done &&
              path == null &&
              !kIsWeb) {
            return source(
              widget.continuityImage ?? const ImageLoadingPlaceholder(),
            );
          }
          if (snapshot.hasError || path == null || path.isEmpty) {
            return source(
              snapshot.connectionState != ConnectionState.done
                  ? widget.continuityImage ?? _placeholder(context)
                  : _placeholder(context),
            );
          }
          if (path.startsWith('https://') || path.startsWith('http://')) {
            return source(
              Image.network(
                path,
                gaplessPlayback: true,
                fit: widget.fit,
                frameBuilder: _frameBuilder,
                errorBuilder: (_, _, _) => _placeholder(context),
              ),
            );
          }
          if (path.startsWith('data:')) {
            return source(
              Image.memory(
                gaplessPlayback: true,
                Uri.parse(path).data!.contentAsBytes(),
                fit: widget.fit,
                frameBuilder: _frameBuilder,
                errorBuilder: (_, _, _) => _placeholder(context),
              ),
            );
          }
          return source(
            Image.file(
              gaplessPlayback: true,
              frameBuilder: _frameBuilder,
              File(path),
              fit: widget.fit,
              errorBuilder:
                  (
                    BuildContext context,
                    Object error,
                    StackTrace? stackTrace,
                  ) => _placeholder(context),
            ),
          );
        },
      ),
    );
  }

  Widget _frameBuilder(
    BuildContext context,
    Widget child,
    int? frame,
    bool synchronous,
  ) {
    final fallback = widget.continuityImage;
    if (fallback != null) return frame == null ? fallback : child;
    return revealImageFrame(context, child, frame, synchronous);
  }

  Widget _placeholder(BuildContext context) {
    return widget.placeholderBuilder?.call(context) ??
        DecoratedBox(
          decoration: BoxDecoration(color: widget.palette.surfaceVariant),
          child: Center(
            child: Icon(
              Icons.image_not_supported_outlined,
              size: 38,
              color: widget.palette.textSecondary,
            ),
          ),
        );
  }
}
