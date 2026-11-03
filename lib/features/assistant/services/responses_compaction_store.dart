import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/responses_context_window.dart';

/// Encrypted storage for versioned compaction windows and their chat boundaries.
///
/// Compaction items are provider-owned state. They must not be rendered as
/// chat text, and they should not be put in ordinary preferences because the
/// payload can contain sensitive conversation context. The secure storage
/// implementation delegates encryption and protected-at-rest storage to the
/// current platform plugin.
abstract interface class ResponsesCompactionStore {
  Future<Map<String, ResponsesContextWindow>> load();

  Future<void> save(Map<String, ResponsesContextWindow> itemsByContext);

  Future<void> clear();
}

/// Platform-backed encrypted storage for Responses compaction state.
class SecureResponsesCompactionStore implements ResponsesCompactionStore {
  SecureResponsesCompactionStore({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  // Keep the physical slot so the first v2 write also replaces old v1 data.
  // The envelope version below decides whether a window can be restored.
  static const String _storageKey = 'responses_compaction_state.v1';
  static const int _schemaVersion = 2;

  final FlutterSecureStorage _secureStorage;
  Future<void> _writeTail = Future<void>.value();

  @override
  Future<Map<String, ResponsesContextWindow>> load() async {
    final String? stored = await _secureStorage.read(key: _storageKey);
    if (stored == null || stored.trim().isEmpty) {
      return const <String, ResponsesContextWindow>{};
    }

    try {
      final dynamic decoded = jsonDecode(stored);
      if (decoded is! Map || decoded['version'] != _schemaVersion) {
        return const <String, ResponsesContextWindow>{};
      }
      final dynamic contexts = decoded['contexts'];
      if (contexts is! Map) {
        return const <String, ResponsesContextWindow>{};
      }

      final Map<String, ResponsesContextWindow> result =
          <String, ResponsesContextWindow>{};
      for (final MapEntry<dynamic, dynamic> entry in contexts.entries) {
        final String contextKey = '${entry.key}'.trim();
        if (contextKey.isEmpty || entry.value is! Map<String, dynamic>) {
          continue;
        }
        try {
          result[contextKey] = ResponsesContextWindow.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
        } on FormatException {
          // Discard only the invalid cache window, never the chat transcript.
        }
      }
      return Map<String, ResponsesContextWindow>.unmodifiable(result);
    } on Object {
      // An incomplete or incompatible cache must never prevent the app from
      // starting. The next successful response replaces it with a v2 window.
      return const <String, ResponsesContextWindow>{};
    }
  }

  @override
  Future<void> save(Map<String, ResponsesContextWindow> itemsByContext) {
    final normalized = <String, Map<String, dynamic>>{
      for (final entry in itemsByContext.entries)
        if (entry.key.trim().isNotEmpty) entry.key: entry.value.toJson(),
    };

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
  Map<String, ResponsesContextWindow> _state =
      <String, ResponsesContextWindow>{};

  @override
  Future<Map<String, ResponsesContextWindow>> load() async {
    return _copy(_state);
  }

  @override
  Future<void> save(Map<String, ResponsesContextWindow> itemsByContext) async {
    _state = _copy(itemsByContext);
  }

  @override
  Future<void> clear() async {
    _state = <String, ResponsesContextWindow>{};
  }

  Map<String, ResponsesContextWindow> _copy(
    Map<String, ResponsesContextWindow> source,
  ) {
    return <String, ResponsesContextWindow>{
      for (final MapEntry<String, ResponsesContextWindow> entry
          in source.entries)
        entry.key: ResponsesContextWindow.fromJson(entry.value.toJson()),
    };
  }
}
