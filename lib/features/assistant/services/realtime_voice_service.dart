import '../models/assistant_mode.dart';

/// Describes whether the realtime voice transport can be used in this build.
enum RealtimeVoiceAvailability { unavailable, available }

/// A small boundary for the future LiveKit/OpenAI Realtime implementation.
///
/// Keeping this contract separate from [AppController] lets the UI expose the
/// mode now without pretending that a missing Agent/ephemeral-token endpoint
/// is a working voice session. The production implementation can be injected
/// later without changing the conversation storage or message widgets.
abstract interface class RealtimeVoiceService {
  const RealtimeVoiceService();

  AssistantMode get mode => AssistantMode.realtimeVoice;

  RealtimeVoiceAvailability get availability;

  String get availabilityMessage;
}

/// Safe default used until a realtime Agent endpoint is configured.
class UnconfiguredRealtimeVoiceService extends RealtimeVoiceService {
  const UnconfiguredRealtimeVoiceService();

  @override
  RealtimeVoiceAvailability get availability =>
      RealtimeVoiceAvailability.unavailable;

  @override
  String get availabilityMessage => '实时语音服务尚未配置 Agent 地址和会话 Token 接口。';
}
