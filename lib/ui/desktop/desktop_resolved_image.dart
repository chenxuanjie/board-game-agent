import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../shared/game_cover_motion.dart';
import '../shared/image_reveal.dart';

import '../../app/state/app_controller.dart';
import '../../core/theme/app_palette.dart';

/// Resolves a logical asset path through the controller's remote/cache layer.
///
/// Native workspaces use the controller's file cache; wide Web uses bundled
/// asset URLs because browsers cannot read a native filesystem cache.
class DesktopResolvedImage extends StatefulWidget {
  const DesktopResolvedImage({
    super.key,
    required this.controller,
    required this.assetPath,
    required this.palette,
    this.placeholderBuilder,
    this.fit = BoxFit.cover,
  });

  final AppController controller;
  final String assetPath;
  final AppPalette palette;
  final WidgetBuilder? placeholderBuilder;
  final BoxFit fit;

  @override
  State<DesktopResolvedImage> createState() => _DesktopResolvedImageState();
}

class _DesktopResolvedImageState extends State<DesktopResolvedImage> {
  late Future<String?> _pathFuture;

  @override
  void initState() {
    super.initState();
    _pathFuture = kIsWeb
        ? Future.value(null)
        : widget.controller.resolveImagePath(widget.assetPath);
  }

  @override
  void didUpdateWidget(covariant DesktopResolvedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.assetPath != widget.assetPath) {
      _pathFuture = kIsWeb
          ? Future.value(null)
          : widget.controller.resolveImagePath(widget.assetPath);
    }
  }

  @override
  Widget build(BuildContext context) =>
      GameCoverSource(path: widget.assetPath, child: _image(context));

  Widget _image(BuildContext context) {
    if (kIsWeb) {
      if (widget.assetPath.trim().isEmpty) return _placeholder(context);
      return SizedBox.expand(
        child: Image.asset(
          widget.assetPath,
          fit: widget.fit,
          frameBuilder: revealImageFrame,
          errorBuilder: (_, _, _) => _placeholder(context),
        ),
      );
    }
    return SizedBox.expand(
      child: FutureBuilder<String?>(
        future: _pathFuture,
        builder: (BuildContext context, AsyncSnapshot<String?> snapshot) {
          final String? path = snapshot.data;
          if (snapshot.hasError || path == null || path.isEmpty) {
            return _placeholder(context);
          }
          return Image.file(
            frameBuilder: revealImageFrame,
            File(path),
            fit: widget.fit,
            errorBuilder:
                (BuildContext context, Object error, StackTrace? stackTrace) =>
                    _placeholder(context),
          );
        },
      ),
    );
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
