import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/localization/app_copy.dart';
import '../../../features/assistant/models/chat_message.dart';

Future<void> shareAssistantConversation({
  required BuildContext context,
  required String title,
  required AppCopy copy,
  required List<ChatMessage> messages,
}) async {
  final List<String> transcriptLines = <String>[
    title,
    ...messages
        .where((ChatMessage message) => message.text.trim().isNotEmpty)
        .map((ChatMessage message) {
          final String speaker = message.role == ChatRole.user
              ? copy.localized('我', 'You')
              : copy.localized('AI 助手', 'AI assistant');
          return '$speaker:\n${message.text.trim()}';
        }),
  ];
  final String transcript = transcriptLines.join('\n\n');

  try {
    await SharePlus.instance.share(
      ShareParams(
        text: transcript,
        title: title,
        subject: title,
        mailToFallbackEnabled: !kIsWeb,
      ),
    );
  } catch (_) {
    if (!context.mounted) return;
    if (!kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            copy.localized('分享失败，请重试', 'Could not share. Try again.'),
          ),
        ),
      );
      return;
    }

    try {
      await Clipboard.setData(ClipboardData(text: transcript));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            copy.localized(
              '系统分享不可用，复制对话也失败了',
              'Sharing is unavailable and copying the conversation failed.',
            ),
          ),
        ),
      );
      return;
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          copy.localized(
            '系统分享不可用，对话内容已复制',
            'System sharing is unavailable; conversation copied.',
          ),
        ),
      ),
    );
  }
}
