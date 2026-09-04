import 'dart:async';
import 'dart:io';

import 'package:app_ai_client/app_ai_client.dart';

import '../models/app_language.dart';

/// Converts unstable provider/client errors into short, actionable product copy.
class AiErrorPresentation {
  const AiErrorPresentation({required this.code, required this.message});

  final String code;
  final String message;

  static AiErrorPresentation from(
    Object error, {
    AppLanguage language = AppLanguage.zhHans,
  }) {
    final bool chinese = language == AppLanguage.zhHans;
    final String value = _flatten(error).toLowerCase();
    if (error is AiConfigurationException) {
      return AiErrorPresentation(
        code: 'configuration',
        message: chinese ? '接口配置不完整' : 'The API configuration is incomplete',
      );
    }
    if (error is AiProtocolException ||
        value.contains('invalid json') ||
        value.contains('parse') ||
        value.contains('protocol')) {
      return AiErrorPresentation(
        code: 'protocol_parse',
        message: chinese
            ? '服务返回格式无法解析'
            : 'The provider returned an unreadable response',
      );
    }
    if (_hasStatus(value, 401) ||
        _hasStatus(value, 403) ||
        value.contains('unauthorized') ||
        value.contains('forbidden') ||
        value.contains('invalid api key') ||
        value.contains('authentication')) {
      return AiErrorPresentation(
        code: 'authentication',
        message: chinese
            ? '鉴权失败，请检查 API 密钥'
            : 'Authentication failed; check the API key',
      );
    }
    if (_hasStatus(value, 404) ||
        value.contains('model not found') ||
        value.contains('unknown model') ||
        value.contains('does not exist')) {
      return AiErrorPresentation(
        code: 'model_unavailable',
        message: chinese
            ? '模型不可用，请检查模型名称'
            : 'The selected model is unavailable',
      );
    }
    if (_hasStatus(value, 429) ||
        value.contains('rate limit') ||
        value.contains('too many requests') ||
        value.contains('quota')) {
      return AiErrorPresentation(
        code: 'rate_limited',
        message: chinese
            ? '请求过于频繁，请稍后再试'
            : 'Too many requests; try again shortly',
      );
    }
    if (_hasStatus(value, 500) ||
        _hasStatus(value, 502) ||
        _hasStatus(value, 503) ||
        _hasStatus(value, 504) ||
        value.contains('service unavailable') ||
        value.contains('server error') ||
        value.contains('overloaded')) {
      return AiErrorPresentation(
        code: 'provider_unavailable',
        message: chinese
            ? '服务商暂时不可用'
            : 'The provider is temporarily unavailable',
      );
    }
    if (error is TimeoutException ||
        value.contains('timeout') ||
        value.contains('timed out') ||
        value.contains('deadline exceeded')) {
      return AiErrorPresentation(
        code: 'network_timeout',
        message: chinese ? '网络请求超时' : 'The network request timed out',
      );
    }
    if (error is SocketException ||
        error is AiTransportException ||
        value.contains('connection') ||
        value.contains('network') ||
        value.contains('socket') ||
        value.contains('dns')) {
      return AiErrorPresentation(
        code: 'network_offline',
        message: chinese ? '网络连接不可用' : 'The network connection is unavailable',
      );
    }
    return AiErrorPresentation(
      code: 'unknown',
      message: chinese ? '服务暂时不可用' : 'The service is temporarily unavailable',
    );
  }

  static String _flatten(Object error) {
    if (error is AiClientException && error.cause != null) {
      return '${error.message} ${error.cause}';
    }
    return '$error';
  }

  static bool _hasStatus(String value, int status) => RegExp(
    '(^|[^0-9])$status'
    r'([^0-9]|$)',
  ).hasMatch(value);
}
