import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_run.dart';

/// Receives normalized run outcomes for diagnostics, metrics, or a future
/// durable observability backend. Implementations must not contain secrets.
abstract interface class AiRunTelemetrySink {
  Future<void> record(AiRunResult result);
}

/// Bounded in-memory telemetry useful for the app and deterministic tests.
class InMemoryAiRunTelemetrySink implements AiRunTelemetrySink {
  InMemoryAiRunTelemetrySink({this.maxEntries = 100}) : assert(maxEntries > 0);

  final int maxEntries;
  final List<AiRunResult> _runs = <AiRunResult>[];

  List<AiRunResult> get recent => List<AiRunResult>.unmodifiable(_runs);

  @override
  Future<void> record(AiRunResult result) async {
    _runs.add(result);
    if (_runs.length > maxEntries) {
      _runs.removeRange(0, _runs.length - maxEntries);
    }
  }
}

class NoopAiRunTelemetrySink implements AiRunTelemetrySink {
  const NoopAiRunTelemetrySink();

  @override
  Future<void> record(AiRunResult result) async {}
}

/// Persists a bounded, secret-free run ledger in local preferences.
///
/// The ledger intentionally stores normalized metadata only (see
/// [AiRunResult.toMap]); prompts, API keys, file contents, and raw provider
/// payloads never enter this store. A write failure is handled by the caller
/// as an observability degradation, not as a chat failure.
class SharedPreferencesAiRunTelemetrySink implements AiRunTelemetrySink {
  SharedPreferencesAiRunTelemetrySink({this.maxEntries = 100})
    : assert(maxEntries > 0);

  static const String storageKey = 'ai_run_telemetry.v1';

  final int maxEntries;
  Future<void> _writeTail = Future<void>.value();

  @override
  Future<void> record(AiRunResult result) {
    final Future<void> operation = _writeTail.then<void>((_) async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> entries = <String>[
        ...(prefs.getStringList(storageKey) ?? const <String>[]),
        jsonEncode(result.toMap()),
      ];
      if (entries.length > maxEntries) {
        entries.removeRange(0, entries.length - maxEntries);
      }
      await prefs.setStringList(storageKey, entries);
    });
    // Keep the queue usable after a storage failure while preserving the
    // original error for the current caller.
    _writeTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<List<Map<String, dynamic>>> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> result = <Map<String, dynamic>>[];
    for (final String entry
        in prefs.getStringList(storageKey) ?? const <String>[]) {
      try {
        final dynamic decoded = jsonDecode(entry);
        if (decoded is Map) {
          result.add(Map<String, dynamic>.from(decoded));
        }
      } on Object {
        // Ignore one corrupt record instead of hiding the remaining ledger.
      }
    }
    return List<Map<String, dynamic>>.unmodifiable(result);
  }

  Future<void> clear() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
  }
}
