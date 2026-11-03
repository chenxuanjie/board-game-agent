import 'dart:async';

import 'package:app_ai_client/app_ai_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:board_game_agent/core/localization/app_language.dart';
import 'package:board_game_agent/features/assistant/services/ai_error_presenter.dart';

void main() {
  test(
    'capacity and integrity failures keep actionable copy without raw details',
    () {
      for (final error in [
        'request_too_large',
        'HTTP 413',
        'AI request exceeds its size limit',
        'AI request exceeds the gateway size limit',
      ]) {
        expect(AiErrorPresentation.from(error).code, 'request_too_large');
      }
      expect(
        AiErrorPresentation.from('knowledge_integrity').message,
        contains('刷新资料库'),
      );
      expect(
        AiErrorPresentation.from(
          'knowledge_preparation_timeout',
          language: AppLanguage.en,
        ).code,
        'knowledge_preparation_timeout',
      );
    },
  );
  test('maps provider status codes to readable Chinese categories', () {
    final AiErrorPresentation authentication = AiErrorPresentation.from(
      const AiTransportException('HTTP 401: invalid api key'),
      language: AppLanguage.zhHans,
    );
    expect(authentication.code, 'authentication');
    expect(authentication.message, '鉴权失败，请检查 API 密钥');
    expect(
      AiErrorPresentation.from(
        const AiTransportException('HTTP 404: model not found'),
        language: AppLanguage.zhHans,
      ).code,
      'model_unavailable',
    );
    expect(
      AiErrorPresentation.from(
        const AiTransportException('HTTP 429: rate limit'),
        language: AppLanguage.zhHans,
      ).code,
      'rate_limited',
    );
  });

  test(
    'maps timeout and protocol failures without exposing exception text',
    () {
      expect(
        AiErrorPresentation.from(
          TimeoutException('raw provider details'),
          language: AppLanguage.zhHans,
        ).message,
        '网络请求超时',
      );
      expect(
        AiErrorPresentation.from(
          const AiProtocolException('raw json payload'),
          language: AppLanguage.zhHans,
        ).message,
        '服务返回格式无法解析',
      );
    },
  );
}
