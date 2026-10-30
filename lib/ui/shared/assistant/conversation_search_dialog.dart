import 'package:flutter/material.dart';

import '../../../core/localization/app_copy.dart';
import '../../../features/assistant/models/chat_message.dart';

/// Searches the current conversation's actual messages and returns a stable ID.
class ConversationSearchDialog extends StatefulWidget {
  const ConversationSearchDialog({
    super.key,
    required this.messages,
    required this.copy,
  });
  final List<ChatMessage> messages;
  final AppCopy copy;

  @override
  State<ConversationSearchDialog> createState() =>
      _ConversationSearchDialogState();
}

class _ConversationSearchDialogState extends State<ConversationSearchDialog> {
  final _query = TextEditingController();
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = widget.copy;
    final media = MediaQuery.of(context);
    final contentHeight =
        (media.size.height -
                media.viewInsets.bottom -
                media.padding.vertical -
                200)
            .clamp(80.0, 460.0);
    final query = _query.text.trim().toLowerCase();
    final matches = query.isEmpty
        ? <ChatMessage>[]
        : widget.messages
              .where((item) => item.text.toLowerCase().contains(query))
              .toList();
    return AlertDialog(
      key: const ValueKey('assistant-search-dialog'),
      title: Text(copy.localized('查找', 'Find')),
      content: SizedBox(
        width: 460,
        height: contentHeight,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('assistant-search-query'),
              controller: _query,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: copy.localized('搜索当前对话', 'Search this conversation'),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: query.isEmpty
                  ? Center(
                      child: Text(
                        copy.localized('输入内容开始查找', 'Enter text to search'),
                      ),
                    )
                  : matches.isEmpty
                  ? Center(
                      child: Text(
                        copy.localized('没有找到相关消息', 'No matching messages'),
                      ),
                    )
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final item = matches[index];
                        final offset = item.text.toLowerCase().indexOf(query);
                        final start = (offset - 45).clamp(0, item.text.length);
                        final end = (offset + query.length + 90).clamp(
                          0,
                          item.text.length,
                        );
                        final excerpt =
                            '${start > 0 ? '…' : ''}${item.text.substring(start, end).replaceAll('\n', ' ')}${end < item.text.length ? '…' : ''}';
                        return ListTile(
                          key: ValueKey('assistant-search-result-${item.id}'),
                          title: Text(
                            item.role == ChatRole.user
                                ? copy.localized('我', 'You')
                                : copy.localized('助手', 'Assistant'),
                          ),
                          subtitle: Text(
                            excerpt,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.of(context).pop(item.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(copy.localized('关闭', 'Close')),
        ),
      ],
    );
  }
}
