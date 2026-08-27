import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../state/app_controller.dart';
import '../../theme/app_palette.dart';
import '../widgets/document_failure_view.dart';

class MarkdownDocumentScreen extends StatefulWidget {
  const MarkdownDocumentScreen({
    super.key,
    required this.controller,
    required this.remotePath,
    required this.title,
  });

  final AppController controller;
  final String remotePath;
  final String title;

  @override
  State<MarkdownDocumentScreen> createState() => _MarkdownDocumentScreenState();
}

class _MarkdownDocumentScreenState extends State<MarkdownDocumentScreen> {
  late Future<String?> _contentFuture;

  @override
  void initState() {
    super.initState();
    _contentFuture = widget.controller.loadMarkdownDocument(widget.remotePath);
  }

  void _retryLoad() {
    if (!mounted) {
      return;
    }
    setState(() {
      _contentFuture = widget.controller.loadMarkdownDocument(
        widget.remotePath,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final copy = widget.controller.copy;
    final Color cardTextColor = palette.textPrimary;
    final secondaryTextColor = cardTextColor.withValues(alpha: 0.82);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      backgroundColor: palette.pageBackground,
      body: FutureBuilder<String?>(
        future: _contentFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError ||
              snapshot.data == null ||
              snapshot.data!.trim().isEmpty) {
            return DocumentFailureView(
              copy: copy,
              title: widget.title,
              kind: DocumentFailureKind.load,
              onRetry: _retryLoad,
              onBack: () => Navigator.of(context).maybePop(),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(18),
            children: <Widget>[
              Card(
                color: palette.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: MarkdownBody(
                    data: snapshot.data ?? '',
                    selectable: true,
                    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                        .copyWith(
                          p: Theme.of(
                            context,
                          ).textTheme.bodyLarge?.copyWith(color: cardTextColor),
                          h1: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: cardTextColor,
                          ),
                          h2: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: cardTextColor,
                          ),
                          h3: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: cardTextColor,
                          ),
                          code: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: secondaryTextColor),
                          blockquote: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(color: secondaryTextColor),
                          strong: TextStyle(
                            color: cardTextColor,
                            fontWeight: FontWeight.w800,
                          ),
                          em: TextStyle(color: secondaryTextColor),
                          listBullet: Theme.of(
                            context,
                          ).textTheme.bodyLarge?.copyWith(color: cardTextColor),
                          a: TextStyle(
                            color: palette.primary,
                            decorationColor: palette.primary,
                          ),
                          codeblockDecoration: BoxDecoration(
                            color: palette.inputSurface.withValues(alpha: 0.38),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          blockquoteDecoration: BoxDecoration(
                            color: palette.inputSurface.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          horizontalRuleDecoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color: cardTextColor.withValues(alpha: 0.12),
                              ),
                            ),
                          ),
                          tableHead: TextStyle(
                            color: cardTextColor,
                            fontWeight: FontWeight.w800,
                          ),
                          tableBody: TextStyle(color: cardTextColor),
                          tableBorder: TableBorder.all(
                            color: cardTextColor.withValues(alpha: 0.14),
                          ),
                          tableCellsDecoration: BoxDecoration(
                            color: palette.inputSurface.withValues(alpha: 0.18),
                          ),
                          tableColumnWidth: const FlexColumnWidth(),
                          checkbox: TextStyle(color: cardTextColor),
                        ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
