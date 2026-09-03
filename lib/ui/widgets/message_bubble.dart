import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../models/answer_source.dart';
import '../../models/chat_message.dart';
import '../../models/evidence_chunk.dart';
import '../../models/rule_citation.dart';
import '../../theme/app_palette.dart';
import '../app_copy.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.onSpeak,
    required this.palette,
    this.speakTooltip = 'Speak',
    this.onCopy,
    this.copyTooltip = 'Copy',
    this.onRetry,
    this.retryTooltip = 'Retry',
    required this.copy,
    this.showTimestamp = false,
    this.onTap,
  });

  final ChatMessage message;
  final VoidCallback onSpeak;
  final AppPalette palette;
  final String speakTooltip;
  final VoidCallback? onCopy;
  final String copyTooltip;
  final VoidCallback? onRetry;
  final String retryTooltip;
  final AppCopy copy;
  final bool showTimestamp;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool isUser = message.role == ChatRole.user;
    final Color userForeground = palette.onPrimaryContainer;
    final ThemeData theme = Theme.of(context);
    final TextStyle bodyStyle = theme.textTheme.bodyLarge!.copyWith(
      color: isUser ? userForeground : palette.textPrimary,
      height: 1.5,
    );
    final BorderRadius borderRadius = BorderRadius.circular(24).copyWith(
      bottomLeft: Radius.circular(isUser ? 24 : 8),
      bottomRight: Radius.circular(isUser ? 8 : 24),
    );
    final bool hasAssistantAction = _hasAssistantAction;
    final bool hasAssistantReferences = _hasAssistantReferences;
    // User messages keep the existing compact bubble. Assistant output is a
    // document-like response area; the activity component beside it carries
    // the dynamic run presentation, so a second assistant bubble would be
    // redundant and visually misleading.
    final EdgeInsets messagePadding = isUser
        ? const EdgeInsets.fromLTRB(16, 13, 12, 11)
        : EdgeInsets.zero;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (!isUser) ...<Widget>[
                const Padding(
                  padding: EdgeInsets.only(top: 6, right: 8),
                  child: _MessageAssistantAvatar(),
                ),
              ],
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: isUser
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: <Widget>[
                    _TapToShowTimes(
                      onTap: onTap,
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: borderRadius,
                        child: Ink(
                          decoration: isUser
                              ? BoxDecoration(
                                  color: palette.primaryContainer,
                                  borderRadius: borderRadius,
                                  boxShadow: <BoxShadow>[
                                    BoxShadow(
                                      color: palette.shadow.withValues(
                                        alpha: 0.28,
                                      ),
                                      blurRadius: 16,
                                      offset: const Offset(0, 7),
                                    ),
                                  ],
                                )
                              : null,
                          child: InkWell(
                            // _TapToShowTimes handles pointer taps so that
                            // selectable message text also toggles the time
                            // without firing the callback twice.
                            onTap: null,
                            borderRadius: borderRadius,
                            child: Padding(
                              padding: messagePadding,
                              child: Column(
                                crossAxisAlignment: isUser
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: <Widget>[
                                  if (isUser)
                                    SelectableText(
                                      message.text,
                                      style: bodyStyle,
                                    )
                                  else if (message.text.trim().isEmpty &&
                                      message.isStreaming)
                                    _StreamingPlaceholder(
                                      palette: palette,
                                      label: copy.streaming,
                                    )
                                  else
                                    MarkdownBody(
                                      data: message.text,
                                      selectable: true,
                                      styleSheet:
                                          MarkdownStyleSheet.fromTheme(
                                            theme,
                                          ).copyWith(
                                            p: bodyStyle,
                                            h1: theme.textTheme.titleLarge
                                                ?.copyWith(
                                                  color: palette.textPrimary,
                                                ),
                                            h2: theme.textTheme.titleMedium
                                                ?.copyWith(
                                                  color: palette.textPrimary,
                                                ),
                                            h3: theme.textTheme.titleMedium
                                                ?.copyWith(
                                                  color: palette.textPrimary,
                                                ),
                                            code: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  color: palette.textPrimary,
                                                ),
                                            strong: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: palette.textPrimary,
                                            ),
                                            blockquote: theme
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  color: palette.textPrimary
                                                      .withValues(alpha: 0.8),
                                                ),
                                            listBullet: bodyStyle,
                                          ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (hasAssistantAction)
                      _AssistantActions(
                        palette: palette,
                        onCopy: _canCopy ? onCopy : null,
                        copyTooltip: copyTooltip,
                        onSpeak: _canSpeak ? onSpeak : null,
                        speakTooltip: speakTooltip,
                        onRetry: _canRetry ? onRetry : null,
                        retryTooltip: retryTooltip,
                      ),
                    if (hasAssistantReferences)
                      _AssistantReferenceSection(
                        source: message.source,
                        evidence: message.evidence,
                        citations: message.citations,
                        palette: palette,
                        copy: copy,
                      ),
                    if (showTimestamp)
                      Padding(
                        padding: const EdgeInsets.only(
                          top: 4,
                          left: 4,
                          right: 4,
                        ),
                        child: Text(
                          _formatTime(message.timestamp),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: isUser
                                ? userForeground.withValues(alpha: 0.68)
                                : palette.textPrimary.withValues(alpha: 0.56),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _hasAssistantAction => _canCopy || _canSpeak || _canRetry;

  bool get _canCopy =>
      message.role == ChatRole.assistant &&
      !message.isStreaming &&
      !message.isFailed &&
      message.text.trim().isNotEmpty &&
      onCopy != null;

  bool get _canSpeak =>
      message.role == ChatRole.assistant &&
      !message.isStreaming &&
      !message.isFailed &&
      message.text.trim().isNotEmpty;

  bool get _canRetry =>
      message.role == ChatRole.assistant && message.isFailed && onRetry != null;

  bool get _hasAssistantReferences =>
      message.role == ChatRole.assistant &&
      (message.source != null ||
          message.evidence.isNotEmpty ||
          message.citations.isNotEmpty);

  String _formatTime(DateTime value) {
    final String hour = value.hour.toString().padLeft(2, '0');
    final String minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _AssistantActions extends StatelessWidget {
  const _AssistantActions({
    required this.palette,
    required this.onCopy,
    required this.copyTooltip,
    required this.onSpeak,
    required this.speakTooltip,
    required this.onRetry,
    required this.retryTooltip,
  });

  final AppPalette palette;
  final VoidCallback? onCopy;
  final String copyTooltip;
  final VoidCallback? onSpeak;
  final String speakTooltip;
  final VoidCallback? onRetry;
  final String retryTooltip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, left: 2, right: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (onCopy != null)
            IconButton(
              tooltip: copyTooltip,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: onCopy,
              icon: Icon(
                Icons.copy_all_rounded,
                size: 18,
                color: palette.textSecondary,
              ),
            ),
          if (onSpeak != null)
            IconButton(
              tooltip: speakTooltip,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: onSpeak,
              icon: Icon(
                Icons.volume_up_rounded,
                size: 18,
                color: palette.textSecondary,
              ),
            ),
          if (onRetry != null)
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text(retryTooltip),
              style: TextButton.styleFrom(
                foregroundColor: palette.primary,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
            ),
        ],
      ),
    );
  }
}

class _AssistantReferenceSection extends StatelessWidget {
  const _AssistantReferenceSection({
    required this.source,
    required this.evidence,
    required this.citations,
    required this.palette,
    required this.copy,
  });

  final AnswerSource? source;
  final List<EvidenceChunk> evidence;
  final List<RuleCitation> citations;
  final AppPalette palette;
  final AppCopy copy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (source != null)
            _SourceLabel(source: source!, palette: palette, copy: copy),
          if (evidence.isNotEmpty) ...<Widget>[
            if (source != null) const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: evidence
                  .map(
                    (evidence) => Chip(
                      avatar: Icon(
                        Icons.menu_book_rounded,
                        size: 15,
                        color: palette.primary,
                      ),
                      label: Text(evidence.sourceName),
                      visualDensity: VisualDensity.compact,
                      side: BorderSide.none,
                      backgroundColor: palette.primaryContainer.withValues(
                        alpha: 0.18,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (citations.isNotEmpty) ...<Widget>[
            if (source != null || evidence.isNotEmpty)
              const SizedBox(height: 6),
            _CitationList(
              citations: citations,
              palette: palette,
              title: copy.evidenceTitle,
            ),
          ],
        ],
      ),
    );
  }
}

class _CitationList extends StatelessWidget {
  const _CitationList({
    required this.citations,
    required this.palette,
    required this.title,
  });

  final List<RuleCitation> citations;
  final AppPalette palette;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: palette.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        for (final RuleCitation citation in citations)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _CitationItem(citation: citation, palette: palette),
          ),
      ],
    );
  }
}

class _CitationItem extends StatelessWidget {
  const _CitationItem({required this.citation, required this.palette});

  final RuleCitation citation;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final bool isWeb = citation.sourceType == 'web';
    final String title = citation.title?.trim().isNotEmpty == true
        ? citation.title!.trim()
        : isWeb
        ? '联网网页'
        : _fileName(citation.path) ?? '规则资料';
    final String? detail = isWeb ? citation.url : _documentLocation(citation);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: palette.primaryContainer.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            isWeb ? Icons.language_rounded : Icons.menu_book_rounded,
            size: 15,
            color: palette.primary,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (detail != null && detail.trim().isNotEmpty)
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _documentLocation(RuleCitation citation) {
    final List<String> parts = <String>[];
    if (citation.page != null) parts.add('第 ${citation.page} 页');
    if (citation.lineStart != null) {
      parts.add(
        citation.lineEnd == null
            ? '第 ${citation.lineStart} 行'
            : '第 ${citation.lineStart}-${citation.lineEnd} 行',
      );
    }
    if (citation.section?.trim().isNotEmpty == true) {
      parts.add(citation.section!.trim());
    }
    if (parts.isNotEmpty) return parts.join(' · ');
    return _fileName(citation.path);
  }

  String? _fileName(String? path) {
    final String value = path?.trim() ?? '';
    if (value.isEmpty) return null;
    return value.split(RegExp(r'[\\/]')).last;
  }
}

class _StreamingPlaceholder extends StatelessWidget {
  const _StreamingPlaceholder({required this.palette, required this.label});

  final AppPalette palette;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: palette.primary,
          ),
        ),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}

class _TapToShowTimes extends StatefulWidget {
  const _TapToShowTimes({required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  State<_TapToShowTimes> createState() => _TapToShowTimesState();
}

class _TapToShowTimesState extends State<_TapToShowTimes> {
  Offset? _pointerDownPosition;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _pointerDownPosition = event.position;
      },
      onPointerUp: (event) {
        final Offset? downPosition = _pointerDownPosition;
        _pointerDownPosition = null;
        if (downPosition == null || widget.onTap == null) {
          return;
        }
        if ((event.position - downPosition).distance <= kTouchSlop) {
          widget.onTap!();
        }
      },
      onPointerCancel: (_) {
        _pointerDownPosition = null;
      },
      child: widget.child,
    );
  }
}

class _SourceLabel extends StatelessWidget {
  const _SourceLabel({
    required this.source,
    required this.palette,
    required this.copy,
  });

  final AnswerSource source;
  final AppPalette palette;
  final AppCopy copy;

  @override
  Widget build(BuildContext context) {
    final String label = switch (source) {
      AnswerSource.rulebook => copy.answerSourceRulebook,
      AnswerSource.official => copy.answerSourceOfficial,
      AnswerSource.community => copy.answerSourceCommunity,
      AnswerSource.web => copy.answerSourceWeb,
      AnswerSource.modelKnowledge => copy.answerSourceModelKnowledge,
      AnswerSource.generalAdvice => copy.answerSourceGeneral,
      AnswerSource.insufficient => copy.answerSourceInsufficient,
    };
    final IconData icon = switch (source) {
      AnswerSource.rulebook => Icons.menu_book_rounded,
      AnswerSource.official => Icons.verified_rounded,
      AnswerSource.community => Icons.groups_rounded,
      AnswerSource.web => Icons.language_rounded,
      AnswerSource.modelKnowledge => Icons.auto_awesome_rounded,
      AnswerSource.generalAdvice => Icons.auto_awesome_rounded,
      AnswerSource.insufficient => Icons.info_outline_rounded,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 15, color: palette.primary),
        const SizedBox(width: 5),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: palette.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _MessageAssistantAvatar extends StatelessWidget {
  const _MessageAssistantAvatar();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.asset(
        'branding/app_icon.png',
        width: 30,
        height: 30,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stackTrace) => Container(
          width: 30,
          height: 30,
          color: Theme.of(context).colorScheme.primary,
          alignment: Alignment.center,
          child: const Icon(Icons.casino_rounded, size: 18),
        ),
      ),
    );
  }
}
