import 'ai_api_config.dart';

/// Deliberately conservative catalog for the app's GPT-5.6-or-newer policy.
///
/// /models supplies identifiers, not reasoning capabilities or proof of a
/// gateway's upstream route. Each entry below links to its official model
/// page; only IDs actually documented there are admitted.
class AiModelPolicy {
  const AiModelPolicy._();

  static const String catalogVersion = '2026-09-29';

  static const List<AiReasoningEffort> _standardEfforts = <AiReasoningEffort>[
    AiReasoningEffort.none,
    AiReasoningEffort.low,
    AiReasoningEffort.medium,
    AiReasoningEffort.high,
    AiReasoningEffort.xhigh,
    AiReasoningEffort.max,
  ];
  static const List<AiReasoningEffort> _astraEfforts = <AiReasoningEffort>[
    AiReasoningEffort.low,
    AiReasoningEffort.medium,
    AiReasoningEffort.high,
    AiReasoningEffort.xhigh,
    AiReasoningEffort.max,
  ];

  static const Map<String, AiModelCapability>
  _catalog = <String, AiModelCapability>{
    'gpt-5.6': AiModelCapability(
      apiEfforts: _standardEfforts,
      documentationUrl:
          'https://developers.openai.com/api/docs/guides/latest-model?model=gpt-5.6',
    ),
    'gpt-5.6-sol': AiModelCapability(
      apiEfforts: _standardEfforts,
      documentationUrl:
          'https://developers.openai.com/api/docs/models/gpt-5.6-sol',
    ),
    'gpt-5.6-terra': AiModelCapability(
      apiEfforts: _standardEfforts,
      documentationUrl:
          'https://developers.openai.com/api/docs/models/gpt-5.6-terra',
    ),
    'gpt-5.6-luna': AiModelCapability(
      apiEfforts: _standardEfforts,
      documentationUrl:
          'https://developers.openai.com/api/docs/models/gpt-5.6-luna',
    ),
    'gpt-6-astra': AiModelCapability(
      apiEfforts: _astraEfforts,
      documentationUrl:
          'https://developers.openai.com/api/docs/models/gpt-6-astra',
    ),
    'gpt-6-sol': AiModelCapability(
      apiEfforts: _standardEfforts,
      documentationUrl:
          'https://developers.openai.com/api/docs/models/gpt-6-sol',
    ),
    'gpt-6-luna': AiModelCapability(
      apiEfforts: _standardEfforts,
      documentationUrl:
          'https://developers.openai.com/api/docs/models/gpt-6-luna',
    ),
  };

  /// Only general-purpose text models documented in this catalog are shown.
  /// Unknown aliases, unlisted snapshots, specialty models and future
  /// families stay unavailable until their capabilities are reviewed.
  static AiModelCapability? capabilityFor(String modelId) =>
      _catalog[modelId.trim()];

  static List<AiReasoningEffort>? reasoningEfforts(String modelId) {
    final AiModelCapability? capability = capabilityFor(modelId);
    if (capability == null) return null;
    return <AiReasoningEffort>[
      AiReasoningEffort.automatic,
      ...capability.apiEfforts,
    ];
  }

  /// Picker choices omit protocol defaults while retaining them for stored configs.
  static List<AiReasoningEffort>? selectableReasoningEfforts(String modelId) =>
      reasoningEfforts(modelId)
          ?.where(
            (effort) =>
                effort != AiReasoningEffort.automatic &&
                effort != AiReasoningEffort.none,
          )
          .toList(growable: false);

  static bool allowsModel(String modelId) => reasoningEfforts(modelId) != null;

  static AiModelResolution resolve(AiApiConfig config) {
    final String modelId = config.model.trim();
    if (modelId.isEmpty) {
      return const AiModelResolution(issue: AiModelIssue.modelRequired);
    }
    final List<AiReasoningEffort>? efforts = reasoningEfforts(modelId);
    if (efforts == null) {
      return const AiModelResolution(issue: AiModelIssue.modelNotAllowed);
    }
    if (!efforts.contains(config.reasoningEffort)) {
      return const AiModelResolution(issue: AiModelIssue.unsupportedEffort);
    }
    return AiModelResolution(
      modelId: modelId,
      reasoningEffort: config.reasoningEffort.requestValue,
      serviceTier: config.responseSpeed.serviceTier,
    );
  }
}

/// Values accepted by a documented model. Automatic is a UI choice that
/// omits the API field, so it is intentionally absent from [apiEfforts].
class AiModelCapability {
  const AiModelCapability({
    required this.apiEfforts,
    required this.documentationUrl,
  });

  final List<AiReasoningEffort> apiEfforts;
  final String documentationUrl;
}

enum AiModelIssue { modelRequired, modelNotAllowed, unsupportedEffort }

/// The effective model controls shared by UI checks and request construction.
class AiModelResolution {
  const AiModelResolution({
    this.modelId,
    this.reasoningEffort,
    this.serviceTier,
    this.issue,
  });

  final String? modelId;
  final String? reasoningEffort;
  final String? serviceTier;
  final AiModelIssue? issue;

  bool get isUsable => issue == null;
}
