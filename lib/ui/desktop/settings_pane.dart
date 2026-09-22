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

part 'settings/preferences_cards.dart';
part 'settings/ai_service_card.dart';
part 'settings/sync_about_cards.dart';

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
