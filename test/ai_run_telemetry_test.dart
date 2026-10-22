import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:board_game_agent/features/assistant/models/ai_run.dart';
import 'package:board_game_agent/features/assistant/services/ai_run_telemetry.dart';
import 'package:board_game_agent/features/assistant/models/answer_source.dart';
import 'package:board_game_agent/features/assistant/models/board_game_ai_answer.dart';
import 'package:board_game_agent/features/settings/services/preferences_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
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

  test(
    'legacy ledger remains guest-owned and signed-in runs never merge into it',
    () async {
      final legacy = jsonEncode(_result('legacy-guest').toMap());
      SharedPreferences.setMockInitialValues({
        SharedPreferencesAiRunTelemetrySink.storageKey: [legacy],
      });
      final sink = SharedPreferencesAiRunTelemetrySink();
      await Future.wait([
        sink.record(_result('a', contextKey: _accountContext('a'))),
        sink.record(_result('b', contextKey: _accountContext('b'))),
        sink.record(
          _result('guest', contextKey: 'conversation:123|$_endpointHash'),
        ),
      ]);
      expect(_ids(await sink.load()), ['legacy-guest', 'guest']);
      expect(_ids(await sink.load(identityUserId: 'a')), ['a']);
      expect(_ids(await sink.load(identityUserId: 'b')), ['b']);
      expect(await sink.load(identityUserId: 'new-account'), isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs
            .getStringList(SharedPreferencesAiRunTelemetrySink.storageKey)!
            .first,
        legacy,
      );
      expect(prefs.getStringList(_accountLedgerKey('a')), hasLength(1));
      expect(prefs.getStringList(_accountLedgerKey('b')), hasLength(1));
    },
  );

  test(
    'interleaved queued runs pin their account namespace and retention limit',
    () async {
      final sink = SharedPreferencesAiRunTelemetrySink(maxEntries: 2);
      final writes = <Future<void>>[];
      for (var i = 1; i <= 3; i++) {
        writes.add(
          sink.record(_result('guest-$i', contextKey: 'global|$_endpointHash')),
        );
        writes.add(
          sink.record(_result('a-$i', contextKey: _accountContext('a'))),
        );
        writes.add(
          sink.record(
            _result(
              'b-$i',
              contextKey: _accountContext('b', localId: 'conversation:789'),
            ),
          ),
        );
      }
      // Each load queues after the writes even when the caller has not awaited them.
      final a = sink.load(identityUserId: 'a');
      final b = sink.load(identityUserId: 'b');
      final guest = sink.load();
      expect(_ids(await a), ['a-2', 'a-3']);
      expect(_ids(await b), ['b-2', 'b-3']);
      expect(_ids(await guest), ['guest-2', 'guest-3']);
      await Future.wait(writes);
      final restarted = SharedPreferencesAiRunTelemetrySink();
      expect(_ids(await restarted.load(identityUserId: 'a')), ['a-2', 'a-3']);
      expect(_ids(await restarted.load(identityUserId: 'b')), ['b-2', 'b-3']);
    },
  );

  test(
    'clear is ordered with pending writes and removes only its selected account',
    () async {
      final sink = SharedPreferencesAiRunTelemetrySink();
      final before = sink.record(
        _result('a-before', contextKey: _accountContext('a')),
      );
      final other = sink.record(_result('b', contextKey: _accountContext('b')));
      final guest = sink.record(_result('guest'));
      final clear = sink.clear(identityUserId: 'a');
      final empty = sink.load(identityUserId: 'a');
      final after = sink.record(
        _result('a-after', contextKey: _accountContext('a')),
      );
      expect(await empty, isEmpty);
      expect(_ids(await sink.load(identityUserId: 'a')), ['a-after']);
      await Future.wait([before, other, guest, clear, after]);
      expect(_ids(await sink.load(identityUserId: 'b')), ['b']);
      expect(_ids(await sink.load()), ['guest']);
      await sink.clear();
      expect(await sink.load(), isEmpty);
      expect(_ids(await sink.load(identityUserId: 'a')), ['a-after']);
      expect(_ids(await sink.load(identityUserId: 'b')), ['b']);
    },
  );

  test(
    'session-only context and exact Unicode identities use the same account hash',
    () async {
      const userId = '../用户/A';
      final sink = SharedPreferencesAiRunTelemetrySink();
      await sink.record(
        _result('session-only', sessionId: _accountContext(userId)),
      );
      await sink.record(
        _result(
          'both',
          contextKey: _accountContext(userId),
          sessionId: _accountContext(userId),
        ),
      );
      // A plain provider conversation ID is also a valid account scope marker.
      await sink.record(
        _result(
          'provider-id',
          contextKey: _accountContext(userId).split('|').first,
        ),
      );
      expect(await sink.load(), isEmpty);
      expect(_ids(await sink.load(identityUserId: userId)), [
        'session-only',
        'both',
        'provider-id',
      ]);
      expect(await sink.load(identityUserId: '../用户/a'), isEmpty);
    },
  );

  test(
    'corrupt entries do not hide valid records or contaminate another ledger',
    () async {
      SharedPreferences.setMockInitialValues({
        _accountLedgerKey('a'): [
          'broken JSON',
          '[]',
          jsonEncode(_result('a').toMap()),
        ],
        SharedPreferencesAiRunTelemetrySink.storageKey: [
          jsonEncode(_result('guest').toMap()),
        ],
      });
      final sink = SharedPreferencesAiRunTelemetrySink();
      expect(_ids(await sink.load(identityUserId: 'a')), ['a']);
      expect(_ids(await sink.load()), ['guest']);
      expect(await sink.load(identityUserId: 'b'), isEmpty);
    },
  );

  test(
    'metadata snapshot is captured at enqueue and excludes answer and buffered text',
    () async {
      final stages = <AiStageResult>[
        const AiStageResult(
          stageId: 'answer',
          scope: AiKnowledgeScope.general(),
          status: AiStageStatus.answered,
          bufferedText: 'private buffered text',
        ),
      ];
      final sink = SharedPreferencesAiRunTelemetrySink();
      final write = sink.record(
        AiRunResult(
          runId: 'a',
          status: AiRunStatus.completed,
          contextKey: _accountContext('a'),
          stages: stages,
          answer: BoardGameAiAnswer(
            text: 'private final answer',
            source: AnswerSource.generalAdvice,
          ),
        ),
      );
      stages.clear();
      await write;
      final records = await sink.load(identityUserId: 'a');
      expect(records.single['stages'], hasLength(1));
      expect(jsonEncode(records), isNot(contains('private buffered text')));
      expect(jsonEncode(records), isNot(contains('private final answer')));
      expect(await sink.load(), isEmpty);
    },
  );

  final validHash = PreferencesService.identityStorageId('a')!;
  final invalidContexts = [
    'conversation:personal_v1:short:global|$_endpointHash',
    'conversation:personal_v1:../a:global|$_endpointHash',
    'conversation:personal_v1:${validHash.toUpperCase()}:global|$_endpointHash',
    'conversation:personal_v1:$validHash:|$_endpointHash',
    'conversation:personal_v1:$validHash:global|not-an-endpoint-hash',
    'conversation:personal_v1:$validHash:global|$_endpointHash\n',
  ];
  for (var i = 0; i < invalidContexts.length; i++) {
    test(
      'malformed account context $i fails without falling back to guest',
      () async {
        final sink = SharedPreferencesAiRunTelemetrySink();
        await expectLater(
          sink.record(_result('invalid', contextKey: invalidContexts[i])),
          throwsFormatException,
        );
        expect(await sink.load(), isEmpty);
        expect(await sink.load(identityUserId: 'a'), isEmpty);
        await sink.record(_result('valid', contextKey: _accountContext('a')));
        expect(_ids(await sink.load(identityUserId: 'a')), ['valid']);
      },
    );
  }

  test(
    'conflicting context and session scope markers never write either account',
    () async {
      final sink = SharedPreferencesAiRunTelemetrySink();
      for (final session in [
        _accountContext('b'),
        'global|$_endpointHash',
        invalidContexts.first,
      ]) {
        await expectLater(
          sink.record(
            _result(
              'invalid',
              contextKey: _accountContext('a'),
              sessionId: session,
            ),
          ),
          throwsFormatException,
        );
      }
      await expectLater(
        sink.record(
          _result(
            'invalid',
            contextKey: 'global|$_endpointHash',
            sessionId: _accountContext('a'),
          ),
        ),
        throwsFormatException,
      );
      expect(await sink.load(), isEmpty);
      expect(await sink.load(identityUserId: 'a'), isEmpty);
      expect(await sink.load(identityUserId: 'b'), isEmpty);
      await sink.record(_result('guest'));
      expect(_ids(await sink.load()), ['guest']);
    },
  );
}

const _endpointHash =
    '1111111111111111111111111111111111111111111111111111111111111111';

String _accountContext(String userId, {String localId = 'global'}) =>
    'conversation:personal_v1:${PreferencesService.identityStorageId(userId)}:$localId|$_endpointHash';

String _accountLedgerKey(String userId) =>
    'personal_v1.${PreferencesService.identityStorageId(userId)}.${SharedPreferencesAiRunTelemetrySink.storageKey}';

List<Object?> _ids(List<Map<String, dynamic>> records) =>
    records.map((record) => record['runId']).toList();

AiRunResult _result(String runId, {String? contextKey, String? sessionId}) =>
    AiRunResult(
      runId: runId,
      status: AiRunStatus.completed,
      model: 'test-model',
      responseId: 'response-$runId',
      terminalEventType: 'response.completed',
      rawEventCount: 3,
      outputItemCount: 1,
      requestCount: 1,
      contextKey: contextKey,
      sessionId: sessionId,
    );
