import '../../assistant/models/ai_api_config.dart';
import '../../../core/models/connectivity_status.dart';
import '../../../app/state/app_controller.dart';
import '../../../core/localization/app_copy.dart';

class DesktopAiSettingsDraft {
  const DesktopAiSettingsDraft({
    required this.provider,
    required this.model,
    required this.apiKey,
    required this.baseUrl,
  });

  final String provider;
  final String model;
  final String apiKey;
  final String baseUrl;

  AiApiConfig mergeWith(AiApiConfig current) => current.copyWith(
    name: provider.trim(),
    model: model.trim(),
    apiKey: apiKey.trim(),
    baseUrl: baseUrl.trim(),
  );
}

class DesktopAiSettingsResult {
  const DesktopAiSettingsResult({
    required this.config,
    required this.connected,
    required this.succeeded,
    required this.message,
    required this.modelCount,
  });

  final AiApiConfig config;
  final bool connected;
  final bool succeeded;
  final String message;
  final int modelCount;
}

/// Desktop-specific orchestration for the compact AI settings card.
///
/// The mobile settings sheet and the desktop card intentionally keep separate
/// presentation flows. Both call the same [AppController] API boundary, so
/// persistence, model discovery, connectivity state, and active-run isolation
/// remain consistent across platforms.
class DesktopAiSettingsService {
  const DesktopAiSettingsService(this.controller);

  final AppController controller;

  Future<DesktopAiSettingsResult> saveAndCheck(
    DesktopAiSettingsDraft draft,
  ) async {
    final AppCopy copy = controller.copy;
    final String provider = draft.provider.trim();
    final String baseUrl = draft.baseUrl.trim();
    final String apiKey = draft.apiKey.trim();

    if (provider.isEmpty) {
      throw DesktopAiSettingsException(
        copy.localized('请输入供应商名称。', 'Enter a provider name.'),
      );
    }
    final Uri? endpoint = Uri.tryParse(baseUrl);
    if (endpoint == null ||
        !endpoint.hasScheme ||
        !endpoint.hasAuthority ||
        (endpoint.scheme != 'http' && endpoint.scheme != 'https')) {
      throw DesktopAiSettingsException(
        copy.localized(
          '请输入有效的 HTTP 或 HTTPS 接口地址。',
          'Enter a valid HTTP or HTTPS base URL.',
        ),
      );
    }
    if (apiKey.isEmpty) {
      throw DesktopAiSettingsException(
        copy.localized('请输入 API Key。', 'Enter an API key.'),
      );
    }

    final AiApiConfig config = draft.mergeWith(controller.aiApiConfig);
    await controller.saveAiApiConfig(config);
    await controller.refreshAiServiceStatus();

    final bool connected =
        controller.aiConnectivityStatus.state == ConnectivityState.success;
    final bool succeeded =
        connected ||
        controller.aiConnectivityStatus.state == ConnectivityState.warning;
    final int modelCount = controller.availableAiModels.length;
    final String message;
    if (connected) {
      message = copy.localized(
        '配置已保存，连接正常，已获取 $modelCount 个模型。',
        'Saved and connected. $modelCount models found.',
      );
    } else if (controller.aiConnectivityStatus.state ==
            ConnectivityState.warning &&
        modelCount > 0) {
      message = copy.localized(
        '配置已保存，已从 /models 获取 $modelCount 个模型，请选择模型。',
        'Saved. $modelCount models loaded from /models; select a model.',
      );
    } else {
      message = controller.aiConnectivityStatus.message;
    }

    return DesktopAiSettingsResult(
      config: controller.aiApiConfig,
      connected: connected,
      succeeded: succeeded,
      message: message,
      modelCount: modelCount,
    );
  }
}

class DesktopAiSettingsException implements Exception {
  const DesktopAiSettingsException(this.message);

  final String message;

  @override
  String toString() => message;
}
