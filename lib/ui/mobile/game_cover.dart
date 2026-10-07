import 'dart:io';

import 'package:flutter/material.dart';
import '../shared/game_cover_motion.dart';
import '../shared/image_reveal.dart';

import '../../features/games/models/game_info.dart';
import '../../app/state/app_controller.dart';

class MobileGameCover extends StatefulWidget {
  const MobileGameCover({
    super.key,
    required this.controller,
    required this.game,
    this.fit = BoxFit.cover,
  });

  final AppController controller;
  final GameInfo game;
  final BoxFit fit;

  @override
  State<MobileGameCover> createState() => _MobileGameCoverState();
}

class _MobileGameCoverState extends State<MobileGameCover> {
  String? _resolvedPath;
  bool _resolving = false;
  bool _resolutionAttempted = false;
  int _resolutionGeneration = 0;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _revision = widget.controller.libraryContentRevision;
    widget.controller.addListener(_refreshContent);
    _resolveRemote();
  }

  void _refreshContent() {
    if (_revision == widget.controller.libraryContentRevision) return;
    _revision = widget.controller.libraryContentRevision;
    _resolvedPath = null;
    _resolutionAttempted = false;
    _resolving = false;
    _resolutionGeneration++;
    _resolveRemote();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refreshContent);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MobileGameCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.game.coverAssetPath != widget.game.coverAssetPath ||
        oldWidget.controller != widget.controller) {
      if (oldWidget.controller != widget.controller) {
        oldWidget.controller.removeListener(_refreshContent);
        widget.controller.addListener(_refreshContent);
      }
      _resolvedPath = null;
      _resolving = false;
      _resolutionAttempted = false;
      _resolutionGeneration += 1;
      _resolveRemote();
    }
  }

  Future<void> _resolveRemote() async {
    if (_resolving || _resolutionAttempted) return;
    _resolving = true;
    final generation = _resolutionGeneration;
    String? path;
    try {
      path = await widget.controller.resolveImagePath(
        widget.game.coverAssetPath,
      );
    } catch (_) {
      path = null;
    }
    if (!mounted || generation != _resolutionGeneration) return;
    setState(() {
      _resolvedPath = path;
      _resolving = false;
      _resolutionAttempted = true;
    });
  }

  @override
  Widget build(BuildContext context) =>
      GameCoverSource(path: widget.game.coverAssetPath, child: _image(context));

  Widget _image(BuildContext context) {
    final assetPath = widget.game.coverAssetPath;
    if (_resolvedPath != null) return _cachedOrPlaceholder();
    if (assetPath.isEmpty) {
      _resolveRemote();
      return _cachedOrPlaceholder();
    }
    return Image.asset(
      frameBuilder: revealImageFrame,
      assetPath,
      fit: widget.fit,
      width: widget.fit == BoxFit.contain ? null : double.infinity,
      height: widget.fit == BoxFit.contain ? null : double.infinity,
      errorBuilder: (_, _, _) {
        _resolveRemote();
        return _cachedOrPlaceholder();
      },
    );
  }

  Widget _cachedOrPlaceholder() {
    final path = _resolvedPath;
    if (path == null || path.isEmpty) return _placeholder();
    if (path.startsWith('data:')) {
      return Image.memory(
        Uri.parse(path).data!.contentAsBytes(),
        frameBuilder: revealImageFrame,
        fit: widget.fit,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    }
    return Image.file(
      frameBuilder: revealImageFrame,
      File(path),
      fit: widget.fit,
      width: widget.fit == BoxFit.contain ? null : double.infinity,
      height: widget.fit == BoxFit.contain ? null : double.infinity,
      errorBuilder: (_, _, _) => _placeholder(),
    );
  }

  Widget _placeholder() => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: Center(
      child: Icon(
        Icons.casino_rounded,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
