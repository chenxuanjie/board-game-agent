import 'dart:async';

import 'package:app_ai_client/app_ai_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../core/theme/app_motion.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:webdav_settings/webdav_settings.dart';

import '../../features/assistant/models/ai_api_config.dart';
import '../../features/assistant/models/ai_model_policy.dart';
import '../../core/localization/app_language.dart';
import '../../features/library/models/asset_source_config.dart';
import '../../core/theme/color_scheme_option.dart';
import '../../core/models/connectivity_status.dart';
import '../../features/settings/services/desktop_ai_settings_service.dart';
import '../../app/state/app_controller.dart';
import '../../core/theme/app_palette.dart';
import '../shared/resource_access_summary.dart';
import '../shared/account_scope.dart';
import '../shared/account_screen.dart';
import '../shared/resource_connection_screen.dart';
import '../shared/settings_section_focus.dart';
import '../shared/settings_transfer_screen.dart';
import '../../features/settings/models/configuration_transfer.dart';
import '../../features/settings/services/settings_transfer_service.dart';

import '../../core/theme/palette_registry.dart';
import '../../core/localization/app_copy.dart';
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
    this.onCheckUpdates,
    this.webDavSettingsController,
    this.focusAiSettings = false,
    this.transferService,
  });

  final AppController controller;
  final bool focusAiSettings;
  final VoidCallback onOpenAbout;
  final VoidCallback? onCheckUpdates;
  final WebDavSettingsController? webDavSettingsController;
  final SettingsTransferService? transferService;

  @override
  State<DesktopSettingsPane> createState() => _DesktopSettingsPaneState();
}

class _DesktopSettingsPaneState extends State<DesktopSettingsPane> {
  late final SettingsTransferService _transfer =
      widget.transferService ??
      SettingsTransferService(
        controller: widget.controller,
        webDav: widget.webDavSettingsController,
      );

  void _importApplied() {
    if (!mounted) return;
    final ai = widget.controller.aiApiConfig;
    setState(() {
      _aiProvider.text = ai.name;
      _aiModel.text = ai.model;
      _aiApiKey.text = ai.apiKey;
      _aiBaseUrl.text = ai.baseUrl;
      _aiReasoningEffort = ai.reasoningEffort;
      _aiResponseSpeed = ai.responseSpeed;
      _aiProviderOptionId = _providerOptionId(ai);
      _aiFeedback = null;
    });
  }

  Widget _transferMenu(ConfigurationScope scope) => SettingsTransferMenu(
    service: _transfer,
    scope: scope,
    onApplied: _importApplied,
    enabled: !_savingAi && !_checkingSources,
  );
  Future<void> _editResourceConnection(AssetSourceConfig source) async {
    if (_transfer.webDav == null || _transfer.isBusy || _checkingSources) {
      return;
    }
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            ResourceConnectionScreen(service: _transfer, source: source),
      ),
    );
    if (mounted) _importApplied();
  }

  late final Future<String> _version = _loadVersion();
  late final DesktopAiSettingsService _desktopAiSettings;
  late final TextEditingController _aiProvider;
  late final TextEditingController _aiModel;
  late final TextEditingController _aiApiKey;
  late final TextEditingController _aiBaseUrl;
  late String _aiProviderOptionId;
  late AiReasoningEffort _aiReasoningEffort;
  late AiResponseSpeed _aiResponseSpeed;
  DesktopAiCheckStep? _aiCheckStep;
  bool _saving = false;
  bool _savingAi = false;
  bool _checkingSources = false;
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
    _aiProviderOptionId = _providerOptionId(config);
    _aiReasoningEffort = config.reasoningEffort;
    _aiResponseSpeed = config.responseSpeed;
  }

  @override
  void dispose() {
    _aiProvider.dispose();
    _aiModel.dispose();
    _aiApiKey.dispose();
    _aiBaseUrl.dispose();
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

  Future<void> _reorderSources(int oldIndex, int newIndex) async {
    if (_checkingSources) return;
    if (newIndex > oldIndex) newIndex--;
    final next = widget.controller.assetSourceConfigs.toList();
    next.insert(newIndex, next.removeAt(oldIndex));
    setState(() => _checkingSources = true);
    try {
      final account = AccountScope.maybeOf(context);
      if (account?.configuration != null) {
        final config = account!.configuration!;
        await account.saveConfiguration(
          config.edited(
            servers: next
                .map((s) => config.servers.firstWhere((a) => a.id == s.id))
                .toList(),
            folder: config.storageFolder,
          ),
        );
        if (account.error != null) throw StateError('Connection pending');
      } else {
        await widget.controller.saveAssetSourceConfigs(next);
      }
    } catch (_) {
      if (mounted) setState(() => _failure = '顺序保存失败，请重试');
    } finally {
      if (mounted) setState(() => _checkingSources = false);
    }
  }

  Future<void> _saveAndCheckAi() async {
    if (_savingAi) return;
    setState(() {
      _savingAi = true;
      _aiCheckStep = DesktopAiCheckStep.saving;
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
              reasoningEffort: _aiReasoningEffort,
              responseSpeed: _aiResponseSpeed,
            ),
            onProgress: (DesktopAiCheckStep step) {
              if (mounted) setState(() => _aiCheckStep = step);
            },
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
      if (mounted) {
        setState(() {
          _savingAi = false;
          _aiCheckStep = null;
        });
      }
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
      _aiReasoningEffort = option.config.reasoningEffort;
      _aiResponseSpeed = option.config.responseSpeed;
      _aiCheckStep = null;
      _aiFeedback = null;
      _aiFeedbackSucceeded = null;
    });
    widget.controller.invalidateAiModels();
  }

  void _invalidateAiDiscovery(String _) {
    setState(() {
      if (_aiModel.text.isNotEmpty) {
        _aiModel.clear();
        _aiReasoningEffort = AiReasoningEffort.automatic;
      }
      _aiFeedback = null;
      _aiFeedbackSucceeded = null;
    });
    widget.controller.invalidateAiModels();
  }

  void _selectAiModel(String? model) {
    setState(() {
      _aiModel.text = model ?? '';
      final List<AiReasoningEffort>? supported = AiModelPolicy.reasoningEfforts(
        _aiModel.text,
      );
      if (supported != null && !supported.contains(_aiReasoningEffort)) {
        _aiReasoningEffort = AiReasoningEffort.automatic;
      }
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
        if (AccountScope.maybeOf(context) != null)
          _SettingsCard(
            icon: Icons.account_circle_outlined,
            title: widget.controller.copy.localized('账户', 'Account'),
            child: AccountEntry(
              title: widget.controller.copy.localized(
                '个人中心',
                'Account details',
              ),
            ),
          ),
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
        SettingsSectionFocus(
          reveal: widget.focusAiSettings,
          child: _AiServiceCard(
            transferMenu: _transferMenu(ConfigurationScope.ai),
            controller: widget.controller,
            providerOptions: _providerOptions(),
            selectedProviderId: _aiProviderOptionId,
            providerController: _aiProvider,
            modelController: _aiModel,
            apiKeyController: _aiApiKey,
            baseUrlController: _aiBaseUrl,
            showApiKey: _showApiKey,
            saving: _savingAi,
            checkStep: _aiCheckStep,
            reasoningEffort: _aiReasoningEffort,
            responseSpeed: _aiResponseSpeed,
            feedback: _aiFeedback,
            feedbackSucceeded: _aiFeedbackSucceeded,
            onProviderChanged: _selectAiProvider,
            onAiFieldChanged: _invalidateAiDiscovery,
            onModelChanged: _selectAiModel,
            onReasoningChanged: (AiReasoningEffort value) => setState(() {
              _aiReasoningEffort = value;
              _aiFeedback = null;
              _aiFeedbackSucceeded = null;
            }),
            onSpeedChanged: (AiResponseSpeed value) => setState(() {
              _aiResponseSpeed = value;
              _aiFeedback = null;
              _aiFeedbackSucceeded = null;
            }),
            onToggleApiKey: () => setState(() => _showApiKey = !_showApiKey),
            onSaveAndCheck: () => unawaited(_saveAndCheckAi()),
          ),
        ),
        _AppearanceCard(
          controller: widget.controller,
          saving: _saving,
          onSelectTheme: (ColorSchemeOption scheme) =>
              unawaited(_save(() => widget.controller.setColorScheme(scheme))),
        ),
        if (AccountScope.maybeOf(context) == null)
          _SyncBackupCard(
            onEditSource: _transfer.webDav == null
                ? null
                : _editResourceConnection,
            transferMenu: _transferMenu(ConfigurationScope.webDav),
            controller: widget.controller,
            settingsController: widget.webDavSettingsController,
            checking: _checkingSources,
            onReorder: _reorderSources,
            onCheckSources: _checkResourceSources,
          ),
        _AboutUpdatesCard(
          controller: widget.controller,
          version: _version,
          onOpenAbout: widget.onOpenAbout,
          onCheckUpdates: widget.onCheckUpdates ?? widget.onOpenAbout,
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (int index = start; index < end; index++) ...<Widget>[
                      if (index > start) SizedBox(width: gap),
                      Expanded(child: cards[index]),
                    ],
                  ],
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
                    _transferMenu(ConfigurationScope.all),
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
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;

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
              ?trailing,
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
            if (subtitle.isNotEmpty) ...[
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

InputDecoration _fieldDecoration(BuildContext context) => InputDecoration(
  isDense: true,
  contentPadding: EdgeInsets.symmetric(
    horizontal: _px(context, 10),
    vertical: _px(context, 10),
  ),
);

ThemeData _dropdownTheme(BuildContext context) =>
    Theme.of(context).copyWith(focusColor: Colors.transparent);

Widget _dropdownOption(
  BuildContext context,
  String label, {
  required bool selected,
}) => _DesktopDropdownOption(
  label: label,
  selected: selected,
  metrics: DesktopMetricsScope.of(context),
);

class _DesktopDropdownOption extends StatefulWidget {
  const _DesktopDropdownOption({
    required this.label,
    required this.selected,
    required this.metrics,
  });

  final String label;
  final bool selected;
  final DesktopMetrics metrics;

  @override
  State<_DesktopDropdownOption> createState() => _DesktopDropdownOptionState();
}

class _DesktopDropdownOptionState extends State<_DesktopDropdownOption> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bool focused = Focus.maybeOf(context)?.hasFocus ?? false;
    final metrics = widget.metrics;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: AppMotion.duration(context, AppMotion.feedback),
        curve: AppMotion.curve,
        height: metrics.px(40),
        alignment: Alignment.centerLeft,
        margin: EdgeInsets.symmetric(
          horizontal: metrics.px(4),
          vertical: metrics.px(3),
        ),
        padding: EdgeInsets.symmetric(horizontal: metrics.px(9)),
        decoration: BoxDecoration(
          color: widget.selected
              ? const Color(0xFFFFE8DF)
              : focused || _hovered
              ? DesktopColors.soft
              : Colors.transparent,
          borderRadius: BorderRadius.circular(metrics.px(8)),
        ),
        child: Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

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
