import 'dart:io';

import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../../theme/app_palette.dart';

/// Resolves a logical asset path through the controller's remote/cache layer.
///
/// This widget is intentionally used by the Windows workspace only. It keeps
/// the remote lookup out of the UI and always provides a visual fallback while
/// an image is loading, unavailable, or invalid.
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
    _pathFuture = widget.controller.resolveImagePath(widget.assetPath);
  }

  @override
  void didUpdateWidget(covariant DesktopResolvedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.assetPath != widget.assetPath) {
      _pathFuture = widget.controller.resolveImagePath(widget.assetPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: FutureBuilder<String?>(
        future: _pathFuture,
        builder: (BuildContext context, AsyncSnapshot<String?> snapshot) {
          final String? path = snapshot.data;
          if (snapshot.hasError || path == null || path.isEmpty) {
            return _placeholder(context);
          }
          return Image.file(
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
