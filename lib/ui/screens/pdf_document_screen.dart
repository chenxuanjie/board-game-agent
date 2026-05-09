import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../state/app_controller.dart';

class PdfDocumentScreen extends StatefulWidget {
  const PdfDocumentScreen({
    super.key,
    required this.controller,
    required this.remotePath,
    required this.title,
  });

  final AppController controller;
  final String remotePath;
  final String title;

  @override
  State<PdfDocumentScreen> createState() => _PdfDocumentScreenState();
}

class _PdfDocumentScreenState extends State<PdfDocumentScreen> {
  late Future<String?> _localPathFuture;

  @override
  void initState() {
    super.initState();
    _localPathFuture = widget.controller.cacheDocument(widget.remotePath);
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.controller.palette;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      backgroundColor: palette.detailOverlayBottom,
      body: FutureBuilder<String?>(
        future: _localPathFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Center(
              child: Text(
                'PDF 加载失败：${snapshot.error ?? '未找到缓存或远端资源'}',
              ),
            );
          }
          return DecoratedBox(
            decoration: BoxDecoration(color: palette.detailOverlayBottom),
            child: PdfViewer.file(
              snapshot.data!,
              params: PdfViewerParams(
                backgroundColor: palette.detailOverlayBottom,
                margin: 10,
                minScale: 1.0,
                maxScale: 5.0,
              ),
            ),
          );
        },
      ),
    );
  }
}
