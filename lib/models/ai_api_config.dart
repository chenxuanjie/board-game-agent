import 'dart:convert';

class AiApiConfig {
  const AiApiConfig({
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    this.model = 'mimo-v2.5-pro',
    this.apiKeyHeader = 'api-key',
    this.chatPath = '/chat/completions',
  });

  final String name;
  final String baseUrl;
  final String apiKey;
  final String model;
  final String apiKeyHeader;
  final String chatPath;

  static const AiApiConfig defaultMimo = AiApiConfig(
    name: 'MiMo',
    baseUrl: 'https://token-plan-cn.xiaomimimo.com/v1',
    apiKey: 'tp-cqrdq1go3g16pd4nhg05vd91dmh36vp0eq49i41qjmb4rdlb',
    model: 'mimo-v2.5-pro',
    apiKeyHeader: 'api-key',
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

  static AiApiConfig fromJson(String? source) {
    if (source == null || source.trim().isEmpty) {
      return defaultMimo;
    }

    try {
      final Map<String, dynamic> json =
          jsonDecode(source) as Map<String, dynamic>;
      return AiApiConfig(
        name: (json['name'] as String?)?.trim().isNotEmpty == true
            ? json['name'] as String
            : defaultMimo.name,
        baseUrl: (json['baseUrl'] as String?)?.trim().isNotEmpty == true
            ? json['baseUrl'] as String
            : defaultMimo.baseUrl,
        apiKey: (json['apiKey'] as String?) ?? defaultMimo.apiKey,
        model: (json['model'] as String?)?.trim().isNotEmpty == true
            ? json['model'] as String
            : defaultMimo.model,
        apiKeyHeader:
            (json['apiKeyHeader'] as String?)?.trim().isNotEmpty == true
            ? json['apiKeyHeader'] as String
            : defaultMimo.apiKeyHeader,
        chatPath: (json['chatPath'] as String?)?.trim().isNotEmpty == true
            ? json['chatPath'] as String
            : defaultMimo.chatPath,
      );
    } catch (_) {
      return defaultMimo;
    }
  }
}
