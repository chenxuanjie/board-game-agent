import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../state/app_controller.dart';

class PdfDocumentScreen extends StatelessWidget {
  const PdfDocumentScreen({
    super.key,
    required this.controller,
    required this.assetPath,
    required this.title,
  });

  final AppController controller;
  final String assetPath;
  final String title;

  @override
  Widget build(BuildContext context) {
    final palette = controller.palette;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      backgroundColor: palette.detailOverlayBottom,
      body: DecoratedBox(
        decoration: BoxDecoration(color: palette.detailOverlayBottom),
        child: PdfViewer.asset(
          assetPath,
          params: PdfViewerParams(
            backgroundColor: palette.detailOverlayBottom,
            margin: 10,
            minScale: 1.0,
            maxScale: 5.0,
          ),
        ),
      ),
    );
  }
}
