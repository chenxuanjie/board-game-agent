import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text_windows/speech_to_text_windows.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('speech_to_text_windows');
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late SpeechToTextWindows speech;
  late List<String> calls;

  setUp(() async {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return switch (call.method) {
        'initialize' || 'listen' => true,
        'locales' => ['en-US:English'],
        _ => null,
      };
    });
    speech = SpeechToTextWindows();
    expect(await speech.initialize(), isTrue);
  });
  tearDown(() {
    channel.setMethodCallHandler(null);
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<void> nativeEvent(String method, String payload) async {
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(MethodCall(method, payload)),
      (_) {},
    );
  }

  test('platform events preserve status, recognition and error protocol',
      () async {
    final statuses = <String>[];
    final texts = <String>[];
    final errors = <String>[];
    speech.onStatus = statuses.add;
    speech.onTextRecognition = texts.add;
    speech.onError = errors.add;
    await speech.listen();
    await nativeEvent('notifyStatus', 'listening');
    final recognized = jsonEncode({
      'alternates': [
        {
          'recognizedWords': '规则是什么？',
          'recognizedPhrases': null,
          'confidence': -1.0
        },
      ],
      'finalResult': true,
    });
    await nativeEvent('textRecognition', recognized);
    await nativeEvent(
        'notifyError', '{"errorMsg":"SAPI failure","permanent":false}');
    await nativeEvent('notifyStatus', 'notListening');
    expect(statuses, ['listening', 'notListening']);
    expect(
        jsonDecode(texts.single)['alternates'][0]['recognizedWords'], '规则是什么？');
    expect(jsonDecode(errors.single)['permanent'], isFalse);
  });

  test('repeated start, stop, cancel and restart keep the channel usable',
      () async {
    for (var i = 0; i < 10; i++) {
      expect(await speech.listen(), isTrue);
      await speech.stop();
      expect(await speech.listen(), isTrue);
      await speech.cancel();
    }
    expect(calls.where((call) => call == 'listen').length, 20);
    expect(calls.where((call) => call == 'stop').length, 10);
    expect(calls.where((call) => call == 'cancel').length, 10);
  });

  test('error status does not prevent another recognition session', () async {
    final statuses = <String>[];
    speech.onStatus = statuses.add;
    await speech.listen();
    await nativeEvent('notifyStatus', 'notListening');
    await nativeEvent(
        'notifyError', '{"errorMsg":"SAPI failure","permanent":false}');
    expect(await speech.listen(), isTrue);
    await nativeEvent('notifyStatus', 'listening');
    expect(statuses, ['notListening', 'listening']);
  });
}
