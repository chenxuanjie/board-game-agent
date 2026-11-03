import 'package:flutter/material.dart';

import '../../../app/state/app_controller.dart';

/// A live durability status, kept visible until the local write succeeds.
class ConversationSaveNotice extends StatefulWidget {
  const ConversationSaveNotice({super.key, required this.controller});
  final AppController controller;

  @override
  State<ConversationSaveNotice> createState() => _ConversationSaveNoticeState();
}

class _ConversationSaveNoticeState extends State<ConversationSaveNotice> {
  bool _retrying = false;

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await widget.controller.retryConversationSave();
    } catch (_) {
      // The controller retains the warning and unsaved messages for retry.
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final error = widget.controller.conversationSaveError;
      final colors = Theme.of(context).colorScheme;
      return AnimatedSize(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        alignment: Alignment.bottomCenter,
        child: error == null
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Semantics(
                  liveRegion: true,
                  child: Material(
                    color: colors.errorContainer,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            error,
                            style: TextStyle(color: colors.onErrorContainer),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: _retrying ? null : _retry,
                              icon: const Icon(Icons.save_outlined),
                              label: Text(
                                widget.controller.copy.retryConversationSave,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      );
    },
  );
}
