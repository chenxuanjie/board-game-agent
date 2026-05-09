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
  });

  final ChatMessage message;
  final VoidCallback onSpeak;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: isUser ? palette.messageUserBubble : palette.messageAssistantBubble,
            borderRadius: BorderRadius.circular(24).copyWith(
              bottomLeft: Radius.circular(isUser ? 24 : 8),
              bottomRight: Radius.circular(isUser ? 8 : 24),
            ),
            border: isUser
                ? null
                : Border.all(
                    color: palette.cardBorder,
                  ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: palette.cardShadow.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment:
                isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Flexible(
                    child: isUser
                        ? Text(
                            message.text,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: Colors.white,
                                ),
                          )
                        : MarkdownBody(
                            data: message.text,
                            selectable: true,
                            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                              p: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: palette.messageAssistantText,
                                  ),
                              h1: Theme.of(context).textTheme.titleLarge?.copyWith(color: palette.messageAssistantText),
                              h2: Theme.of(context).textTheme.titleMedium?.copyWith(color: palette.messageAssistantText),
                              h3: Theme.of(context).textTheme.titleMedium?.copyWith(color: palette.messageAssistantText),
                              code: Theme.of(context).textTheme.bodyMedium?.copyWith(color: palette.messageAssistantText),
                              strong: TextStyle(fontWeight: FontWeight.w800, color: palette.messageAssistantText),
                              blockquote: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: palette.messageAssistantText.withValues(alpha: 0.8),
                                  ),
                              listBullet: Theme.of(context).textTheme.bodyLarge?.copyWith(color: palette.messageAssistantText),
                            ),
                          ),
                  ),
                  if (!isUser) ...<Widget>[
                    const SizedBox(width: 10),
                    InkWell(
                      onTap: onSpeak,
                      borderRadius: BorderRadius.circular(18),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Icon(
                          Icons.volume_up_rounded,
                          size: 18,
                          color: palette.buttonOutline,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
