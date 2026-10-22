/// The two user-facing ways to interact with the assistant.
///
/// The text mode keeps the existing keyboard and system dictation path. The
/// realtime mode is deliberately separated so it can later be backed by a
/// LiveKit/OpenAI Realtime session without changing the conversation model.
enum AssistantMode { textAndDictation, realtimeVoice }

extension AssistantModeX on AssistantMode {
  String get code {
    switch (this) {
      case AssistantMode.textAndDictation:
        return 'text_and_dictation';
      case AssistantMode.realtimeVoice:
        return 'realtime_voice';
    }
  }

  static AssistantMode fromCode(String? value) {
    for (final AssistantMode mode in AssistantMode.values) {
      if (mode.code == value) {
        return mode;
      }
    }
    return AssistantMode.textAndDictation;
  }
}
