import 'dart:async';

import 'package:app_ai_client/app_ai_client.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:webdav_settings/webdav_settings.dart';

import '../../models/ai_api_config.dart';
import '../../models/app_language.dart';
import '../../models/asset_source_config.dart';
import '../../models/color_scheme_option.dart';
import '../../models/connectivity_status.dart';
import '../../services/desktop_ai_settings_service.dart';
import '../../services/board_game_remote_layout.dart';
import '../../state/app_controller.dart';
import '../../theme/app_palette.dart';
import '../../theme/palette_registry.dart';
import '../app_copy.dart';
import 'desktop_responsive.dart';
import 'theme.dart';

class DesktopSettingsPane extends StatefulWidget {
  const DesktopSettingsPane({
    super.key,
    required this.controller,
    required this.onOpenAbout,
    this.webDavSettingsController,
  });

  final AppController controller;
  final VoidCallback onOpenAbout;
  final WebDavSettingsController? webDavSettingsController;

  @override
  State<DesktopSettingsPane> createState() => _DesktopSettingsPaneState();
}

class _DesktopSettingsPaneState extends State<DesktopSettingsPane> {
  late final Future<String> _version = _loadVersion();
  late final DesktopAiSettingsService _desktopAiSettings;
  late final TextEditingController _aiProvider;
  late final TextEditingController _aiModel;
  late final TextEditingController _aiApiKey;
  late final TextEditingController _aiBaseUrl;
  late final TextEditingController _webDavUrl;
  late final TextEditingController _webDavUsername;
  late final TextEditingController _webDavPassword;
  late String _aiProviderOptionId;
  bool _saving = false;
  bool _savingAi = false;
  bool _checkingSources = false;
  bool _showWebDavPassword = false;
  String? _webDavFeedback;
  bool? _webDavFeedbackSucceeded;
  bool _showApiKey = false;
  String? _failure;
  String? _aiFeedback;
  bool? _aiFeedbackSucceeded;

  @override
  void initState() {
    super.initState();
    _desktopAiSettings = DesktopAiSettingsService(widget.controller);
    final AiApiConfig config = widget.controller.aiApiConfig;
    _aiProvider = TextEditingController(text: config.name);
    _aiModel = TextEditingController(text: config.model);
    _aiApiKey = TextEditingController(text: config.apiKey);
    _aiBaseUrl = TextEditingController(text: config.baseUrl);
    final WebDavSettings webDav =
        widget.webDavSettingsController?.draft ?? const WebDavSettings();
    _webDavUrl = TextEditingController(text: webDav.baseUrl);
    _webDavUsername = TextEditingController(text: webDav.username);
    _webDavPassword = TextEditingController(text: webDav.password);
    _aiProviderOptionId = _providerOptionId(config);
  }

  @override
  void dispose() {
    _aiProvider.dispose();
    _aiModel.dispose();
    _aiApiKey.dispose();
    _aiBaseUrl.dispose();
    _webDavUrl.dispose();
    _webDavUsername.dispose();
    _webDavPassword.dispose();
    super.dispose();
  }

  Future<String> _loadVersion() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      final String build = info.buildNumber.trim();
      return build.isEmpty ? info.version : '${info.version} ($build)';
    } catch (_) {
      return widget.controller.copy.localized('暂不可读取', 'Unavailable');
    }
  }

  Future<void> _save(Future<void> Function() operation) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failure = null;
    });
    try {
      await operation();
    } catch (_) {
      if (mounted) {
        setState(
          () => _failure = widget.controller.copy.localized(
            '设置未能保存，请重试。',
            'Could not save the setting. Please try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _checkResourceSources() async {
    if (_checkingSources) return;
    setState(() {
      _checkingSources = true;
      _failure = null;
    });
    try {
      await widget.controller.refreshAssetAccessStatus();
    } catch (_) {
      if (mounted) {
        setState(
          () => _failure = widget.controller.copy.localized(
            '资料源检测失败，请稍后重试。',
            'Could not check resource sources. Please try again later.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _checkingSources = false);
    }
  }

  Future<void> _saveAndCheckWebDav() async {
    final WebDavSettingsController? settingsController =
        widget.webDavSettingsController;
    if (_checkingSources || settingsController == null) return;
    setState(() {
      _checkingSources = true;
      _failure = null;
      _webDavFeedback = null;
      _webDavFeedbackSucceeded = null;
    });
    try {
      final WebDavSettings draft = BoardGameRemoteLayout.normalizeSettings(
        WebDavSettings(
          mode: ExternalStorageMode.webDav,
          baseUrl: _webDavUrl.text.trim(),
          username: _webDavUsername.text.trim(),
          password: _webDavPassword.text,
        ),
      );
      settingsController.updateDraft(draft);
      final WebDavConnectionTestResult testResult = await settingsController
          .testConnection();
      if (!testResult.isSuccess) {
        if (!mounted) return;
        setState(() {
          _webDavFeedback = testResult.message;
          _webDavFeedbackSucceeded = false;
        });
        return;
      }
      final WebDavSettings saved = await settingsController.enableWebDav();
      final AssetSourceConfig source = AssetSourceConfig.normalize(
        AssetSourceConfig(
          id: 'configured_webdav',
          name: 'WebDAV',
          address: saved.baseUrl,
          testUrl: saved.baseUrl,
        ),
      );
      await widget.controller.saveAssetSourceConfigs(<AssetSourceConfig>[
        source,
      ]);
      if (!mounted) return;
      _webDavUrl.text = saved.baseUrl;
      setState(() {
        _webDavFeedback = widget.controller.copy.localized(
          '连接成功，WebDAV 地址已保存。',
          'Connected. The WebDAV address has been saved.',
        );
        _webDavFeedbackSucceeded = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _webDavFeedback = widget.controller.copy.localized(
          'WebDAV 配置保存失败：$error',
          'Could not save the WebDAV configuration: $error',
        );
        _webDavFeedbackSucceeded = false;
      });
    } finally {
      if (mounted) setState(() => _checkingSources = false);
    }
  }

  Future<void> _saveAndCheckAi() async {
    if (_savingAi) return;
    setState(() {
      _savingAi = true;
      _aiFeedback = null;
      _aiFeedbackSucceeded = null;
    });
    try {
      final DesktopAiSettingsResult result = await _desktopAiSettings
          .saveAndCheck(
            DesktopAiSettingsDraft(
              provider: _aiProvider.text,
              model: _aiModel.text,
              apiKey: _aiApiKey.text,
              baseUrl: _aiBaseUrl.text,
            ),
          );
      if (!mounted) return;
      _aiModel.text = result.config.model;
      setState(() {
        _aiProviderOptionId = _providerOptionId(result.config);
        _aiFeedback = result.message;
        _aiFeedbackSucceeded = result.succeeded;
      });
    } on DesktopAiSettingsException catch (error) {
      if (!mounted) return;
      setState(() {
        _aiFeedback = error.message;
        _aiFeedbackSucceeded = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _aiFeedback = widget.controller.copy.localized(
          'AI 配置未能保存，请重试。',
          'Could not save the AI configuration. Please try again.',
        );
        _aiFeedbackSucceeded = false;
      });
    } finally {
      if (mounted) setState(() => _savingAi = false);
    }
  }

  String _providerOptionId(AiApiConfig config) =>
      switch (config.providerPreset) {
        AiProviderPreset.openAi => 'builtin:openai',
        AiProviderPreset.deepSeek => 'builtin:deepseek',
        AiProviderPreset.custom =>
          config.normalizedName.isEmpty
              ? 'custom:new'
              : 'custom:${config.normalizedName}',
      };

  List<_DesktopAiProviderOption> _providerOptions() {
    final AppCopy copy = widget.controller.copy;
    final List<AiApiConfig> custom = <AiApiConfig>[
      ...widget.controller.customAiPresets,
    ];
    final AiApiConfig current = widget.controller.aiApiConfig;
    if (current.providerPreset == AiProviderPreset.custom &&
        current.normalizedName.isNotEmpty &&
        custom.every(
          (AiApiConfig item) => item.normalizedName != current.normalizedName,
        )) {
      custom.insert(0, current);
    }
    return <_DesktopAiProviderOption>[
      _DesktopAiProviderOption(
        id: 'builtin:openai',
        label: copy.aiProviderPresetName(AiProviderPreset.openAi),
        config: AiApiConfig.defaultOpenAi,
      ),
      _DesktopAiProviderOption(
        id: 'builtin:deepseek',
        label: copy.aiProviderPresetName(AiProviderPreset.deepSeek),
        config: AiApiConfig.defaultDeepSeek,
      ),
      ...custom
          .where(
            (AiApiConfig config) =>
                !AiApiConfig.isBuiltInProviderName(config.name),
          )
          .map(
            (AiApiConfig config) => _DesktopAiProviderOption(
              id: 'custom:${config.normalizedName}',
              label: config.name,
              config: config,
            ),
          ),
      _DesktopAiProviderOption(
        id: 'custom:new',
        label: copy.aiProviderPresetName(AiProviderPreset.custom),
        config: AiApiConfig.defaultCustom,
        isNewCustom: true,
      ),
    ];
  }

  void _selectAiProvider(String? id) {
    if (id == null || id == _aiProviderOptionId) return;
    final _DesktopAiProviderOption option = _providerOptions().firstWhere(
      (_DesktopAiProviderOption item) => item.id == id,
    );
    setState(() {
      _aiProviderOptionId = option.id;
      _aiProvider.text = option.isNewCustom ? '' : option.config.name;
      _aiModel.text = option.config.model;
      _aiApiKey.text = option.isNewCustom ? '' : option.config.apiKey;
      _aiBaseUrl.text = option.isNewCustom ? '' : option.config.baseUrl;
      _aiFeedback = null;
      _aiFeedbackSucceeded = null;
    });
    widget.controller.invalidateAiModels();
  }

  void _invalidateAiDiscovery(String _) {
    widget.controller.invalidateAiModels();
    if (_aiModel.text.isNotEmpty) {
      _aiModel.clear();
    }
    if (_aiFeedback != null || _aiFeedbackSucceeded != null) {
      setState(() {
        _aiFeedback = null;
        _aiFeedbackSucceeded = null;
      });
    }
  }

  void _selectAiModel(String? model) {
    setState(() {
      _aiModel.text = model ?? '';
      _aiFeedback = null;
      _aiFeedbackSucceeded = null;
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final DesktopMetrics metrics = DesktopMetricsScope.of(context);
      final List<Widget> cards = <Widget>[
        _GeneralCard(
          controller: widget.controller,
          saving: _saving,
          onLanguage: (AppLanguage language) =>
              unawaited(_save(() => widget.controller.setLanguage(language))),
          onStartupUpdates: (bool enabled) => unawaited(
            _save(() => widget.controller.setCheckForUpdates(enabled)),
          ),
          onVoiceReply: (bool enabled) => unawaited(
            _save(() => widget.controller.setVoiceReplyEnabled(enabled)),
          ),
        ),
        _AiServiceCard(
          controller: widget.controller,
          providerOptions: _providerOptions(),
          selectedProviderId: _aiProviderOptionId,
          providerController: _aiProvider,
          modelController: _aiModel,
          apiKeyController: _aiApiKey,
          baseUrlController: _aiBaseUrl,
          showApiKey: _showApiKey,
          saving: _savingAi,
          feedback: _aiFeedback,
          feedbackSucceeded: _aiFeedbackSucceeded,
          onProviderChanged: _selectAiProvider,
          onAiFieldChanged: _invalidateAiDiscovery,
          onModelChanged: _selectAiModel,
          onToggleApiKey: () => setState(() => _showApiKey = !_showApiKey),
          onSaveAndCheck: () => unawaited(_saveAndCheckAi()),
        ),
        _AppearanceCard(
          controller: widget.controller,
          saving: _saving,
          onSelectTheme: (ColorSchemeOption scheme) =>
              unawaited(_save(() => widget.controller.setColorScheme(scheme))),
        ),
        _NotificationsCard(copy: widget.controller.copy),
        _SyncBackupCard(
          controller: widget.controller,
          settingsController: widget.webDavSettingsController,
          urlController: _webDavUrl,
          usernameController: _webDavUsername,
          passwordController: _webDavPassword,
          checking: _checkingSources,
          showPassword: _showWebDavPassword,
          feedback: _webDavFeedback,
          feedbackSucceeded: _webDavFeedbackSucceeded,
          onTogglePassword: () =>
              setState(() => _showWebDavPassword = !_showWebDavPassword),
          onSaveAndCheck: widget.webDavSettingsController == null
              ? _checkResourceSources
              : _saveAndCheckWebDav,
        ),
        _AboutUpdatesCard(
          controller: widget.controller,
          version: _version,
          onOpenAbout: widget.onOpenAbout,
        ),
      ];

      return Padding(
        padding: metrics.insets(const EdgeInsets.only(top: 12, bottom: 16)),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final int columns = DesktopResponsive.settingsColumnsFor(
              constraints.maxWidth,
            );
            final double gap = metrics.px(16);
            final List<Widget> rows = <Widget>[];
            for (int start = 0; start < cards.length; start += columns) {
              final int end = (start + columns).clamp(0, cards.length);
              rows.add(
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (int index = start; index < end; index++) ...<Widget>[
                        if (index > start) SizedBox(width: gap),
                        Expanded(child: cards[index]),
                      ],
                    ],
                  ),
                ),
              );
              if (end < cards.length) rows.add(SizedBox(height: gap));
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            widget.controller.copy.localized('设置', 'Settings'),
                            style: TextStyle(
                              fontSize: metrics.font(28),
                              height: 1.1,
                              fontWeight: FontWeight.w700,
                              color: DesktopColors.text,
                            ),
                          ),
                          SizedBox(height: metrics.px(5)),
                          Text(
                            widget.controller.copy.localized(
                              '应用偏好与服务',
                              'App preferences and services',
                            ),
                            style: TextStyle(
                              fontSize: metrics.font(13),
                              color: DesktopColors.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_saving)
                      SizedBox(
                        width: metrics.px(20),
                        height: metrics.px(20),
                        child: CircularProgressIndicator(
                          strokeWidth: metrics.px(2),
                          color: DesktopColors.orange,
                        ),
                      ),
                  ],
                ),
                SizedBox(height: metrics.px(16)),
                ...rows,
                if (_failure != null) ...<Widget>[
                  SizedBox(height: metrics.px(10)),
                  Text(
                    _failure!,
                    style: TextStyle(
                      fontSize: metrics.font(12),
                      color: const Color(0xFF9F4D5D),
                    ),
                  ),
                ],
                SizedBox(height: metrics.px(14)),
                Row(
                  children: <Widget>[
                    OutlinedButton.icon(
                      key: const ValueKey<String>(
                        'desktop-settings-restore-defaults',
                      ),
                      onPressed: null,
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: Text(
                        widget.controller.copy.localized(
                          '恢复默认设置',
                          'Restore defaults',
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: Size(0, metrics.px(40)),
                        padding: EdgeInsets.symmetric(
                          horizontal: metrics.px(14),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            metrics.radius(9),
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      widget.controller.copy.localized(
                        '大多数设置会自动保存',
                        'Most settings save automatically',
                      ),
                      style: TextStyle(
                        fontSize: metrics.font(12),
                        color: DesktopColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );
    },
  );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final DesktopMetrics metrics = DesktopMetricsScope.of(context);
    return Container(
      key: ValueKey<String>('desktop-settings-card-$title'),
      padding: EdgeInsets.all(metrics.px(17)),
      decoration: BoxDecoration(
        color: DesktopColors.card,
        borderRadius: BorderRadius.circular(metrics.radius(13)),
        border: Border.all(color: const Color(0x1AA76D48)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0x0A704728),
            blurRadius: metrics.px(12),
            offset: Offset(0, metrics.px(3)),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: DesktopColors.orange, size: metrics.px(23)),
              SizedBox(width: metrics.px(9)),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: metrics.font(16),
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    color: DesktopColors.text,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: metrics.px(13)),
          child,
        ],
      ),
    );
  }
}

class _GeneralCard extends StatelessWidget {
  const _GeneralCard({
    required this.controller,
    required this.saving,
    required this.onLanguage,
    required this.onStartupUpdates,
    required this.onVoiceReply,
  });

  final AppController controller;
  final bool saving;
  final ValueChanged<AppLanguage> onLanguage;
  final ValueChanged<bool> onStartupUpdates;
  final ValueChanged<bool> onVoiceReply;

  @override
  Widget build(BuildContext context) {
    final AppCopy copy = controller.copy;
    return _SettingsCard(
      icon: Icons.tune_rounded,
      title: copy.localized('通用', 'General'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _FieldLabel(label: copy.localized('语言', 'Language')),
          SizedBox(height: _px(context, 5)),
          SizedBox(
            height: _px(context, 42),
            child: DropdownButtonFormField<AppLanguage>(
              key: const ValueKey<String>('desktop-settings-language'),
              initialValue: controller.language,
              isExpanded: true,
              decoration: _fieldDecoration(context),
              style: TextStyle(
                fontSize: _font(context, 13),
                color: DesktopColors.text,
              ),
              items: AppLanguage.values
                  .map(
                    (AppLanguage language) => DropdownMenuItem<AppLanguage>(
                      value: language,
                      child: Text(language.label),
                    ),
                  )
                  .toList(growable: false),
              onChanged: saving
                  ? null
                  : (value) {
                      if (value != null) onLanguage(value);
                    },
            ),
          ),
          SizedBox(height: _px(context, 7)),
          _SettingSwitchRow(
            key: const ValueKey<String>(
              'desktop-settings-startup-update-check',
            ),
            title: copy.localized('启动时检查更新', 'Check for updates on startup'),
            subtitle: copy.localized(
              '当前更新源仅支持 Android APK',
              'The current update source supports Android APK only',
            ),
            value: controller.checkForUpdates,
            onChanged: saving ? null : onStartupUpdates,
          ),
          SizedBox(height: _px(context, 4)),
          _SettingSwitchRow(
            key: const ValueKey<String>('desktop-settings-voice-reply'),
            title: copy.localized('语音朗读', 'Voice output'),
            subtitle: controller.voiceReplyAvailable
                ? copy.localized('可按设备能力启用', 'Available on this device')
                : copy.localized('当前设备不可用', 'Unavailable on this device'),
            value: controller.voiceReplyEnabled,
            onChanged: !saving && controller.voiceReplyAvailable
                ? onVoiceReply
                : null,
          ),
        ],
      ),
    );
  }
}

class _AiServiceCard extends StatelessWidget {
  const _AiServiceCard({
    required this.controller,
    required this.providerOptions,
    required this.selectedProviderId,
    required this.providerController,
    required this.modelController,
    required this.apiKeyController,
    required this.baseUrlController,
    required this.showApiKey,
    required this.saving,
    required this.feedback,
    required this.feedbackSucceeded,
    required this.onProviderChanged,
    required this.onAiFieldChanged,
    required this.onModelChanged,
    required this.onToggleApiKey,
    required this.onSaveAndCheck,
  });

  final AppController controller;
  final List<_DesktopAiProviderOption> providerOptions;
  final String selectedProviderId;
  final TextEditingController providerController;
  final TextEditingController modelController;
  final TextEditingController apiKeyController;
  final TextEditingController baseUrlController;
  final bool showApiKey;
  final bool saving;
  final String? feedback;
  final bool? feedbackSucceeded;
  final ValueChanged<String?> onProviderChanged;
  final ValueChanged<String> onAiFieldChanged;
  final ValueChanged<String?> onModelChanged;
  final VoidCallback onToggleApiKey;
  final VoidCallback onSaveAndCheck;

  @override
  Widget build(BuildContext context) {
    final AppCopy copy = controller.copy;
    final bool hasKey = apiKeyController.text.trim().isNotEmpty;

    return _SettingsCard(
      icon: Icons.auto_awesome_rounded,
      title: copy.localized('AI 服务', 'AI Service'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _AiProviderDropdownField(
                  fieldKey: const ValueKey<String>(
                    'desktop-settings-ai-provider',
                  ),
                  label: copy.localized('供应商', 'Provider'),
                  options: providerOptions,
                  selectedId: selectedProviderId,
                  enabled: !saving,
                  onChanged: onProviderChanged,
                ),
              ),
              SizedBox(width: _px(context, 9)),
              Expanded(
                child: _AiModelDropdownField(
                  fieldKey: const ValueKey<String>('desktop-settings-ai-model'),
                  label: copy.localized('模型', 'Model'),
                  models: controller.availableAiModels,
                  selectedModel: modelController.text,
                  loadState: controller.aiModelLoadState,
                  enabled: !saving,
                  copy: copy,
                  onChanged: onModelChanged,
                ),
              ),
            ],
          ),
          if (selectedProviderId == 'custom:new') ...<Widget>[
            SizedBox(height: _px(context, 8)),
            _EditableValueField(
              fieldKey: const ValueKey<String>(
                'desktop-settings-ai-custom-provider',
              ),
              label: copy.aiApiProviderNameLabel,
              controller: providerController,
              enabled: !saving,
              onChanged: onAiFieldChanged,
            ),
          ],
          SizedBox(height: _px(context, 8)),
          _EditableValueField(
            fieldKey: const ValueKey<String>('desktop-settings-ai-api-key'),
            label: 'API Key',
            controller: apiKeyController,
            enabled: !saving,
            obscureText: !showApiKey,
            onChanged: onAiFieldChanged,
            trailing: IconButton(
              tooltip: showApiKey
                  ? copy.localized('隐藏 API Key', 'Hide API Key')
                  : copy.localized('显示 API Key', 'Show API Key'),
              onPressed: saving ? null : onToggleApiKey,
              icon: Icon(
                showApiKey
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: _px(context, 18),
              ),
              visualDensity: VisualDensity.compact,
            ),
          ),
          SizedBox(height: _px(context, 8)),
          _EditableValueField(
            fieldKey: const ValueKey<String>('desktop-settings-ai-base-url'),
            label: copy.localized('接口地址', 'Base URL'),
            controller: baseUrlController,
            enabled: !saving,
            onChanged: onAiFieldChanged,
          ),
          SizedBox(height: _px(context, 10)),
          _AiStatusLabel(
            status: controller.aiConnectivityStatus,
            hasKey: hasKey,
            copy: copy,
          ),
          SizedBox(height: _px(context, 8)),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const ValueKey<String>('desktop-settings-ai-save-check'),
              onPressed: saving ? null : onSaveAndCheck,
              icon: saving
                  ? SizedBox.square(
                      dimension: _px(context, 15),
                      child: CircularProgressIndicator(
                        strokeWidth: _px(context, 1.8),
                        color: Colors.white,
                      ),
                    )
                  : Icon(Icons.sync_rounded, size: _px(context, 17)),
              label: Text(
                saving
                    ? copy.localized('检测中', 'Checking')
                    : copy.localized('保存并检测', 'Save & check'),
              ),
              style: FilledButton.styleFrom(
                minimumSize: Size(0, _px(context, 38)),
                padding: EdgeInsets.symmetric(horizontal: _px(context, 11)),
                backgroundColor: DesktopColors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_px(context, 9)),
                ),
              ),
            ),
          ),
          if (feedback != null) ...<Widget>[
            SizedBox(height: _px(context, 7)),
            Text(
              feedback!,
              key: const ValueKey<String>('desktop-settings-ai-feedback'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: _font(context, 11),
                height: 1.25,
                color: feedbackSucceeded == true
                    ? const Color(0xFF497461)
                    : const Color(0xFF9F4D5D),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard({
    required this.controller,
    required this.saving,
    required this.onSelectTheme,
  });

  final AppController controller;
  final bool saving;
  final ValueChanged<ColorSchemeOption> onSelectTheme;

  @override
  Widget build(BuildContext context) {
    const List<ColorSchemeOption> schemes = ColorSchemeOption.values;
    final AppCopy copy = controller.copy;
    return _SettingsCard(
      icon: Icons.palette_outlined,
      title: copy.localized('外观与主题', 'Appearance & Theme'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              for (int index = 0; index < schemes.length; index++) ...<Widget>[
                if (index > 0) SizedBox(width: _px(context, 7)),
                Expanded(
                  child: _ThemePreview(
                    scheme: schemes[index],
                    selected: controller.colorScheme == schemes[index],
                    enabled: !saving,
                    label: controller.copy.colorSchemeName(schemes[index]),
                    onTap: () => onSelectTheme(schemes[index]),
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: _px(context, 12)),
          Row(
            children: <Widget>[
              Expanded(
                child: _FieldLabel(
                  label: copy.localized('主题色', 'Accent color'),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _UnavailableLabel(
                    label: copy.localized(
                      '当前版本不可调整',
                      'Not adjustable in this version',
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: _px(context, 6)),
          _DisabledAccentColors(copy: copy),
          SizedBox(height: _px(context, 8)),
          Row(
            children: <Widget>[
              _FieldLabel(label: copy.localized('界面缩放', 'Interface scale')),
              SizedBox(width: _px(context, 8)),
              Text(
                '100%',
                style: TextStyle(
                  fontSize: _font(context, 12),
                  fontWeight: FontWeight.w600,
                  color: DesktopColors.secondaryText,
                ),
              ),
              SizedBox(width: _px(context, 8)),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _UnavailableLabel(
                    label: copy.localized(
                      '当前版本不可调整',
                      'Not adjustable in this version',
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(
            height: _px(context, 24),
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                disabledActiveTrackColor: const Color(0xFFDCD5CD),
                disabledInactiveTrackColor: const Color(0xFFEAE4DD),
                disabledThumbColor: const Color(0xFFCFC7BE),
                trackHeight: _px(context, 3),
                thumbShape: RoundSliderThumbShape(
                  enabledThumbRadius: _px(context, 6),
                  disabledThumbRadius: _px(context, 6),
                ),
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: const Slider(
                value: 1,
                min: 0.8,
                max: 1.2,
                onChanged: null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview({
    required this.scheme,
    required this.selected,
    required this.enabled,
    required this.label,
    required this.onTap,
  });

  final ColorSchemeOption scheme;
  final bool selected;
  final bool enabled;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final DesktopMetrics metrics = DesktopMetricsScope.of(context);
    final AppPalette palette = PaletteRegistry.of(scheme);
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        enabled: enabled,
        label: label,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(metrics.radius(9)),
            child: AnimatedContainer(
              key: ValueKey<String>('desktop-settings-theme-${scheme.code}'),
              duration: const Duration(milliseconds: 160),
              padding: EdgeInsets.all(metrics.px(5)),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFFFF2E9) : DesktopColors.card,
                borderRadius: BorderRadius.circular(metrics.radius(9)),
                border: Border.all(
                  color: selected
                      ? DesktopColors.orange
                      : const Color(0x1AA76D48),
                  width: selected ? metrics.px(1.5) : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(
                    height: metrics.px(45),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(metrics.radius(5)),
                      child: _ThemeMiniature(palette: palette),
                    ),
                  ),
                  SizedBox(height: metrics.px(4)),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: metrics.font(11),
                      height: 1.1,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: DesktopColors.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeMiniature extends StatelessWidget {
  const _ThemeMiniature({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: palette.pageBackground,
    child: Padding(
      padding: const EdgeInsets.all(5),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 12,
                height: 5,
                decoration: BoxDecoration(
                  color: palette.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Spacer(),
              Container(width: 7, height: 4, color: palette.textSecondary),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Row(
              children: <Widget>[
                Container(
                  width: 16,
                  decoration: BoxDecoration(
                    color: palette.surfaceContainer,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    children: <Widget>[
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: palette.surface,
                            borderRadius: BorderRadius.circular(2),
                            border: Border.all(color: palette.outline),
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Expanded(
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: ColoredBox(
                                color: palette.primaryContainer,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: ColoredBox(
                                color: palette.secondaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _DisabledAccentColors extends StatelessWidget {
  const _DisabledAccentColors({required this.copy});

  final AppCopy copy;

  static const List<Color> _colors = <Color>[
    Color(0xFFFF6846),
    Color(0xFFFFB427),
    Color(0xFF46BE72),
    Color(0xFF3489E8),
    Color(0xFFA555D8),
    Color(0xFFEF4A7A),
  ];

  @override
  Widget build(BuildContext context) => Tooltip(
    message: copy.localized('当前版本不可调整', 'Not adjustable in this version'),
    child: Semantics(
      enabled: false,
      label: copy.localized(
        '主题色，当前版本不可调整',
        'Accent color, not adjustable in this version',
      ),
      child: IgnorePointer(
        child: MouseRegion(
          cursor: SystemMouseCursors.basic,
          child: Opacity(
            opacity: 0.38,
            child: Row(
              children: <Widget>[
                for (
                  int index = 0;
                  index < _colors.length;
                  index++
                ) ...<Widget>[
                  if (index > 0) SizedBox(width: _px(context, 9)),
                  Container(
                    key: index == 0
                        ? const ValueKey<String>(
                            'desktop-settings-disabled-accent',
                          )
                        : null,
                    width: _px(context, 19),
                    height: _px(context, 19),
                    decoration: BoxDecoration(
                      color: _colors[index],
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _NotificationsCard extends StatelessWidget {
  const _NotificationsCard({required this.copy});

  final AppCopy copy;

  @override
  Widget build(BuildContext context) => _SettingsCard(
    icon: Icons.notifications_none_rounded,
    title: copy.localized('通知设置', 'Notification Settings'),
    child: Column(
      children: <Widget>[
        _UnavailableSettingRow(
          icon: Icons.new_releases_outlined,
          title: copy.localized('游戏上新通知', 'New Game Notifications'),
          subtitle: copy.localized(
            '关注的桌游有新内容时提醒',
            'Notify me when followed games get new content',
          ),
          unavailableLabel: copy.localized('暂不可用', 'Unavailable'),
        ),
        const _SettingsDivider(),
        _UnavailableSettingRow(
          icon: Icons.article_outlined,
          title: copy.localized('桌游资讯推送', 'Board Game News'),
          subtitle: copy.localized(
            '精选桌游文章、测评和资讯',
            'Curated articles, reviews, and news',
          ),
          unavailableLabel: copy.localized('暂不可用', 'Unavailable'),
        ),
      ],
    ),
  );
}

class _SyncBackupCard extends StatelessWidget {
  const _SyncBackupCard({
    required this.controller,
    required this.settingsController,
    required this.urlController,
    required this.usernameController,
    required this.passwordController,
    required this.checking,
    required this.showPassword,
    required this.feedback,
    required this.feedbackSucceeded,
    required this.onTogglePassword,
    required this.onSaveAndCheck,
  });

  final AppController controller;
  final WebDavSettingsController? settingsController;
  final TextEditingController urlController;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool checking;
  final bool showPassword;
  final String? feedback;
  final bool? feedbackSucceeded;
  final VoidCallback onTogglePassword;
  final VoidCallback onSaveAndCheck;

  @override
  Widget build(BuildContext context) {
    final AppCopy copy = controller.copy;
    final List<AssetSourceConfig> sources = controller.assetSourceConfigs;
    final Map<String, ConnectivityStatus> statuses =
        controller.assetSourceStatuses;
    final int connected = sources.where((source) {
      return statuses[source.id]?.state == ConnectivityState.success;
    }).length;
    final bool isLoading =
        checking ||
        sources.any((source) {
          return statuses[source.id]?.state == ConnectivityState.loading;
        });
    final String stateLabel;
    final Color stateColor;
    if (sources.isEmpty) {
      stateLabel = copy.localized('未配置', 'Not configured');
      stateColor = DesktopColors.secondaryText;
    } else if (isLoading) {
      stateLabel = copy.localized('检测中', 'Checking');
      stateColor = DesktopColors.brown;
    } else if (connected > 0) {
      stateLabel = copy.localized(
        '已连接 $connected/${sources.length}',
        'Connected $connected/${sources.length}',
      );
      stateColor = const Color(0xFF497461);
    } else if (statuses.isEmpty ||
        sources.every((source) {
          return statuses[source.id] == null ||
              statuses[source.id]?.state == ConnectivityState.unknown;
        })) {
      stateLabel = copy.localized('尚未检测', 'Not checked');
      stateColor = DesktopColors.secondaryText;
    } else {
      stateLabel = copy.localized('连接失败', 'Connection failed');
      stateColor = const Color(0xFF9F4D5D);
    }

    return _SettingsCard(
      icon: Icons.cloud_outlined,
      title: copy.localized('同步与备份', 'Sync & Backup'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      copy.localized(
                        '桌游资料 WebDAV',
                        'Board Game Resources via WebDAV',
                      ),
                      style: TextStyle(
                        fontSize: _font(context, 13),
                        fontWeight: FontWeight.w600,
                        color: DesktopColors.text,
                      ),
                    ),
                    SizedBox(height: _px(context, 3)),
                    Text(
                      copy.localized(
                        '${sources.length} 个资料源；只用于游戏资源，不同步个人数据',
                        '${sources.length} resource sources; game resources only, personal data is not synced',
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: _font(context, 11),
                        height: 1.25,
                        color: DesktopColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: _px(context, 8)),
              _StatusPill(label: stateLabel, color: stateColor),
            ],
          ),
          SizedBox(height: _px(context, 8)),
          if (settingsController != null) ...<Widget>[
            _EditableValueField(
              fieldKey: const ValueKey<String>('desktop-settings-webdav-url'),
              label: copy.localized('WebDAV 地址', 'WebDAV URL'),
              controller: urlController,
              enabled: !checking,
            ),
            SizedBox(height: _px(context, 8)),
            Row(
              children: <Widget>[
                Expanded(
                  child: _EditableValueField(
                    fieldKey: const ValueKey<String>(
                      'desktop-settings-webdav-username',
                    ),
                    label: copy.localized('账号', 'Username'),
                    controller: usernameController,
                    enabled: !checking,
                  ),
                ),
                SizedBox(width: _px(context, 8)),
                Expanded(
                  child: _EditableValueField(
                    fieldKey: const ValueKey<String>(
                      'desktop-settings-webdav-password',
                    ),
                    label: copy.localized('密码', 'Password'),
                    controller: passwordController,
                    enabled: !checking,
                    obscureText: !showPassword,
                    trailing: IconButton(
                      tooltip: showPassword
                          ? copy.localized('隐藏密码', 'Hide password')
                          : copy.localized('显示密码', 'Show password'),
                      onPressed: checking ? null : onTogglePassword,
                      icon: Icon(
                        showPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: _px(context, 18),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (feedback != null) ...<Widget>[
              SizedBox(height: _px(context, 8)),
              Text(
                feedback!,
                key: const ValueKey<String>('desktop-settings-webdav-feedback'),
                style: TextStyle(
                  fontSize: _font(context, 11),
                  height: 1.3,
                  color: feedbackSucceeded == true
                      ? const Color(0xFF497461)
                      : const Color(0xFF9F4D5D),
                ),
              ),
            ],
            SizedBox(height: _px(context, 8)),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey<String>(
                'desktop-settings-check-resource-sources',
              ),
              onPressed: checking ? null : onSaveAndCheck,
              icon: checking
                  ? SizedBox.square(
                      dimension: _px(context, 15),
                      child: CircularProgressIndicator(
                        strokeWidth: _px(context, 1.8),
                      ),
                    )
                  : Icon(Icons.network_check_rounded, size: _px(context, 17)),
              label: Text(
                checking
                    ? copy.localized('正在检测', 'Checking')
                    : settingsController == null
                    ? copy.localized('检测资料源', 'Check sources')
                    : copy.localized('保存并检测', 'Save & Test'),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: Size(0, _px(context, 36)),
                padding: EdgeInsets.symmetric(horizontal: _px(context, 10)),
                foregroundColor: DesktopColors.brown,
                side: const BorderSide(color: Color(0x1FA76D48)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_px(context, 8)),
                ),
              ),
            ),
          ),
          SizedBox(height: _px(context, 5)),
          _SettingsDivider(height: _px(context, 9)),
          _UnavailableSettingRow(
            icon: Icons.sync_rounded,
            title: copy.localized('个人数据自动同步', 'Automatic Personal Data Sync'),
            subtitle: copy.localized(
              '当前版本不包含个人数据同步',
              'Personal data sync is not included in this version',
            ),
            unavailableLabel: copy.localized('暂不可用', 'Unavailable'),
            compact: true,
          ),
          SizedBox(height: _px(context, 6)),
          Row(
            children: <Widget>[
              Expanded(
                child: _DisabledButton(
                  label: copy.localized('立即同步', 'Sync now'),
                  icon: Icons.sync_rounded,
                  unavailableMessage: copy.localized(
                    '当前版本不可用',
                    'Unavailable in this version',
                  ),
                  key: const ValueKey<String>('desktop-settings-sync-disabled'),
                ),
              ),
              SizedBox(width: _px(context, 8)),
              Expanded(
                child: _DisabledButton(
                  label: copy.localized('导入备份', 'Import backup'),
                  icon: Icons.file_download_outlined,
                  unavailableMessage: copy.localized(
                    '当前版本不可用',
                    'Unavailable in this version',
                  ),
                ),
              ),
              SizedBox(width: _px(context, 8)),
              Expanded(
                child: _DisabledButton(
                  label: copy.localized('导出备份', 'Export backup'),
                  icon: Icons.file_upload_outlined,
                  unavailableMessage: copy.localized(
                    '当前版本不可用',
                    'Unavailable in this version',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AboutUpdatesCard extends StatelessWidget {
  const _AboutUpdatesCard({
    required this.controller,
    required this.version,
    required this.onOpenAbout,
  });

  final AppController controller;
  final Future<String> version;
  final VoidCallback onOpenAbout;

  @override
  Widget build(BuildContext context) {
    final AppCopy copy = controller.copy;
    return _SettingsCard(
      icon: Icons.info_outline_rounded,
      title: copy.localized('关于与更新', 'About & Updates'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _FieldLabel(
                  label: copy.localized('当前版本', 'Current version'),
                ),
              ),
              FutureBuilder<String>(
                future: version,
                builder: (context, snapshot) => Text(
                  snapshot.data ?? copy.localized('读取中…', 'Loading…'),
                  key: const ValueKey<String>('desktop-settings-app-version'),
                  style: TextStyle(
                    fontSize: _font(context, 13),
                    fontWeight: FontWeight.w600,
                    color: DesktopColors.text,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: _px(context, 8)),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: _px(context, 11),
              vertical: _px(context, 9),
            ),
            decoration: BoxDecoration(
              color: DesktopColors.soft,
              borderRadius: BorderRadius.circular(_px(context, 8)),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  controller.checkForUpdates
                      ? Icons.update_rounded
                      : Icons.update_disabled_rounded,
                  size: _px(context, 18),
                  color: DesktopColors.orange,
                ),
                SizedBox(width: _px(context, 8)),
                Expanded(
                  child: Text(
                    controller.checkForUpdates
                        ? copy.localized(
                            '启动检查已开启（更新源仅支持 Android APK）',
                            'Startup checks are enabled (the update source supports Android APK only)',
                          )
                        : copy.localized(
                            '启动检查已关闭',
                            'Startup checks are disabled',
                          ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: _font(context, 11.5),
                      height: 1.25,
                      color: DesktopColors.secondaryText,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: _px(context, 11)),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey<String>('desktop-settings-check-updates'),
                  onPressed: onOpenAbout,
                  icon: Icon(
                    Icons.system_update_alt_rounded,
                    size: _px(context, 17),
                  ),
                  label: Text(copy.localized('检查更新', 'Check for updates')),
                  style: _settingsButtonStyle(context),
                ),
              ),
              SizedBox(width: _px(context, 9)),
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey<String>('desktop-settings-open-about'),
                  onPressed: onOpenAbout,
                  icon: Icon(Icons.open_in_new_rounded, size: _px(context, 17)),
                  label: Text(copy.localized('关于应用', 'About app')),
                  style: FilledButton.styleFrom(
                    minimumSize: Size(0, _px(context, 39)),
                    backgroundColor: DesktopColors.orange,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: _px(context, 8)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(_px(context, 9)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AiStatusLabel extends StatelessWidget {
  const _AiStatusLabel({
    required this.status,
    required this.hasKey,
    required this.copy,
  });

  final ConnectivityStatus status;
  final bool hasKey;
  final AppCopy copy;

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color color;
    if (!hasKey) {
      label = copy.localized('未配置', 'Not configured');
      color = DesktopColors.secondaryText;
    } else {
      switch (status.state) {
        case ConnectivityState.success:
          label = copy.localized('连接正常', 'Connection ready');
          color = const Color(0xFF497461);
        case ConnectivityState.loading:
          label = copy.localized('检测中', 'Checking');
          color = DesktopColors.brown;
        case ConnectivityState.warning:
          label = copy.localized('需要留意', 'Needs attention');
          color = const Color(0xFF945D31);
        case ConnectivityState.failure:
          label = copy.localized('连接失败', 'Connection failed');
          color = const Color(0xFF9F4D5D);
        case ConnectivityState.unknown:
          label = copy.localized('尚未检测', 'Not checked');
          color = DesktopColors.secondaryText;
      }
    }
    return Row(
      children: <Widget>[
        Container(
          width: _px(context, 7),
          height: _px(context, 7),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: _px(context, 6)),
        Flexible(
          child: Text(
            '${copy.localized('AI 服务', 'AI Service')} · $label',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: _font(context, 11),
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _DesktopAiProviderOption {
  const _DesktopAiProviderOption({
    required this.id,
    required this.label,
    required this.config,
    this.isNewCustom = false,
  });

  final String id;
  final String label;
  final AiApiConfig config;
  final bool isNewCustom;
}

class _AiProviderDropdownField extends StatelessWidget {
  const _AiProviderDropdownField({
    required this.fieldKey,
    required this.label,
    required this.options,
    required this.selectedId,
    required this.enabled,
    required this.onChanged,
  });

  final Key fieldKey;
  final String label;
  final List<_DesktopAiProviderOption> options;
  final String selectedId;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      _FieldLabel(label: label),
      SizedBox(height: _px(context, 4)),
      SizedBox(
        height: _px(context, 39),
        child: KeyedSubtree(
          key: fieldKey,
          child: DropdownButtonFormField<String>(
            key: ValueKey<String>('provider-$selectedId'),
            initialValue: selectedId,
            isExpanded: true,
            icon: Icon(Icons.expand_more_rounded, size: _px(context, 18)),
            style: TextStyle(
              fontSize: _font(context, 12),
              color: DesktopColors.text,
              fontWeight: FontWeight.w500,
            ),
            decoration: _fieldDecoration(context).copyWith(
              contentPadding: EdgeInsets.only(
                left: _px(context, 10),
                right: _px(context, 6),
              ),
            ),
            items: options
                .map(
                  (_DesktopAiProviderOption option) => DropdownMenuItem<String>(
                    value: option.id,
                    child: Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: enabled ? onChanged : null,
          ),
        ),
      ),
    ],
  );
}

class _AiModelDropdownField extends StatelessWidget {
  const _AiModelDropdownField({
    required this.fieldKey,
    required this.label,
    required this.models,
    required this.selectedModel,
    required this.loadState,
    required this.enabled,
    required this.copy,
    required this.onChanged,
  });

  final Key fieldKey;
  final String label;
  final List<AiModel> models;
  final String selectedModel;
  final AiModelLoadState loadState;
  final bool enabled;
  final AppCopy copy;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final String normalizedSelection = selectedModel.trim();
    final bool selectionAvailable = models.any(
      (AiModel model) => model.id == normalizedSelection,
    );
    final String hint = switch (loadState) {
      AiModelLoadState.loading => copy.localized('正在获取…', 'Loading…'),
      AiModelLoadState.failure => copy.localized('获取失败', 'Load failed'),
      AiModelLoadState.empty => copy.localized('没有可用模型', 'No models'),
      _ => copy.localized('保存并检测后选择', 'Save & check first'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _FieldLabel(label: label),
        SizedBox(height: _px(context, 4)),
        SizedBox(
          height: _px(context, 39),
          child: KeyedSubtree(
            key: fieldKey,
            child: DropdownButtonFormField<String>(
              key: ValueKey<String>(
                'model-${loadState.name}-$normalizedSelection-${models.length}',
              ),
              initialValue: selectionAvailable ? normalizedSelection : null,
              isExpanded: true,
              hint: Text(hint, overflow: TextOverflow.ellipsis),
              icon: loadState == AiModelLoadState.loading
                  ? SizedBox.square(
                      dimension: _px(context, 14),
                      child: CircularProgressIndicator(
                        strokeWidth: _px(context, 1.6),
                      ),
                    )
                  : Icon(Icons.expand_more_rounded, size: _px(context, 18)),
              style: TextStyle(
                fontSize: _font(context, 12),
                color: DesktopColors.text,
                fontWeight: FontWeight.w500,
              ),
              decoration: _fieldDecoration(context).copyWith(
                contentPadding: EdgeInsets.only(
                  left: _px(context, 10),
                  right: _px(context, 6),
                ),
              ),
              items: models
                  .map(
                    (AiModel model) => DropdownMenuItem<String>(
                      value: model.id,
                      child: Text(
                        model.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: enabled && models.isNotEmpty ? onChanged : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _EditableValueField extends StatelessWidget {
  const _EditableValueField({
    required this.fieldKey,
    required this.label,
    required this.controller,
    required this.enabled,
    this.obscureText = false,
    this.trailing,
    this.onChanged,
  });

  final Key fieldKey;
  final String label;
  final TextEditingController controller;
  final bool enabled;
  final bool obscureText;
  final Widget? trailing;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      _FieldLabel(label: label),
      SizedBox(height: _px(context, 4)),
      SizedBox(
        height: _px(context, 39),
        child: TextField(
          key: fieldKey,
          controller: controller,
          enabled: enabled,
          obscureText: obscureText,
          obscuringCharacter: '•',
          maxLines: 1,
          onChanged: onChanged,
          style: TextStyle(
            fontSize: _font(context, 12),
            color: DesktopColors.text,
            fontWeight: FontWeight.w500,
          ),
          decoration: _fieldDecoration(context).copyWith(
            contentPadding: EdgeInsets.symmetric(
              horizontal: _px(context, 10),
              vertical: _px(context, 9),
            ),
            suffixIcon: trailing,
            suffixIconConstraints: BoxConstraints(
              minWidth: _px(context, 38),
              minHeight: _px(context, 38),
            ),
          ),
        ),
      ),
    ],
  );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: TextStyle(
      fontSize: _font(context, 12),
      height: 1.15,
      fontWeight: FontWeight.w500,
      color: DesktopColors.secondaryText,
    ),
  );
}

class _SettingSwitchRow extends StatelessWidget {
  const _SettingSwitchRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: TextStyle(
                fontSize: _font(context, 13),
                fontWeight: FontWeight.w600,
                color: DesktopColors.text,
              ),
            ),
            SizedBox(height: _px(context, 2)),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: _font(context, 11),
                color: DesktopColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
      SizedBox(width: _px(context, 5)),
      Transform.scale(
        scale: 0.86,
        alignment: Alignment.centerRight,
        child: Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeThumbColor: DesktopColors.orange,
        ),
      ),
    ],
  );
}

class _UnavailableSettingRow extends StatelessWidget {
  const _UnavailableSettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.unavailableLabel,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String unavailableLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) => Semantics(
    enabled: false,
    child: Opacity(
      opacity: 0.72,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: _px(context, compact ? 2 : 8)),
        child: Row(
          children: <Widget>[
            Icon(icon, size: _px(context, 20), color: DesktopColors.brown),
            SizedBox(width: _px(context, 10)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: _font(context, 13),
                      fontWeight: FontWeight.w600,
                      color: DesktopColors.text,
                    ),
                  ),
                  SizedBox(height: _px(context, 2)),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: _font(context, 11),
                      height: 1.25,
                      color: DesktopColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: _px(context, 8)),
            _UnavailableLabel(label: unavailableLabel),
          ],
        ),
      ),
    ),
  );
}

class _UnavailableLabel extends StatelessWidget {
  const _UnavailableLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: _font(context, 11),
      color: const Color(0xFF9B928A),
    ),
  );
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider({this.height = 8});

  final double height;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: height / 2),
    child: const Divider(height: 1, color: Color(0x16A76D48)),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: _px(context, 8),
      vertical: _px(context, 5),
    ),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: _font(context, 11),
        color: color,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _DisabledButton extends StatelessWidget {
  const _DisabledButton({
    super.key,
    required this.label,
    required this.icon,
    required this.unavailableMessage,
  });

  final String label;
  final IconData icon;
  final String unavailableMessage;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: unavailableMessage,
    child: OutlinedButton.icon(
      onPressed: null,
      icon: Icon(icon, size: _px(context, 15)),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        minimumSize: Size(0, _px(context, 35)),
        padding: EdgeInsets.symmetric(horizontal: _px(context, 5)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_px(context, 8)),
        ),
      ),
    ),
  );
}

InputDecoration _fieldDecoration(BuildContext context) => InputDecoration(
  isDense: true,
  contentPadding: EdgeInsets.symmetric(
    horizontal: _px(context, 10),
    vertical: _px(context, 10),
  ),
  filled: true,
  fillColor: DesktopColors.soft,
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(_px(context, 8)),
    borderSide: const BorderSide(color: Color(0x10A76D48)),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(_px(context, 8)),
    borderSide: const BorderSide(color: DesktopColors.orange, width: 1.2),
  ),
);

ButtonStyle _settingsButtonStyle(BuildContext context) =>
    OutlinedButton.styleFrom(
      minimumSize: Size(0, _px(context, 39)),
      foregroundColor: DesktopColors.brown,
      side: const BorderSide(color: Color(0x1FA76D48)),
      padding: EdgeInsets.symmetric(horizontal: _px(context, 8)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_px(context, 9)),
      ),
    );

double _px(BuildContext context, double value) =>
    DesktopMetricsScope.of(context).px(value);

double _font(BuildContext context, double value) =>
    DesktopMetricsScope.of(context).font(value);
