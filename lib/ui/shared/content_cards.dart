import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/ui_tokens.dart';
import 'hover_horizontal_scrollbar.dart';

/// Roles shared by compact content cards, rather than page-specific font sizes.
abstract final class ContentCardStyle {
  static const radius = UiTokens.cardRadius;
  static const gap = UiTokens.itemGap;
  static const ratingColor = Color(0xFFFFA126);

  static TextStyle title(BuildContext context) => Theme.of(context)
      .textTheme
      .titleMedium!
      .copyWith(fontSize: 15, fontWeight: FontWeight.w700, height: 1.2);
  static TextStyle body(BuildContext context) => Theme.of(
    context,
  ).textTheme.bodySmall!.copyWith(fontSize: 12, height: 1.3);
  static TextStyle compactBody(BuildContext context) =>
      body(context).copyWith(fontSize: 11);
  static TextStyle score(BuildContext context) =>
      title(context).copyWith(fontSize: 14, height: 1.2);
  static TextStyle section(BuildContext context) => Theme.of(context)
      .textTheme
      .titleMedium!
      .copyWith(fontSize: 19, fontWeight: FontWeight.w700, height: 1.3);

  static String attributes(String categoryLine) => categoryLine
      .split(RegExp(r'\s*[/／·,，]\s*'))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .take(2)
      .join(' / ');

  static String relativeDate(DateTime date, bool chinese) {
    final local = date.toLocal();
    final now = DateTime.now();
    final days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(local.year, local.month, local.day)).inDays;
    if (days <= 0) return chinese ? '今天' : 'Today';
    if (days == 1) return chinese ? '昨天' : 'Yesterday';
    if (days < 7) return chinese ? '$days 天前' : '${days}d ago';
    return chinese
        ? '${local.month}月${local.day}日'
        : '${local.month}/${local.day}';
  }
}

class ContentCardMetrics {
  const ContentCardMetrics({
    required this.width,
    required this.height,
    this.recommendation = false,
  });
  final double width;
  final double height;
  final bool recommendation;
  double get coverWidth =>
      recommendation ? (width * .4).clamp(96.0, 112.0) : width * .38;

  static ContentCardMetrics resolve(
    BuildContext context,
    double availableWidth, {
    Iterable<String> metadata = const [],
    bool recommendation = false,
  }) {
    // Mobile exposes the next card; larger views fit complete equal-width cards.
    final slots = ((availableWidth + 12) / 252).floor().clamp(1, 5);
    final width = availableWidth >= 600
        ? ((availableWidth - 12 * (slots - 1)) / slots).clamp(240.0, 280.0)
        : math.min(
            availableWidth,
            (recommendation ? (availableWidth - 12) / 2 : availableWidth * .8)
                .clamp(240.0, 280.0),
          );
    final scaler = MediaQuery.textScalerOf(context);
    final body = recommendation
        ? ContentCardStyle.compactBody(context)
        : ContentCardStyle.body(context);
    final title = ContentCardStyle.title(context);
    final score = ContentCardStyle.score(context);
    final coverWidth = recommendation
        ? (width * .4).clamp(96.0, 112.0)
        : width * .38;
    final textWidth = width - coverWidth - (recommendation ? 20 : 24);
    double measure(String text, TextStyle style, {int? maxLines}) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: maxLines,
      )..layout(maxWidth: textWidth);
      final height = painter.height;
      painter.dispose();
      return height;
    }

    // Recommendations only reserve the lines their attributes actually need.
    var metadataHeight = measure(recommendation ? '桌游' : '桌游\n桌游', body);
    for (final text in metadata) {
      metadataHeight = math.max(metadataHeight, measure(text, body));
    }
    final height =
        20 +
        measure('桌游', title, maxLines: 1) +
        4 +
        metadataHeight +
        8 +
        math.max(math.max(18, scaler.scale(14) * 1.2), measure('8.0', score)) +
        22 +
        measure('桌游\n桌游\n桌游', body, maxLines: 3);
    return ContentCardMetrics(
      width: width,
      height: math.max(recommendation ? 154 : 168, height.ceilToDouble()),
      recommendation: recommendation,
    );
  }
}

/// Colored category labels; wrapping and measurement use the same constraints.
class ContentAttributeTags extends StatelessWidget {
  const ContentAttributeTags({super.key, required this.tags});
  final List<String> tags;

  static double heightFor(
    BuildContext context,
    List<String> tags,
    double width,
  ) {
    var height = 0.0;
    var rowHeight = 0.0;
    var usedWidth = 0.0;
    for (final tag in tags) {
      final painter = TextPainter(
        text: TextSpan(text: tag, style: ContentCardStyle.body(context)),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: math.max(1, width - 14));
      final tagWidth = math.min(width, painter.width + 14);
      final tagHeight = painter.height + 6;
      painter.dispose();
      if (usedWidth > 0 && usedWidth + 4 + tagWidth > width) {
        height += rowHeight + 4;
        rowHeight = 0;
        usedWidth = 0;
      }
      usedWidth += (usedWidth == 0 ? 0 : 4) + tagWidth;
      rowHeight = math.max(rowHeight, tagHeight);
    }
    return height + rowHeight;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final tag in tags)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: dark
                      ? palette.primaryContainer
                      : const Color(0xFFFFF1E9),
                  borderRadius: BorderRadius.circular(UiTokens.controlRadius),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  child: Text(
                    tag,
                    style: ContentCardStyle.body(context).copyWith(
                      color: dark
                          ? palette.onPrimaryContainer
                          : const Color(0xFFD85E2E),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ContentCardStrip extends StatelessWidget {
  const ContentCardStrip({
    super.key,
    required this.keyPrefix,
    required this.itemCount,
    required this.itemBuilder,
    this.metadata = const [],
    this.recommendation = false,
  });
  final String keyPrefix;
  final int itemCount;
  final Iterable<String> metadata;
  final bool recommendation;
  final Widget Function(BuildContext, int, ContentCardMetrics) itemBuilder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final metrics = ContentCardMetrics.resolve(
        context,
        constraints.maxWidth,
        metadata: metadata,
        recommendation: recommendation,
      );
      return HoverHorizontalScrollbar(
        keyPrefix: keyPrefix,
        builder: (controller) => SizedBox(
          height: metrics.height,
          child: ListView.separated(
            controller: controller,
            scrollDirection: Axis.horizontal,
            itemCount: itemCount,
            separatorBuilder: (_, _) =>
                const SizedBox(width: ContentCardStyle.gap),
            itemBuilder: (context, index) => SizedBox(
              width: metrics.width,
              height: metrics.height,
              child: itemBuilder(context, index, metrics),
            ),
          ),
        ),
      );
    },
  );
}

class ContentCardSurface extends StatelessWidget {
  const ContentCardSurface({
    super.key,
    required this.onTap,
    required this.child,
  });
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final radius = BorderRadius.circular(ContentCardStyle.radius);
    return Material(
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: palette.outline.withValues(alpha: .65)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        hoverColor: palette.primary.withValues(alpha: .05),
        focusColor: palette.primary.withValues(alpha: .12),
        child: child,
      ),
    );
  }
}

class ContentRating extends StatelessWidget {
  const ContentRating({super.key, required this.score});
  final String score;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(
        Icons.star_rounded,
        size: math.max(18, MediaQuery.textScalerOf(context).scale(14) * 1.2),
        color: ContentCardStyle.ratingColor,
      ),
      const SizedBox(width: 4),
      Text(
        score.trim().isEmpty ? '—' : score,
        style: ContentCardStyle.score(context),
      ),
    ],
  );
}
