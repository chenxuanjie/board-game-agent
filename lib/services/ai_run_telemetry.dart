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
