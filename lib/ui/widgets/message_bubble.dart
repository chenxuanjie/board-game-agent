import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../models/chat_message.dart';
import '../../theme/app_palette.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.onSpeak,
    required this.palette,
    this.speakTooltip = 'Speak',
  });

  final ChatMessage message;
  final VoidCallback onSpeak;
  final AppPalette palette;
  final String speakTooltip;

  @override
  Widget build(BuildContext context) {
    final bool isUser = message.role == ChatRole.user;
    final Color userForeground =
        ThemeData.estimateBrightnessForColor(palette.messageUserBubble) ==
            Brightness.dark
        ? Colors.white
        : palette.messageAssistantText;
    final ThemeData theme = Theme.of(context);
    final TextStyle bodyStyle = theme.textTheme.bodyLarge!.copyWith(
      color: isUser ? userForeground : palette.messageAssistantText,
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
                        ? palette.messageUserBubble
                        : palette.messageAssistantBubble,
                    borderRadius: borderRadius,
                    border: isUser
                        ? null
                        : Border.all(color: palette.cardBorder),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: palette.cardShadow.withValues(alpha: 0.28),
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
                        else
                          MarkdownBody(
                            data: message.text,
                            selectable: true,
                            styleSheet: MarkdownStyleSheet.fromTheme(theme)
                                .copyWith(
                                  p: bodyStyle,
                                  h1: theme.textTheme.titleLarge?.copyWith(
                                    color: palette.messageAssistantText,
                                  ),
                                  h2: theme.textTheme.titleMedium?.copyWith(
                                    color: palette.messageAssistantText,
                                  ),
                                  h3: theme.textTheme.titleMedium?.copyWith(
                                    color: palette.messageAssistantText,
                                  ),
                                  code: theme.textTheme.bodyMedium?.copyWith(
                                    color: palette.messageAssistantText,
                                  ),
                                  strong: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: palette.messageAssistantText,
                                  ),
                                  blockquote: theme.textTheme.bodyMedium
                                      ?.copyWith(
                                        color: palette.messageAssistantText
                                            .withValues(alpha: 0.8),
                                      ),
                                  listBullet: bodyStyle,
                                ),
                          ),
                        if (!isUser) ...<Widget>[
                          const SizedBox(height: 6),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                _formatTime(message.timestamp),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: palette.messageAssistantText
                                      .withValues(alpha: 0.56),
                                ),
                              ),
                              const SizedBox(width: 8),
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
                                  color: palette.buttonOutline,
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
