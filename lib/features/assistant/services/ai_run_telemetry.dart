import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_run.dart';
import '../../settings/services/preferences_service.dart';

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
/// Account records are routed from the immutable run context, never from the
/// currently signed-in account. Existing unscoped records remain guest-owned.
class SharedPreferencesAiRunTelemetrySink implements AiRunTelemetrySink {
  SharedPreferencesAiRunTelemetrySink({this.maxEntries = 100})
    : assert(maxEntries > 0);

  static const String storageKey = 'ai_run_telemetry.v1';
  static const String _accountContextPrefix = 'conversation:personal_v1:';
  // ResponsesRulesWorkflow uses <provider conversation ID>|<endpoint hash>
  // for both contextKey and sessionId. The provider ID may also be used alone.
  static final RegExp _accountContextPattern = RegExp(
    r'^conversation:personal_v1:([a-f0-9]{64}):([^|\s]+)(?:\|[a-f0-9]{64})?$',
  );

  final int maxEntries;
  Future<void> _writeTail = Future<void>.value();

  static String _keyForHash(String? hash) =>
      hash == null ? storageKey : 'personal_v1.$hash.$storageKey';

  static String? _hashFromContext(String? context) {
    if (context == null || !context.startsWith(_accountContextPrefix)) {
      return null;
    }
    final match = _accountContextPattern.firstMatch(context);
    if (match == null || match.end != context.length) {
      // A malformed account marker must never send account data to guest.
      throw const FormatException('Invalid account-scoped telemetry context');
    }
    return match.group(1)!;
  }

  static String _keyForRun(AiRunResult result) {
    final contextHash = _hashFromContext(result.contextKey);
    final sessionHash = _hashFromContext(result.sessionId);
    if (result.contextKey != null &&
        result.sessionId != null &&
        contextHash != sessionHash) {
      throw const FormatException('Conflicting telemetry account scopes');
    }
    return _keyForHash(contextHash ?? sessionHash);
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final operation = _writeTail.then<T>((_) => action());
    // Keep later reads/writes usable while returning this operation's error.
    _writeTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  @override
  Future<void> record(AiRunResult result) async {
    // Pin the namespace and metadata before waiting for any earlier operation.
    final key = _keyForRun(result);
    final encoded = jsonEncode(result.toMap());
    await _serialize<void>(() async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> entries = <String>[
        ...(prefs.getStringList(key) ?? const <String>[]),
        encoded,
      ];
      if (entries.length > maxEntries) {
        entries.removeRange(0, entries.length - maxEntries);
      }
      if (!await prefs.setStringList(key, entries)) {
        throw StateError('Telemetry ledger write failed');
      }
    });
  }

  /// Null reads only the legacy guest ledger, never every account's records.
  Future<List<Map<String, dynamic>>> load({String? identityUserId}) async {
    final key = _keyForHash(
      PreferencesService.identityStorageId(identityUserId),
    );
    return _serialize(() => _load(key));
  }

  Future<List<Map<String, dynamic>>> _load(String key) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> result = <Map<String, dynamic>>[];
    for (final String entry in prefs.getStringList(key) ?? const <String>[]) {
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

  /// Ordered with record/load, so a pending old write cannot undo this clear.
  Future<void> clear({String? identityUserId}) async {
    final key = _keyForHash(
      PreferencesService.identityStorageId(identityUserId),
    );
    await _serialize<void>(() async {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.remove(key)) {
        throw StateError('Telemetry ledger clear failed');
      }
    });
  }
}
