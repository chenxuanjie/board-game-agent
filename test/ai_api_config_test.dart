import 'package:board_game_agent/models/ai_api_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('provider presets keep model and authentication settings together', () {
    expect(AiProviderPreset.values, <AiProviderPreset>[
      AiProviderPreset.openAi,
      AiProviderPreset.deepSeek,
      AiProviderPreset.custom,
    ]);
    expect(AiApiConfig.defaultOpenAi.model, isEmpty);
    expect(AiApiConfig.defaultOpenAi.apiKeyHeader, 'Authorization');
    expect(AiApiConfig.defaultDeepSeek.apiKeyHeader, 'Authorization');
    expect(AiApiConfig.defaultDeepSeek.model, isEmpty);
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

  test('round trips a saved model while normalizing transport settings', () {
    const AiApiConfig original = AiApiConfig(
      name: 'Gateway',
      baseUrl: 'https://gateway.example/v1',
      apiKey: 'key',
      model: 'gateway-model',
      apiKeyHeader: 'x-api-key',
      chatPath: '/custom-path',
    );

    final AiApiConfig restored = AiApiConfig.fromJson(original.toJson());

    expect(restored.name, original.name);
    expect(restored.baseUrl, original.baseUrl);
    expect(restored.model, original.model);
    expect(restored.apiKeyHeader, 'Authorization');
    expect(restored.chatPath, '/chat/completions');
  });

  test('round trips reasoning and response-speed preferences', () {
    const AiApiConfig original = AiApiConfig(
      name: 'Gateway',
      baseUrl: 'https://gateway.example/v1',
      apiKey: 'key',
      model: 'reasoning-model',
      apiKeyHeader: 'Authorization',
      reasoningEffort: AiReasoningEffort.high,
      responseSpeed: AiResponseSpeed.fast,
    );

    final AiApiConfig restored = AiApiConfig.fromJson(original.toJson());

    expect(restored.reasoningEffort, AiReasoningEffort.high);
    expect(restored.responseSpeed, AiResponseSpeed.fast);
    expect(restored.reasoningEffort.requestValue, 'high');
    expect(restored.responseSpeed.serviceTier, 'fast');
  });

  test(
    'old saved configs default optional generation controls to automatic',
    () {
      final AiApiConfig restored = AiApiConfig.fromJson(
        '{"name":"Gateway","baseUrl":"https://gateway.example/v1",'
        '"apiKey":"key","model":"model"}',
      );

      expect(restored.reasoningEffort, AiReasoningEffort.automatic);
      expect(restored.responseSpeed, AiResponseSpeed.automatic);
      expect(restored.toMap()['reasoningEffort'], 'automatic');
      expect(restored.toMap()['responseSpeed'], 'automatic');
    },
  );

  test('normalizes custom provider names for preset identity', () {
    const AiApiConfig config = AiApiConfig(
      name: '  Loomex  ',
      baseUrl: 'https://gateway.example/v1',
      apiKey: 'key',
      model: 'model',
      apiKeyHeader: 'Authorization',
    );

    expect(config.normalizedName, 'loomex');
    expect(AiApiConfig.isBuiltInProviderName(' openai '), isTrue);
    expect(
      AiApiConfig.isBuiltInProviderName('Custom OpenAI-compatible'),
      isTrue,
    );
    expect(AiApiConfig.isBuiltInProviderName('Loomex'), isFalse);
  });

  test(
    'decodes custom presets and keeps the first entry for duplicate names',
    () {
      final String encoded = AiApiConfig.encodeList(<AiApiConfig>[
        const AiApiConfig(
          name: 'Loomex',
          baseUrl: 'https://first.example/v1',
          apiKey: 'first-key',
          model: 'first-model',
          apiKeyHeader: 'Authorization',
        ),
        const AiApiConfig(
          name: ' loomex ',
          baseUrl: 'https://second.example/v1',
          apiKey: 'second-key',
          model: 'second-model',
          apiKeyHeader: 'Authorization',
        ),
        AiApiConfig.defaultOpenAi,
      ]);

      final List<AiApiConfig> restored = AiApiConfig.decodeList(encoded);

      expect(restored, hasLength(1));
      expect(restored.single.name, 'Loomex');
      expect(restored.single.baseUrl, 'https://first.example/v1');
    },
  );
}
