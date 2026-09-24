import 'dart:convert';

enum AiProviderPreset { openAi, deepSeek, custom }

/// How much deliberate reasoning the selected model should spend.
///
/// `automatic` deliberately omits the optional provider field so existing
/// OpenAI-compatible endpoints keep working, including providers that do not
/// implement reasoning controls.
enum AiReasoningEffort { automatic, low, medium, high }

extension AiReasoningEffortX on AiReasoningEffort {
  String get storageValue => name;

  String? get requestValue => switch (this) {
    AiReasoningEffort.automatic => null,
    AiReasoningEffort.low => 'low',
    AiReasoningEffort.medium => 'medium',
    AiReasoningEffort.high => 'high',
  };

  static AiReasoningEffort fromStored(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'low' => AiReasoningEffort.low,
      'medium' => AiReasoningEffort.medium,
      'high' => AiReasoningEffort.high,
      _ => AiReasoningEffort.automatic,
    };
  }
}

/// A provider service-tier hint exposed as a user-friendly response-speed
/// preference. It is only sent when the user explicitly chooses a non-default
/// value because compatible providers are free to ignore or reject it.
enum AiResponseSpeed { automatic, fast, standard }

extension AiResponseSpeedX on AiResponseSpeed {
  String get storageValue => name;

  String? get serviceTier => switch (this) {
    AiResponseSpeed.automatic => null,
    AiResponseSpeed.fast => 'fast',
    AiResponseSpeed.standard => 'default',
  };

  static AiResponseSpeed fromStored(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'fast' => AiResponseSpeed.fast,
      'standard' || 'default' => AiResponseSpeed.standard,
      _ => AiResponseSpeed.automatic,
    };
  }
}

class AiApiConfig {
  const AiApiConfig({
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.apiKeyHeader,
    this.chatPath = '/chat/completions',
    this.reasoningEffort = AiReasoningEffort.automatic,
    this.responseSpeed = AiResponseSpeed.automatic,
  });

  final String name;
  final String baseUrl;
  final String apiKey;
  final String model;
  final String apiKeyHeader;
  final String chatPath;
  final AiReasoningEffort reasoningEffort;
  final AiResponseSpeed responseSpeed;

  /// A stable comparison key used for custom supplier presets.
  ///
  /// Supplier names are the user-facing identity of a saved custom preset;
  /// casing and surrounding whitespace must not create duplicate entries.
  String get normalizedName => name.trim().toLowerCase();

  static const AiApiConfig defaultOpenAi = AiApiConfig(
    name: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    apiKey: '',
    model: '',
    apiKeyHeader: 'Authorization',
    chatPath: '/chat/completions',
  );

  static const AiApiConfig defaultDeepSeek = AiApiConfig(
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com',
    apiKey: '',
    model: '',
    apiKeyHeader: 'Authorization',
    chatPath: '/chat/completions',
  );

  static const AiApiConfig defaultCustom = AiApiConfig(
    name: 'Custom OpenAI-compatible',
    baseUrl: '',
    apiKey: '',
    model: '',
    apiKeyHeader: 'Authorization',
    chatPath: '/chat/completions',
  );

  AiApiConfig copyWith({
    String? name,
    String? baseUrl,
    String? apiKey,
    String? model,
    String? apiKeyHeader,
    String? chatPath,
    AiReasoningEffort? reasoningEffort,
    AiResponseSpeed? responseSpeed,
  }) {
    return AiApiConfig(
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      apiKeyHeader: apiKeyHeader ?? this.apiKeyHeader,
      chatPath: chatPath ?? this.chatPath,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      responseSpeed: responseSpeed ?? this.responseSpeed,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'name': name,
      'baseUrl': baseUrl,
      'apiKey': apiKey,
      'model': model,
      'apiKeyHeader': apiKeyHeader,
      'chatPath': chatPath,
      'reasoningEffort': reasoningEffort.storageValue,
      'responseSpeed': responseSpeed.storageValue,
    };
  }

  String toJson() => jsonEncode(toMap());

  static List<AiApiConfig> decodeList(String? source) {
    if (source == null || source.trim().isEmpty) {
      return const <AiApiConfig>[];
    }

    try {
      final Object? decoded = jsonDecode(source);
      if (decoded is! List<Object?>) {
        return const <AiApiConfig>[];
      }
      final Set<String> seenNames = <String>{};
      final List<AiApiConfig> result = <AiApiConfig>[];
      for (final Object? item in decoded) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final AiApiConfig config = AiApiConfig.fromJson(jsonEncode(item));
        if (config.providerPreset != AiProviderPreset.custom ||
            config.normalizedName.isEmpty ||
            !seenNames.add(config.normalizedName)) {
          continue;
        }
        result.add(config);
      }
      return List<AiApiConfig>.unmodifiable(result);
    } catch (_) {
      return const <AiApiConfig>[];
    }
  }

  static String encodeList(Iterable<AiApiConfig> configs) {
    return jsonEncode(
      configs
          .map((AiApiConfig config) => config.toMap())
          .toList(growable: false),
    );
  }

  static bool isBuiltInProviderName(String value) {
    final String normalized = value.trim().toLowerCase();
    return normalized == defaultOpenAi.name.toLowerCase() ||
        normalized == defaultDeepSeek.name.toLowerCase() ||
        normalized == defaultCustom.name.toLowerCase();
  }

  AiProviderPreset get providerPreset => detectAiProviderPreset(this);

  static AiApiConfig fromJson(String? source) {
    if (source == null || source.trim().isEmpty) {
      return defaultOpenAi;
    }

    try {
      final Map<String, dynamic> json =
          jsonDecode(source) as Map<String, dynamic>;
      final String baseUrl =
          (json['baseUrl'] as String?)?.trim().isNotEmpty == true
          ? json['baseUrl'] as String
          : defaultOpenAi.baseUrl;
      if (_isRemovedMimoBaseUrl(baseUrl)) {
        return defaultOpenAi;
      }
      final AiApiConfig providerTemplate = detectAiProviderPreset(
        AiApiConfig(
          name: defaultOpenAi.name,
          baseUrl: baseUrl,
          apiKey: '',
          model: defaultOpenAi.model,
          apiKeyHeader: defaultOpenAi.apiKeyHeader,
        ),
      ).template;
      final String? storedModel = (json['model'] as String?)?.trim();
      final bool hasRemovedMimoModel = _isRemovedMimoModel(storedModel);
      return AiApiConfig(
        name: (json['name'] as String?)?.trim().isNotEmpty == true
            ? json['name'] as String
            : providerTemplate.name,
        baseUrl: baseUrl,
        apiKey: (json['apiKey'] as String?) ?? defaultOpenAi.apiKey,
        model:
            storedModel != null &&
                storedModel.isNotEmpty &&
                !hasRemovedMimoModel
            ? storedModel
            : providerTemplate.model,
        apiKeyHeader: providerTemplate.apiKeyHeader,
        chatPath: providerTemplate.chatPath,
        reasoningEffort: AiReasoningEffortX.fromStored(
          json['reasoningEffort'] as String?,
        ),
        responseSpeed: AiResponseSpeedX.fromStored(
          json['responseSpeed'] as String? ?? json['serviceTier'] as String?,
        ),
      );
    } catch (_) {
      return defaultOpenAi;
    }
  }
}

extension AiProviderPresetX on AiProviderPreset {
  AiApiConfig get template {
    switch (this) {
      case AiProviderPreset.openAi:
        return AiApiConfig.defaultOpenAi;
      case AiProviderPreset.deepSeek:
        return AiApiConfig.defaultDeepSeek;
      case AiProviderPreset.custom:
        return AiApiConfig.defaultCustom;
    }
  }
}

bool _isRemovedMimoBaseUrl(String value) {
  final String normalized = value.trim().toLowerCase();
  return normalized.contains('xiaomimimo.com');
}

bool _isRemovedMimoModel(String? value) {
  return value?.trim().toLowerCase().startsWith('mimo-') == true;
}

AiProviderPreset detectAiProviderPreset(AiApiConfig config) {
  final String baseUrl = config.baseUrl.trim().toLowerCase();
  if (baseUrl.contains('api.openai.com')) {
    return AiProviderPreset.openAi;
  }
  if (baseUrl.contains('api.deepseek.com')) {
    return AiProviderPreset.deepSeek;
  }
  return AiProviderPreset.custom;
}
