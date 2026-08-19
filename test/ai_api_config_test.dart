import 'package:board_game_agent/models/ai_api_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('provider presets keep model and authentication settings together', () {
    expect(AiProviderPreset.values, <AiProviderPreset>[
      AiProviderPreset.openAi,
      AiProviderPreset.deepSeek,
      AiProviderPreset.custom,
    ]);
    expect(AiApiConfig.defaultOpenAi.model, 'gpt-4o-mini');
    expect(AiApiConfig.defaultOpenAi.apiKeyHeader, 'Authorization');
    expect(AiApiConfig.defaultDeepSeek.apiKeyHeader, 'Authorization');
    expect(AiApiConfig.defaultDeepSeek.model, 'deepseek-chat');
    expect(AiApiConfig.defaultDeepSeek.chatPath, '/chat/completions');
  });

  test('detects provider from a saved base URL', () {
    expect(
      detectAiProviderPreset(AiApiConfig.defaultOpenAi),
      AiProviderPreset.openAi,
    );
    expect(
      detectAiProviderPreset(AiApiConfig.defaultDeepSeek),
      AiProviderPreset.deepSeek,
    );
    expect(
      detectAiProviderPreset(AiApiConfig.defaultCustom),
      AiProviderPreset.custom,
    );
  });

  test('migrates a removed model away from legacy defaults', () {
    final AiApiConfig config = AiApiConfig.fromJson(
      '{"name":"OpenAI","baseUrl":"https://api.openai.com/v1",'
      '"apiKey":"key","model":"mimo-v2.5-pro",'
      '"apiKeyHeader":"api-key"}',
    );

    expect(config.model, AiApiConfig.defaultOpenAi.model);
    expect(config.apiKeyHeader, 'Authorization');
    expect(config.apiKey, 'key');
  });

  test('replaces a saved MiMo endpoint with the new default provider', () {
    final AiApiConfig config = AiApiConfig.fromJson(
      '{"name":"MiMo","baseUrl":"https://token-plan-cn.xiaomimimo.com/v1",'
      '"apiKey":"legacy-key","model":"mimo-v2.5-pro",'
      '"apiKeyHeader":"api-key"}',
    );

    expect(config.name, AiApiConfig.defaultOpenAi.name);
    expect(config.baseUrl, AiApiConfig.defaultOpenAi.baseUrl);
    expect(config.apiKey, isEmpty);
    expect(config.model, AiApiConfig.defaultOpenAi.model);
    expect(config.apiKeyHeader, AiApiConfig.defaultOpenAi.apiKeyHeader);
  });

  test('does not silently reuse MiMo defaults for an unknown provider', () {
    final AiApiConfig config = AiApiConfig.fromJson(
      '{"name":"Gateway","baseUrl":"https://gateway.example/v1",'
      '"apiKey":"key","model":"mimo-v2.5-pro",'
      '"apiKeyHeader":"api-key"}',
    );

    expect(config.model, isEmpty);
    expect(config.apiKeyHeader, 'Authorization');
  });

  test('round trips custom model and authentication settings', () {
    const AiApiConfig original = AiApiConfig(
      name: 'Gateway',
      baseUrl: 'https://gateway.example/v1',
      apiKey: 'key',
      model: 'gateway-model',
      apiKeyHeader: 'x-api-key',
      chatPath: '/chat/completions',
    );

    final AiApiConfig restored = AiApiConfig.fromJson(original.toJson());

    expect(restored.name, original.name);
    expect(restored.baseUrl, original.baseUrl);
    expect(restored.model, original.model);
    expect(restored.apiKeyHeader, original.apiKeyHeader);
    expect(restored.chatPath, original.chatPath);
  });
}
