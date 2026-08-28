import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:board_game_agent/models/ai_run.dart';
import 'package:board_game_agent/services/ai_run_telemetry.dart';

void main() {
  test('persists a bounded secret-free run ledger', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferencesAiRunTelemetrySink sink =
        SharedPreferencesAiRunTelemetrySink(maxEntries: 2);

    await Future.wait(<Future<void>>[
      sink.record(_result('run-1')),
      sink.record(_result('run-2')),
      sink.record(_result('run-3')),
    ]);

    final List<Map<String, dynamic>> records = await sink.load();
    expect(records, hasLength(2));
    expect(records.first['runId'], 'run-2');
    expect(records.last['runId'], 'run-3');
    expect(records.last.containsKey('apiKey'), isFalse);
    expect(records.last['terminalEventType'], 'response.completed');
    expect(records.last['rawEventCount'], 3);
  });
}

AiRunResult _result(String runId) => AiRunResult(
  runId: runId,
  status: AiRunStatus.completed,
  model: 'test-model',
  responseId: 'response-$runId',
  terminalEventType: 'response.completed',
  rawEventCount: 3,
  outputItemCount: 1,
  requestCount: 1,
);
