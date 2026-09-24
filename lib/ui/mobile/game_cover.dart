import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../features/games/models/game_info.dart';
import '../../app/state/app_controller.dart';

class MobileGameCover extends StatefulWidget {
  const MobileGameCover({
    super.key,
    required this.controller,
    required this.game,
  });

  final AppController controller;
  final GameInfo game;

  @override
  State<MobileGameCover> createState() => _MobileGameCoverState();
}

class _MobileGameCoverState extends State<MobileGameCover> {
  String? _resolvedPath;
  bool _resolving = false;
  bool _resolutionAttempted = false;
  int _resolutionGeneration = 0;

  @override
  void didUpdateWidget(covariant MobileGameCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.game.coverAssetPath != widget.game.coverAssetPath ||
        oldWidget.controller != widget.controller) {
      _resolvedPath = null;
      _resolving = false;
      _resolutionAttempted = false;
      _resolutionGeneration += 1;
    }
  }

  Future<void> _resolveRemote() async {
    if (kIsWeb || _resolving || _resolutionAttempted) return;
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
  Widget build(BuildContext context) {
    final assetPath = widget.game.coverAssetPath;
    if (assetPath.isEmpty) {
      _resolveRemote();
      return _cachedOrPlaceholder();
    }
    return Image.asset(
      assetPath,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, _, _) {
        _resolveRemote();
        return _cachedOrPlaceholder();
      },
    );
  }

  Widget _cachedOrPlaceholder() {
    final path = _resolvedPath;
    if (kIsWeb || path == null || path.isEmpty) return _placeholder();
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, _, _) => _placeholder(),
    );
  }

  Widget _placeholder() => const ColoredBox(
    color: Color(0xFFF5E9DD),
    child: Center(child: Icon(Icons.casino_rounded, color: Color(0xFFCE8A66))),
  );
}
