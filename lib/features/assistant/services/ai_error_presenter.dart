import 'dart:async';
import 'dart:io';

import 'package:app_ai_client/app_ai_client.dart';

import '../../../core/localization/app_language.dart';

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
    if (value.contains('knowledge_integrity')) {
      return AiErrorPresentation(
        code: 'knowledge_integrity',
        message: chinese
            ? '资料已更新或校验失败，请刷新资料库后重试'
            : 'The published file changed or failed verification. Refresh the library and retry',
      );
    }
    if (value.contains('knowledge_unavailable')) {
      return AiErrorPresentation(
        code: 'knowledge_unavailable',
        message: chinese
            ? '当前发布的资料正文暂不可用，请刷新资料库后重试'
            : 'The published file is unavailable. Refresh the library and retry',
      );
    }
    if (value.contains('knowledge_preparation_timeout')) {
      return AiErrorPresentation(
        code: 'knowledge_preparation_timeout',
        message: chinese
            ? '资料准备超时，请稍后重试'
            : 'Preparing the published files timed out. Please retry',
      );
    }
    if (value.contains('request_too_large') ||
        _hasStatus(value, 413) ||
        value.contains('request exceeds') && value.contains('size limit')) {
      return AiErrorPresentation(
        code: 'request_too_large',
        message: chinese
            ? '资料和对话超出本次请求容量，请减少资料或新建对话'
            : 'The files and conversation exceed this request limit. Use fewer files or start a new conversation',
      );
    }
    if (value.contains('请先登录后使用 loomex') || value.contains('请先登录后使用loomex')) {
      return AiErrorPresentation(
        code: 'account_required',
        message: chinese
            ? '请登录后使用 Loomex，或选择自定义模型服务'
            : 'Sign in to use Loomex, or choose a custom model service',
      );
    }
    if (value.contains('loomex_session_expired') ||
        (value.contains('/ai/loomex/') ||
                value.contains('loomex.account.invalid')) &&
            (_hasStatus(value, 401) || _hasStatus(value, 403))) {
      return AiErrorPresentation(
        code: 'account_expired',
        message: chinese
            ? '登录已过期，请重新登录'
            : 'Your session expired; sign in again',
      );
    }
    final bool authenticationCode =
        value.contains('invalid_api_key') ||
        value.contains('invalid api key') ||
        value.contains('authentication_error') ||
        value.contains('unauthorized');
    final bool modelCode =
        value.contains('model_not_found') ||
        value.contains('model_unavailable');
    final bool rateLimitCode =
        value.contains('rate_limit') || value.contains('rate limited');
    final bool timeoutCode =
        value.contains('timeout') || value.contains('timed_out');
    final bool serverCode =
        value.contains('server_error') || value.contains('internal_error');
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
    if (authenticationCode ||
        _hasStatus(value, 401) ||
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
    if (modelCode ||
        _hasStatus(value, 404) ||
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
    if (rateLimitCode ||
        _hasStatus(value, 429) ||
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
    if (serverCode ||
        _hasStatus(value, 500) ||
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
    if (timeoutCode ||
        _hasStatus(value, 408) ||
        _hasStatus(value, 425) ||
        error is TimeoutException ||
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
