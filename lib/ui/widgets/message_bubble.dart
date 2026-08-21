import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../models/answer_source.dart';
import '../../models/chat_message.dart';
import '../../theme/app_palette.dart';
import '../app_copy.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.onSpeak,
    required this.palette,
    this.speakTooltip = 'Speak',
    this.onRetry,
    this.retryTooltip = 'Retry',
    required this.copy,
  });

  final ChatMessage message;
  final VoidCallback onSpeak;
  final AppPalette palette;
  final String speakTooltip;
  final VoidCallback? onRetry;
  final String retryTooltip;
  final AppCopy copy;

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
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: isUser
                        ? palette.primaryContainer
                        : palette.surfaceContainer,
                    borderRadius: borderRadius,
                    border: isUser ? null : Border.all(color: palette.outline),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: palette.shadow.withValues(alpha: 0.28),
                        blurRadius: 16,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 13, 12, 11),
                    child: Column(
                      crossAxisAlignment: isUser
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: <Widget>[
                        if (isUser)
                          SelectableText(message.text, style: bodyStyle)
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
                            styleSheet: MarkdownStyleSheet.fromTheme(theme)
                                .copyWith(
                                  p: bodyStyle,
                                  h1: theme.textTheme.titleLarge?.copyWith(
                                    color: palette.textPrimary,
                                  ),
                                  h2: theme.textTheme.titleMedium?.copyWith(
                                    color: palette.textPrimary,
                                  ),
                                  h3: theme.textTheme.titleMedium?.copyWith(
                                    color: palette.textPrimary,
                                  ),
                                  code: theme.textTheme.bodyMedium?.copyWith(
                                    color: palette.textPrimary,
                                  ),
                                  strong: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: palette.textPrimary,
                                  ),
                                  blockquote: theme.textTheme.bodyMedium
                                      ?.copyWith(
                                        color: palette.textPrimary.withValues(
                                          alpha: 0.8,
                                        ),
                                      ),
                                  listBullet: bodyStyle,
                                ),
                          ),
                        if (!isUser && message.source != null) ...<Widget>[
                          const SizedBox(height: 10),
                          _SourceLabel(
                            source: message.source!,
                            palette: palette,
                            copy: copy,
                          ),
                        ],
                        if (!isUser && message.evidence.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: message.evidence
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
                                    backgroundColor: palette.primaryContainer
                                        .withValues(alpha: 0.18),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                        if (!isUser && message.isFailed) ...<Widget>[
                          const SizedBox(height: 8),
                          Text(
                            'AI',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: palette.textPrimary.withValues(
                                alpha: 0.58,
                              ),
                            ),
                          ),
                        ],
                        if (!isUser) ...<Widget>[
                          const SizedBox(height: 6),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                _formatTime(message.timestamp),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: palette.textPrimary.withValues(
                                    alpha: 0.56,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (!message.isStreaming && !message.isFailed)
                                IconButton(
                                  tooltip: speakTooltip,
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 28,
                                    minHeight: 28,
                                  ),
                                  onPressed: onSpeak,
                                  icon: Icon(
                                    Icons.volume_up_rounded,
                                    size: 17,
                                    color: palette.primary,
                                  ),
                                ),
                              if (message.isFailed && onRetry != null)
                                TextButton.icon(
                                  onPressed: onRetry,
                                  icon: const Icon(
                                    Icons.refresh_rounded,
                                    size: 16,
                                  ),
                                  label: Text(retryTooltip),
                                  style: TextButton.styleFrom(
                                    foregroundColor: palette.primary,
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ] else
                          Text(
                            _formatTime(message.timestamp),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: userForeground.withValues(alpha: 0.68),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime value) {
    final String hour = value.hour.toString().padLeft(2, '0');
    final String minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
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
      AnswerSource.generalAdvice => copy.answerSourceGeneral,
      AnswerSource.insufficient => copy.answerSourceInsufficient,
    };
    final IconData icon = switch (source) {
      AnswerSource.rulebook => Icons.menu_book_rounded,
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
