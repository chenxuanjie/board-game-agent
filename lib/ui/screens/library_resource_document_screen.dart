import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/resolved_document.dart';
import '../../state/app_controller.dart';
import '../../theme/app_palette.dart';

/// Lightweight viewer for library resources that are not Markdown or PDF.
/// HTML is intentionally rendered as readable text for now; this avoids a
/// heavyweight WebView dependency while still making the indexed content
/// available offline after it has been cached.
class LibraryResourceDocumentScreen extends StatefulWidget {
  const LibraryResourceDocumentScreen({
    super.key,
    required this.controller,
    required this.document,
    required this.title,
  });

  final AppController controller;
  final ResolvedDocument document;
  final String title;

  @override
  State<LibraryResourceDocumentScreen> createState() =>
      _LibraryResourceDocumentScreenState();
}

class _LibraryResourceDocumentScreenState
    extends State<LibraryResourceDocumentScreen> {
  late final Future<Object?> _contentFuture;

  @override
  void initState() {
    super.initState();
    _contentFuture = _loadContent();
  }

  Future<Object?> _loadContent() async {
    if (widget.document.renderType == DocumentRenderType.image) {
      // Desktop caches remote images, while bundled fallback images can be
      // rendered directly from Flutter's asset bundle when no remote copy is
      // available.
      return await widget.controller.resolveImagePath(
            widget.document.remotePath,
          ) ??
          (widget.document.remotePath.startsWith('assets/')
              ? widget.document.remotePath
              : null);
    }
    final String? content = await widget.controller.loadLibraryResourceText(
      widget.document.remotePath,
    );
    if (content == null) return null;
    if (widget.document.renderType == DocumentRenderType.html) {
      return _htmlToText(content);
    }
    return content;
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      backgroundColor: palette.pageBackground,
      body: FutureBuilder<Object?>(
        future: _contentFuture,
        builder: (BuildContext context, AsyncSnapshot<Object?> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Center(
              child: Text(
                '资源加载失败：${snapshot.error ?? '未找到缓存或远端资源'}',
                style: TextStyle(color: palette.textPrimary),
              ),
            );
          }
          if (widget.document.renderType == DocumentRenderType.image) {
            final String path = snapshot.data! as String;
            return InteractiveViewer(
              minScale: 0.5,
              maxScale: 5,
              child: Center(
                child: path.startsWith('assets/')
                    ? Image.asset(
                        path,
                        fit: BoxFit.contain,
                        errorBuilder:
                            (
                              BuildContext context,
                              Object error,
                              StackTrace? stack,
                            ) => Text('图片加载失败：$error'),
                      )
                    : Image.file(
                        File(path),
                        fit: BoxFit.contain,
                        errorBuilder:
                            (
                              BuildContext context,
                              Object error,
                              StackTrace? stack,
                            ) => Text('图片加载失败：$error'),
                      ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              if (widget.document.renderType == DocumentRenderType.html)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'HTML 预览',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ),
              SelectableText(
                snapshot.data! as String,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: palette.textPrimary,
                  height: 1.55,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _htmlToText(String source) {
    String text = source
        .replaceAll(
          RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(
          RegExp(r'</(p|div|li|h[1-6]|tr)>', caseSensitive: false),
          '\n',
        )
        .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '• ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n\s+'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }
}
