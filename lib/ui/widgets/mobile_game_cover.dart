import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/game_info.dart';
import '../../state/app_controller.dart';

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
  late Future<String?> _resolvedPath;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant MobileGameCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.game.coverAssetPath != widget.game.coverAssetPath ||
        oldWidget.controller != widget.controller) {
      _resolve();
    }
  }

  void _resolve() {
    _resolvedPath = widget.controller.resolveImagePath(
      widget.game.coverAssetPath,
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: _resolvedPath,
    builder: (context, snapshot) {
      final path = snapshot.data;
      if (path == null || path.isEmpty) return _placeholder();
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    },
  );

  Widget _placeholder() => const ColoredBox(
    color: Color(0xFFF5E9DD),
    child: Center(child: Icon(Icons.casino_rounded, color: Color(0xFFCE8A66))),
  );
}
