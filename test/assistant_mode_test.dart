import 'package:flutter_test/flutter_test.dart';

import 'package:board_game_agent/models/assistant_mode.dart';

void main() {
  test('assistant modes have stable preference codes', () {
    expect(AssistantMode.textAndDictation.code, 'text_and_dictation');
    expect(AssistantMode.realtimeVoice.code, 'realtime_voice');
  });

  test('unknown assistant mode preferences fall back to text mode', () {
    expect(
      AssistantModeX.fromCode('future_mode'),
      AssistantMode.textAndDictation,
    );
    expect(AssistantModeX.fromCode(null), AssistantMode.textAndDictation);
  });
}
