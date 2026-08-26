import 'dart:convert';

import 'package:app_ai_client/app_ai_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Durable storage for opaque Responses compaction output items.
///
/// Compaction items are provider-owned state. They must not be rendered as
/// chat text, and they should not be put in ordinary preferences because the
/// payload can contain sensitive conversation context. The secure storage
/// implementation delegates encryption and protected-at-rest storage to the
/// current platform plugin.
abstract interface class ResponsesCompactionStore {
  Future<Map<String, List<ResponsesInputItem>>> load();

  Future<void> save(Map<String, List<ResponsesInputItem>> itemsByContext);

  Future<void> clear();
}

/// Platform-backed encrypted storage for Responses compaction state.
class SecureResponsesCompactionStore implements ResponsesCompactionStore {
  SecureResponsesCompactionStore({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const String _storageKey = 'responses_compaction_state.v1';
  static const int _schemaVersion = 1;

  final FlutterSecureStorage _secureStorage;
  Future<void> _writeTail = Future<void>.value();

  @override
  Future<Map<String, List<ResponsesInputItem>>> load() async {
    final String? stored = await _secureStorage.read(key: _storageKey);
    if (stored == null || stored.trim().isEmpty) {
      return const <String, List<ResponsesInputItem>>{};
    }

    try {
      final dynamic decoded = jsonDecode(stored);
      if (decoded is! Map || decoded['version'] != _schemaVersion) {
        return const <String, List<ResponsesInputItem>>{};
      }
      final dynamic contexts = decoded['contexts'];
      if (contexts is! Map) {
        return const <String, List<ResponsesInputItem>>{};
      }

      final Map<String, List<ResponsesInputItem>> result =
          <String, List<ResponsesInputItem>>{};
      for (final MapEntry<dynamic, dynamic> entry in contexts.entries) {
        final String contextKey = '${entry.key}'.trim();
        if (contextKey.isEmpty || entry.value is! List) continue;

        final List<ResponsesInputItem> items = <ResponsesInputItem>[];
        for (final dynamic item in entry.value as List<dynamic>) {
          if (item is! Map) continue;
          final Map<String, dynamic> value = Map<String, dynamic>.from(item);
          if (value['type'] != 'compaction') continue;
          items.add(ResponsesRawInput(value));
        }
        if (items.isNotEmpty) {
          result[contextKey] = List<ResponsesInputItem>.unmodifiable(items);
        }
      }
      return Map<String, List<ResponsesInputItem>>.unmodifiable(result);
    } on Object {
      // An incomplete or incompatible cache must never prevent the app from
      // starting. The next successful response will replace it with v1 data.
      return const <String, List<ResponsesInputItem>>{};
    }
  }

  @override
  Future<void> save(Map<String, List<ResponsesInputItem>> itemsByContext) {
    final Map<String, List<Map<String, dynamic>>> normalized =
        <String, List<Map<String, dynamic>>>{};
    for (final MapEntry<String, List<ResponsesInputItem>> entry
        in itemsByContext.entries) {
      final String contextKey = entry.key.trim();
      if (contextKey.isEmpty) continue;
      final List<Map<String, dynamic>> items = entry.value
          .whereType<ResponsesRawInput>()
          .map((ResponsesRawInput item) => item.value)
          .where((Map<String, dynamic> value) => value['type'] == 'compaction')
          .map(Map<String, dynamic>.from)
          .toList(growable: false);
      if (items.isNotEmpty) normalized[contextKey] = items;
    }

    final Future<void> operation = _writeTail.then<void>((_) async {
      if (normalized.isEmpty) {
        await _secureStorage.delete(key: _storageKey);
        return;
      }
      final String encoded = jsonEncode(<String, dynamic>{
        'version': _schemaVersion,
        'contexts': normalized,
      });
      await _secureStorage.write(key: _storageKey, value: encoded);
    });
    // Keep later writes usable after a failed platform write while still
    // returning the original error to the caller.
    _writeTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  @override
  Future<void> clear() {
    final Future<void> operation = _writeTail.then<void>(
      (_) => _secureStorage.delete(key: _storageKey),
    );
    _writeTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }
}

/// Deterministic in-memory store used by tests and non-Flutter embedders.
class InMemoryResponsesCompactionStore implements ResponsesCompactionStore {
  Map<String, List<ResponsesInputItem>> _state =
      <String, List<ResponsesInputItem>>{};

  @override
  Future<Map<String, List<ResponsesInputItem>>> load() async {
    return _copy(_state);
  }

  @override
  Future<void> save(
    Map<String, List<ResponsesInputItem>> itemsByContext,
  ) async {
    _state = _copy(itemsByContext);
  }

  @override
  Future<void> clear() async {
    _state = <String, List<ResponsesInputItem>>{};
  }

  Map<String, List<ResponsesInputItem>> _copy(
    Map<String, List<ResponsesInputItem>> source,
  ) {
    return <String, List<ResponsesInputItem>>{
      for (final MapEntry<String, List<ResponsesInputItem>> entry
          in source.entries)
        entry.key: List<ResponsesInputItem>.unmodifiable(entry.value),
    };
  }
}
