import 'package:flutter/material.dart';

import '../../state/app_controller.dart';

class DocumentInfoScreen extends StatelessWidget {
  const DocumentInfoScreen({
    super.key,
    required this.controller,
    required this.title,
    required this.description,
  });

  final AppController controller;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final palette = controller.palette;
    final cardTextColor =
        ThemeData.estimateBrightnessForColor(palette.cardSurface) ==
            Brightness.dark
        ? Colors.white
        : const Color(0xFF173B52);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      backgroundColor: palette.detailOverlayBottom,
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: <Widget>[
          Card(
            color: palette.cardSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(color: cardTextColor),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: cardTextColor.withValues(alpha: 0.86),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
