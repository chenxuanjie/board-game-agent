import 'package:board_game_agent/features/assistant/models/ai_api_config.dart';
import 'package:board_game_agent/features/assistant/models/ai_model_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catalog admits only documented general text model IDs', () {
    for (final String id in <String>[
      'gpt-5.6',
      'gpt-5.6-sol',
      'gpt-5.6-terra',
      'gpt-5.6-luna',
      'gpt-6-astra',
      'gpt-6-sol',
      'gpt-6-luna',
    ]) {
      expect(AiModelPolicy.allowsModel(id), isTrue, reason: id);
    }
    for (final String id in <String>[
      'gpt-5.5',
      'gpt-5.6-cyber',
      'gpt-5.6-image',
      'gpt-6-astra-extra',
      'gpt-5.6-luna-2026-09-01',
      'gpt-6-sol-2026-09-01',
      'gpt-7-sol',
      'gateway-gpt-5.6-sol',
      'my-best-model',
      'text-embedding-3-large',
      '',
    ]) {
      expect(AiModelPolicy.allowsModel(id), isFalse, reason: id);
    }
  });

  test('each model records exactly its documented API effort values', () {
    const List<AiReasoningEffort> standard = <AiReasoningEffort>[
      AiReasoningEffort.none,
      AiReasoningEffort.low,
      AiReasoningEffort.medium,
      AiReasoningEffort.high,
      AiReasoningEffort.xhigh,
      AiReasoningEffort.max,
    ];
    for (final String id in <String>[
      'gpt-5.6',
      'gpt-5.6-sol',
      'gpt-5.6-terra',
      'gpt-5.6-luna',
      'gpt-6-sol',
      'gpt-6-luna',
    ]) {
      final AiModelCapability capability = AiModelPolicy.capabilityFor(id)!;
      expect(capability.apiEfforts, standard, reason: id);
      expect(
        capability.documentationUrl,
        startsWith('https://developers.openai.com/'),
      );
      expect(AiModelPolicy.reasoningEfforts(id), <AiReasoningEffort>[
        AiReasoningEffort.automatic,
        ...standard,
      ]);
    }
    expect(
      AiModelPolicy.capabilityFor('gpt-6-astra')!.apiEfforts,
      standard.where(
        (AiReasoningEffort effort) => effort != AiReasoningEffort.none,
      ),
    );
    expect(
      AiModelPolicy.capabilityFor(
        'gpt-6-luna',
      )!.apiEfforts.map((AiReasoningEffort effort) => effort.name),
      isNot(contains('ultra')),
    );
    expect(AiModelPolicy.reasoningEfforts('relay-alias'), isNull);
  });

  test('resolved controls match the fields sent by request builders', () {
    final AiApiConfig config = AiApiConfig.defaultOpenAi.copyWith(
      model: 'gpt-5.6-sol',
      reasoningEffort: AiReasoningEffort.xhigh,
      responseSpeed: AiResponseSpeed.fast,
    );
    final AiModelResolution resolved = AiModelPolicy.resolve(config);
    expect(resolved.isUsable, isTrue);
    expect(resolved.modelId, 'gpt-5.6-sol');
    expect(resolved.reasoningEffort, 'xhigh');
    expect(resolved.serviceTier, 'fast');
    expect(
      AiModelPolicy.resolve(
        config.copyWith(reasoningEffort: AiReasoningEffort.automatic),
      ).reasoningEffort,
      isNull,
    );
    expect(
      AiModelPolicy.resolve(
        config.copyWith(
          model: 'gpt-6-astra',
          reasoningEffort: AiReasoningEffort.none,
        ),
      ).issue,
      AiModelIssue.unsupportedEffort,
    );
    expect(
      AiModelPolicy.resolve(config.copyWith(model: 'gpt-5.5')).issue,
      AiModelIssue.modelNotAllowed,
    );
  });

  test('new effort values survive preference serialization', () {
    for (final AiReasoningEffort effort in <AiReasoningEffort>[
      AiReasoningEffort.none,
      AiReasoningEffort.xhigh,
      AiReasoningEffort.max,
    ]) {
      final AiApiConfig config = AiApiConfig.defaultOpenAi.copyWith(
        model: 'gpt-5.6',
        reasoningEffort: effort,
      );
      expect(AiApiConfig.fromJson(config.toJson()).reasoningEffort, effort);
    }
  });
}
