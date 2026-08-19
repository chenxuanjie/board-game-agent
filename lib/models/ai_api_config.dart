import 'dart:convert';

enum AiProviderPreset { openAi, deepSeek, custom }

class AiApiConfig {
  const AiApiConfig({
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.apiKeyHeader,
    this.chatPath = '/chat/completions',
  });

  final String name;
  final String baseUrl;
  final String apiKey;
  final String model;
  final String apiKeyHeader;
  final String chatPath;

  static const AiApiConfig defaultOpenAi = AiApiConfig(
    name: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    apiKey: '',
    model: 'gpt-4o-mini',
    apiKeyHeader: 'Authorization',
    chatPath: '/chat/completions',
  );

  static const AiApiConfig defaultDeepSeek = AiApiConfig(
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com',
    apiKey: '',
    model: 'deepseek-chat',
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
  }) {
    return AiApiConfig(
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      apiKeyHeader: apiKeyHeader ?? this.apiKeyHeader,
      chatPath: chatPath ?? this.chatPath,
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
    };
  }

  String toJson() => jsonEncode(toMap());

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
      final String? storedApiKeyHeader = (json['apiKeyHeader'] as String?)
          ?.trim();
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
        apiKeyHeader:
            storedApiKeyHeader != null &&
                storedApiKeyHeader.isNotEmpty &&
                !hasRemovedMimoModel
            ? storedApiKeyHeader
            : providerTemplate.apiKeyHeader,
        chatPath: (json['chatPath'] as String?)?.trim().isNotEmpty == true
            ? json['chatPath'] as String
            : providerTemplate.chatPath,
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
