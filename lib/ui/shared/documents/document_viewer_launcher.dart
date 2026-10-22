import 'package:flutter/material.dart';

import '../../../app/state/app_controller.dart';
import '../../../features/library/models/resolved_document.dart';
import 'library_resource_document_screen.dart';
import 'markdown_document_screen.dart';
import 'pdf_document_screen.dart';

/// Opens a resolved resource with the viewer for its actual format.
abstract final class DocumentViewerLauncher {
  static Future<void> open(
    BuildContext context, {
    required AppController controller,
    required ResolvedDocument document,
    required String title,
  }) {
    final Widget screen = switch (document.renderType) {
      DocumentRenderType.pdf => PdfDocumentScreen(
        controller: controller,
        remotePath: document.remotePath,
        title: title,
      ),
      DocumentRenderType.markdown => MarkdownDocumentScreen(
        controller: controller,
        remotePath: document.remotePath,
        title: title,
      ),
      _ => LibraryResourceDocumentScreen(
        controller: controller,
        document: document,
        title: title,
      ),
    };
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
  }
}
