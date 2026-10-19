import 'dart:async';
import 'dart:convert';

import 'package:app_ai_client/app_ai_client.dart';
import 'package:board_game_agent/features/assistant/services/web_ai_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const endpoint = AiEndpointConfig(
  name: 'test',
  baseUrl: 'https://www.loomex.lol/v1',
  apiKey: 'fixture-provider-key',
  model: 'test-model',
);

void main() {
  test(
    'existing SDK discovers models through same origin without putting keys in URL',
    () async {
      final transport = WebAiHttpClient(
        site: Uri.parse('https://games.example:18887'),
        inner: MockClient((request) async {
          expect(
            request.url.toString(),
            'https://games.example:18887/api/ai/request',
          );
          expect(
            request.headers['x-bga-ai-target'],
            'https://www.loomex.lol/v1/models',
          );
          expect(request.headers['x-board-game-request'], '1');
          expect(
            request.headers['authorization'],
            'Bearer fixture-provider-key',
          );
          expect(request.url.query, isEmpty);
          return http.Response(
            '{"data":[{"id":"test-model","object":"model","created":1,"owned_by":"fixture"}]}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final sdk = OpenAiDartAiClient(httpClient: transport);
      addTearDown(() {
        sdk.close();
        transport.close();
      });
      final models = await sdk.listModels(endpoint);
      expect(models.single.id, 'test-model');
    },
  );

  test(
    'Responses keeps the existing SDK mapping and does not switch to chat',
    () async {
      final transport = WebAiHttpClient(
        site: Uri.parse('https://games.example:18887'),
        inner: MockClient((request) async {
          expect(request.url.path, '/api/ai/request');
          expect(
            request.headers['x-bga-ai-target'],
            'https://www.loomex.lol/v1/responses',
          );
          final data = jsonDecode(request.body) as Map;
          expect(data['model'], 'test-model');
          expect(data['input'], isA<List>());
          return http.Response(
            jsonEncode({
              'id': 'resp_test',
              'object': 'response',
              'created_at': 1,
              'model': 'test-model',
              'status': 'completed',
              'output': [
                {
                  'type': 'message',
                  'id': 'msg_test',
                  'role': 'assistant',
                  'status': 'completed',
                  'content': [
                    {'type': 'output_text', 'text': '规则回答'},
                  ],
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final sdk = OpenAiDartResponsesAiClient(httpClient: transport);
      addTearDown(() {
        sdk.close();
        transport.close();
      });
      final response = await sdk.complete(
        ResponsesRequest(
          endpoint: endpoint,
          input: [const ResponsesTextInput('规则问题')],
        ),
      );
      expect(response.text, '规则回答');
    },
  );

  test(
    'stream bytes and the original abort trigger pass through unchanged',
    () async {
      final capture = _CaptureClient();
      final transport = WebAiHttpClient(
        inner: capture,
        site: Uri.parse('https://games.example:18887'),
      );
      addTearDown(transport.close);
      final abort = Completer<void>();
      final original =
          http.AbortableRequest(
              'POST',
              Uri.parse('${endpoint.baseUrl}/chat/completions'),
              abortTrigger: abort.future,
            )
            ..headers.addAll({
              'Authorization': 'Bearer fixture-provider-key',
              'Content-Type': 'application/json',
              'Cookie': 'must-not-forward',
              'X-Syno-Token': 'must-not-forward',
            })
            ..body = '{"model":"test-model","stream":true}';
      final response = await transport.send(original);
      expect(capture.request, isA<http.Abortable>());
      expect(
        (capture.request as http.Abortable).abortTrigger,
        same(abort.future),
      );
      expect(
        capture.request.headers.keys.map((e) => e.toLowerCase()),
        isNot(contains('cookie')),
      );
      expect(
        capture.request.headers.keys.map((e) => e.toLowerCase()),
        isNot(contains('x-syno-token')),
      );
      final iterator = StreamIterator(response.stream);
      capture.chunks.add(utf8.encode('data: first\n\n'));
      expect(await iterator.moveNext(), isTrue);
      expect(utf8.decode(iterator.current), 'data: first\n\n');
      abort.complete();
      await iterator.cancel();
      await capture.chunks.close();
    },
  );

  test('Web never forwards a plaintext provider request', () async {
    final transport = WebAiHttpClient(
      inner: MockClient((_) async => throw StateError('must not send')),
      site: Uri.parse('https://games.example:18887'),
    );
    addTearDown(transport.close);
    await expectLater(
      transport.send(
        http.Request('GET', Uri.parse('http://nas.local/v1/models')),
      ),
      throwsA(isA<http.ClientException>()),
    );
  });
}

class _CaptureClient extends http.BaseClient {
  late http.BaseRequest request;
  final chunks = StreamController<List<int>>();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    this.request = request;
    await request.finalize().drain<void>();
    return http.StreamedResponse(
      chunks.stream,
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  }
}
