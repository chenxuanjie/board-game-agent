import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../state/app_controller.dart';
import '../../theme/app_palette.dart';

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
  final PdfViewerController _pdfController = PdfViewerController();
  late Future<String?> _localPathFuture;
  int _currentPage = 1;
  int _totalPages = 0;

  @override
  void initState() {
    super.initState();
    _localPathFuture = widget.controller.cacheDocument(widget.remotePath);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final copy = widget.controller.copy;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      backgroundColor: palette.pageBackground,
      body: FutureBuilder<String?>(
        future: _localPathFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Center(child: Text(copy.documentUnavailable(widget.title)));
          }
          return DecoratedBox(
            decoration: BoxDecoration(color: palette.pageBackground),
            child: PdfViewer.file(
              snapshot.data!,
              controller: _pdfController,
              useProgressiveLoading: false,
              params: PdfViewerParams(
                backgroundColor: palette.pageBackground,
                margin: 10,
                minScale: 1.0,
                maxScale: 5.0,
                limitRenderingCache: false,
                maxImageBytesCachedOnMemory: 320 * 1024 * 1024,
                verticalCacheExtent: 3.0,
                horizontalCacheExtent: 1.5,
                scrollPhysics: const _FastPdfScrollPhysics(),
                onViewerReady: (document, controller) {
                  if (!mounted) {
                    return;
                  }
                  setState(() {
                    _totalPages = document.pages.length;
                    _currentPage = controller.pageNumber ?? 1;
                  });
                },
                onPageChanged: (pageNumber) {
                  if (!mounted || pageNumber == null) {
                    return;
                  }
                  setState(() {
                    _currentPage = pageNumber;
                  });
                },
                viewerOverlayBuilder: (context, size, handleLinkTap) {
                  return <Widget>[
                    Positioned(
                      bottom: 14,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: palette.surfaceContainer.withValues(
                                alpha: 0.94,
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              _totalPages > 0
                                  ? '$_currentPage/$_totalPages'
                                  : '$_currentPage',
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ];
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FastPdfScrollPhysics extends FixedOverscrollPhysics {
  const _FastPdfScrollPhysics({
    super.parent,
    super.maxOverscroll = 220,
    this.velocityMultiplier = 1.35,
  });

  final double velocityMultiplier;

  @override
  _FastPdfScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _FastPdfScrollPhysics(
      parent: buildParent(ancestor),
      maxOverscroll: maxOverscroll,
      velocityMultiplier: velocityMultiplier,
    );
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    return super.createBallisticSimulation(
      position,
      velocity * velocityMultiplier,
    );
  }
}
