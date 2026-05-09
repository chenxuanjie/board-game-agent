import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../state/app_controller.dart';

class MarkdownDocumentScreen extends StatefulWidget {
  const MarkdownDocumentScreen({
    super.key,
    required this.controller,
    required this.assetPath,
    required this.title,
  });

  final AppController controller;
  final String assetPath;
  final String title;

  @override
  State<MarkdownDocumentScreen> createState() => _MarkdownDocumentScreenState();
}

class _MarkdownDocumentScreenState extends State<MarkdownDocumentScreen> {
  late Future<String> _contentFuture;

  @override
  void initState() {
    super.initState();
    _contentFuture = rootBundle.loadString(widget.assetPath);
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.controller.palette;
    final cardTextColor =
        ThemeData.estimateBrightnessForColor(palette.cardSurface) ==
            Brightness.dark
        ? Colors.white
        : const Color(0xFF173B52);
    final secondaryTextColor = cardTextColor.withValues(alpha: 0.82);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      backgroundColor: palette.detailOverlayBottom,
      body: FutureBuilder<String>(
        future: _contentFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                '文档加载失败：${snapshot.error}',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: cardTextColor),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(18),
            children: <Widget>[
              Card(
                color: palette.cardSurface,
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
                            color: palette.accentPrimary,
                            decorationColor: palette.accentPrimary,
                          ),
                          codeblockDecoration: BoxDecoration(
                            color: palette.homeSearchBackground.withValues(
                              alpha: 0.38,
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          blockquoteDecoration: BoxDecoration(
                            color: palette.homeSearchBackground.withValues(
                              alpha: 0.22,
                            ),
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
                            color: palette.homeSearchBackground.withValues(
                              alpha: 0.18,
                            ),
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
