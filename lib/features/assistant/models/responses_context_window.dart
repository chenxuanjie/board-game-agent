import 'dart:convert';

import 'package:app_ai_client/app_ai_client.dart';
import 'package:crypto/crypto.dart';

import 'chat_message.dart';

/// A stateless Responses window, anchored to the accepted visible chat turn.
/// Only items BEFORE the newest compaction are disposable. Items after it
/// retain their provider order, including reasoning, tool results and messages.
class ResponsesContextWindow {
  ResponsesContextWindow._({
    required this.items,
    required this.promptDigest,
    required this.answerDigest,
    required this.messageId,
  });

  static const maxBytes = 256 * 1024;
  static const maxItems = 512;
  final List<ResponsesInputItem> items;
  final String promptDigest, answerDigest;
  final String? messageId;

  static bool isCompaction(ResponsesInputItem item) =>
      item is ResponsesRawInput && item.value['type'] == 'compaction';
  static String _digest(String text) =>
      sha256.convert(utf8.encode(text.trim())).toString();

  static ResponsesContextWindow? capture({
    required ResponsesRequest request,
    required ResponsesResponse response,
    required List<ChatMessage> history,
    required String prompt,
    required String answer,
  }) {
    final output = List<ResponsesInputItem>.of(response.outputItems);
    // Real Responses output already contains message items. Some compatible
    // providers return text without a message item; preserve that text too.
    if (response.text.trim().isNotEmpty &&
        !output.any((item) => item.toJson()['type'] == 'message')) {
      output.add(
        ResponsesTextInput(response.text, role: ResponsesInputRole.assistant),
      );
    }
    final all = [...request.input, ...output];
    final boundary = all.lastIndexWhere(isCompaction);
    if (boundary < 0) return null;
    final retained = all.sublist(boundary);
    // Reject large file/history windows before duplicating their JSON payload.
    if (!_itemsWithinBudget(retained)) return null;
    final last = history
        .where((message) => message.text.trim().isNotEmpty)
        .lastOrNull;
    final window = ResponsesContextWindow._(
      items: _freeze(retained),
      promptDigest: _digest(prompt),
      answerDigest: _digest(answer),
      messageId:
          last?.role == ChatRole.user && last!.text.trim() == prompt.trim()
          ? last.id
          : null,
    );
    return window._withinBudget ? window : null;
  }

  /// Null means the transcript no longer proves continuity (edited/truncated
  /// anchor, missing answer, another device's replacement). Rebuild from chat.
  List<ResponsesInputItem>? continueWith(
    List<ChatMessage> history,
    String prompt,
  ) {
    final messages = history
        .where((message) => message.text.trim().isNotEmpty)
        .toList();
    if (messages.isEmpty) {
      // Embedders may intentionally keep history solely in this window. The
      // application supplies IDs; an empty authoritative history invalidates it.
      return messageId == null ? [...items, ResponsesTextInput(prompt)] : null;
    }
    final matches = <int>[];
    for (var i = 0; i + 1 < messages.length; i++) {
      final user = messages[i], assistant = messages[i + 1];
      if (user.role == ChatRole.user &&
          (messageId == null || user.id == messageId) &&
          _digest(user.text) == promptDigest &&
          assistant.role == ChatRole.assistant &&
          _digest(assistant.text) == answerDigest) {
        matches.add(i);
      }
    }
    if (matches.length != 1) return null;
    final tail = messages
        .skip(matches.single + 2)
        .map(
          (message) => ResponsesTextInput(
            message.text.trim(),
            role: message.role == ChatRole.user
                ? ResponsesInputRole.user
                : ResponsesInputRole.assistant,
          ),
        )
        .toList();
    if (tail.isEmpty ||
        tail.last.role != ResponsesInputRole.user ||
        tail.last.text != prompt.trim()) {
      tail.add(ResponsesTextInput(prompt));
    }
    return [...items, ...tail];
  }

  bool get _withinBudget =>
      items.length <= maxItems &&
      utf8.encode(jsonEncode(toJson())).length <= maxBytes;

  static bool _itemsWithinBudget(List<ResponsesInputItem> items) {
    if (items.length > maxItems) return false;
    var bytes = 0;
    for (final item in items) {
      bytes += utf8.encode(jsonEncode(item.toJson())).length;
      if (bytes > maxBytes) return false;
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
    'prompt_digest': promptDigest,
    'answer_digest': answerDigest,
    'message_id': messageId,
    'items': items.map((item) => item.toJson()).toList(),
  };

  static ResponsesContextWindow fromJson(Map<String, dynamic> json) {
    final prompt = json['prompt_digest'], answer = json['answer_digest'];
    final id = json['message_id'], raw = json['items'];
    final digest = RegExp(r'^[a-f0-9]{64}$');
    if (prompt is! String ||
        !digest.hasMatch(prompt) ||
        answer is! String ||
        !digest.hasMatch(answer) ||
        id != null && (id is! String || id.isEmpty) ||
        raw is! List ||
        raw.isEmpty ||
        raw.length > maxItems ||
        raw.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('Invalid Responses context window');
    }
    final items = _freeze(
      raw
          .map((item) => ResponsesRawInput(item as Map<String, dynamic>))
          .toList(),
    );
    if (!isCompaction(items.first) || items.skip(1).any(isCompaction)) {
      throw const FormatException('Invalid Responses compaction boundary');
    }
    final window = ResponsesContextWindow._(
      items: items,
      promptDigest: prompt,
      answerDigest: answer,
      messageId: id as String?,
    );
    if (!window._withinBudget) {
      throw const FormatException('Responses context budget exceeded');
    }
    return window;
  }

  static List<ResponsesInputItem> _freeze(List<ResponsesInputItem> items) =>
      List.unmodifiable(
        items.map(
          (item) => ResponsesRawInput(
            jsonDecode(jsonEncode(item.toJson())) as Map<String, dynamic>,
          ),
        ),
      );
}
