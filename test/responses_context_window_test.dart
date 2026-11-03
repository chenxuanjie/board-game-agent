import 'dart:convert';

import 'package:app_ai_client/app_ai_client.dart';
import 'package:board_game_agent/features/assistant/models/chat_message.dart';
import 'package:board_game_agent/features/assistant/models/responses_context_window.dart';
import 'package:board_game_agent/features/assistant/services/responses_compaction_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

ChatMessage _message(String id, ChatRole role, String text) =>
    ChatMessage(id: id, role: role, text: text, timestamp: DateTime(2026));

ResponsesContextWindow? _window({String payload = 'opaque'}) =>
    ResponsesContextWindow.capture(
      request: ResponsesRequest(
        endpoint: const AiEndpointConfig(
          name: 'test',
          baseUrl: 'https://example.test/v1',
          apiKey: 'test-key',
          model: 'test-model',
        ),
        input: const [ResponsesTextInput('hello')],
      ),
      response: ResponsesResponse(
        text: 'answer',
        model: 'test-model',
        outputItems: [
          ResponsesRawInput({
            'type': 'compaction',
            'id': 'cmp',
            'encrypted_content': payload,
          }),
        ],
      ),
      history: [_message('user-1', ChatRole.user, 'hello')],
      prompt: 'hello',
      answer: 'answer',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key = 'responses_compaction_state.v1';
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'encrypted store restores the full versioned window and boundary',
    () async {
      final original = _window()!;
      await SecureResponsesCompactionStore().save({'scope': original});
      final restored = (await SecureResponsesCompactionStore()
          .load())['scope']!;
      expect(restored.toJson(), original.toJson());
      final input = restored.continueWith([
        _message('user-1', ChatRole.user, 'hello'),
        _message('answer-1', ChatRole.assistant, 'answer'),
        _message('user-2', ChatRole.user, 'new condition'),
      ], 'new condition')!;
      expect(input, hasLength(3)); // marker + retained answer + new user input
      expect(
        jsonEncode(input.map((item) => item.toJson()).toList()),
        contains('new condition'),
      );
      final raw =
          jsonDecode((await const FlutterSecureStorage().read(key: key))!)
              as Map;
      expect(raw['version'], 2);
    },
  );

  test(
    'legacy compaction-only state is ignored rather than guessing a boundary',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        key: jsonEncode({
          'version': 1,
          'contexts': {
            'scope': [
              {'type': 'compaction', 'encrypted_content': 'old'},
            ],
          },
        }),
      });
      expect(await SecureResponsesCompactionStore().load(), isEmpty);
    },
  );

  test('an invalid cache entry does not discard other valid windows', () async {
    FlutterSecureStorage.setMockInitialValues({
      key: jsonEncode({
        'version': 2,
        'contexts': {
          'valid': _window()!.toJson(),
          'invalid': {'items': []},
        },
      }),
    });
    expect((await SecureResponsesCompactionStore().load()).keys, ['valid']);
  });

  test(
    'edited, removed or mismatched answer boundaries reject cached input',
    () {
      final window = _window()!;
      for (final history in <List<ChatMessage>>[
        [],
        [
          _message('user-1', ChatRole.user, 'changed'),
          _message('a', ChatRole.assistant, 'answer'),
        ],
        [
          _message('user-1', ChatRole.user, 'hello'),
          _message('a', ChatRole.assistant, 'edited answer'),
        ],
        [
          _message('different-user-id', ChatRole.user, 'hello'),
          _message('a', ChatRole.assistant, 'answer'),
        ],
      ]) {
        expect(window.continueWith(history, 'next'), isNull);
      }
    },
  );

  test(
    'identical prompt text across turns does not duplicate or skip a user turn',
    () {
      final input = _window()!.continueWith([
        _message('user-1', ChatRole.user, 'hello'),
        _message('a', ChatRole.assistant, 'answer'),
        _message('user-2', ChatRole.user, 'hello'),
      ], 'hello')!;
      expect(input, hasLength(3));
      expect(input.last.toJson()['role'], 'user');
    },
  );

  test(
    'oversized windows are discarded whole instead of dropping post-compaction turns',
    () {
      expect(_window(payload: 'x' * ResponsesContextWindow.maxBytes), isNull);
    },
  );
}
