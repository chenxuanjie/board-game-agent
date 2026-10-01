import 'package:app_ai_client/app_ai_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/theme/ui_tokens.dart';

import '../../features/assistant/models/ai_api_config.dart';
import '../../features/assistant/models/ai_model_policy.dart';
import '../../features/library/models/asset_source_config.dart';
import '../../core/localization/app_language.dart';
import '../../core/models/connectivity_status.dart';
import '../../core/theme/color_scheme_option.dart';
import '../../core/theme/palette_registry.dart';
import '../../app/state/app_controller.dart';
import '../../core/theme/app_palette.dart';
import '../../core/localization/app_copy.dart';

class MobileSettingsScreen extends StatefulWidget {
  const MobileSettingsScreen({
    super.key,
    required this.controller,
    required this.onOpenAbout,
  });

  final AppController controller;
  final VoidCallback onOpenAbout;

  @override
  State<MobileSettingsScreen> createState() => _MobileSettingsScreenState();
}

class _MobileSettingsScreenState extends State<MobileSettingsScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _keyController;
  late List<AssetSourceConfig> _assetSourceConfigs;
  late _AiPresetOption _selectedPreset;
  String? _selectedModel;
  AiReasoningEffort _selectedReasoningEffort = AiReasoningEffort.automatic;
  AiResponseSpeed _selectedResponseSpeed = AiResponseSpeed.standard;
  bool _isTesting = false;
  bool _isTestingAssets = false;
  String? _lastTestMessage;
  bool? _lastTestSucceeded;

  @override
  void initState() {
    super.initState();
    final config = widget.controller.aiApiConfig;
    final List<_AiPresetOption> options = _presetOptions(widget.controller);
    _selectedPreset = _presetForConfig(options, config);
    _nameController = TextEditingController(
      text:
          config.providerPreset == AiProviderPreset.custom &&
              !AiApiConfig.isBuiltInProviderName(config.name)
          ? config.name
          : '',
    );
    _urlController = TextEditingController(text: config.baseUrl);
    _keyController = TextEditingController(text: config.apiKey);
    _selectedModel = config.model.trim().isEmpty ? null : config.model.trim();
    _selectedReasoningEffort = config.reasoningEffort;
    _selectedResponseSpeed = config.responseSpeed;
    _assetSourceConfigs = widget.controller.assetSourceConfigs;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final copy = controller.copy;
        final palette = AppPalette.of(context);
        final List<AiReasoningEffort> supportedReasoning =
            AiModelPolicy.reasoningEfforts(_selectedModel ?? '') ??
            const <AiReasoningEffort>[AiReasoningEffort.automatic];
        final List<AiReasoningEffort> visibleReasoning =
            AiModelPolicy.selectableReasoningEfforts(_selectedModel ?? '') ??
            const [];
        final List<_AiPresetOption> presetOptions = _presetOptions(controller);
        final _AiPresetOption selectedPreset = _presetForId(
          presetOptions,
          _selectedPreset.id,
        );
        return Scaffold(
          key: const ValueKey('mobile-settings-screen'),
          backgroundColor: palette.pageBackground,
          appBar: AppBar(
            title: Text(copy.localized('设置', 'Settings')),
            backgroundColor: palette.pageBackground,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
          ),
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: SingleChildScrollView(
                  key: const ValueKey('mobile-settings-scroll'),
                  padding: EdgeInsets.fromLTRB(
                    18,
                    12,
                    18,
                    MediaQuery.viewInsetsOf(context).bottom + 32,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _SectionTitle(
                        title: copy.languageTitle,
                        icon: Icons.translate_rounded,
                      ),
                      const SizedBox(height: 10),
                      _SectionCard(
                        palette: palette,
                        child: SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<AppLanguage>(
                            key: const ValueKey('mobile-settings-language'),
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(
                                value: AppLanguage.zhHans,
                                label: Text('简体中文'),
                              ),
                              ButtonSegment(
                                value: AppLanguage.en,
                                label: Text('English'),
                              ),
                            ],
                            selected: {controller.language},
                            onSelectionChanged: (selection) =>
                                controller.setLanguage(selection.first),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _SectionTitle(
                        title: copy.colorSchemeTitle,
                        icon: Icons.palette_outlined,
                      ),
                      const SizedBox(height: 10),
                      _SectionCard(
                        palette: palette,
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: _ThemeChoice(
                                palette: palette,
                                title: copy.colorSchemeName(
                                  ColorSchemeOption.warmwoodStudy,
                                ),
                                swatch: PaletteRegistry.warmwoodStudy.primary,
                                selected:
                                    controller.colorScheme ==
                                    ColorSchemeOption.warmwoodStudy,
                                onTap: () => controller.setColorScheme(
                                  ColorSchemeOption.warmwoodStudy,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _ThemeChoice(
                                palette: palette,
                                title: copy.colorSchemeName(
                                  ColorSchemeOption.classic,
                                ),
                                swatch: PaletteRegistry.classic.primary,
                                selected:
                                    controller.colorScheme ==
                                    ColorSchemeOption.classic,
                                onTap: () => controller.setColorScheme(
                                  ColorSchemeOption.classic,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _ThemeChoice(
                                palette: palette,
                                title: copy.colorSchemeName(
                                  ColorSchemeOption.sunsetCoast,
                                ),
                                swatch: PaletteRegistry.sunsetCoast.primary,
                                selected:
                                    controller.colorScheme ==
                                    ColorSchemeOption.sunsetCoast,
                                onTap: () => controller.setColorScheme(
                                  ColorSchemeOption.sunsetCoast,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _SectionCard(
                        palette: palette,
                        padding: EdgeInsets.zero,
                        child: ExpansionTile(
                          key: const ValueKey('mobile-settings-sources'),
                          maintainState: true,
                          shape: const Border(),
                          collapsedShape: const Border(),
                          leading: Icon(
                            Icons.storage_rounded,
                            color: palette.primary,
                          ),
                          title: Text(copy.assetPriorityTitle),
                          subtitle: Text(
                            copy.localized(
                              '${_assetSourceConfigs.length} 个资料源',
                              '${_assetSourceConfigs.length} sources',
                            ),
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            16,
                            0,
                            16,
                            16,
                          ),
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                ReorderableListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _assetSourceConfigs.length,
                                  onReorder: _reorderSources,
                                  itemBuilder: (context, index) {
                                    final item = _assetSourceConfigs[index];
                                    return Container(
                                      key: ValueKey(item.id),
                                      margin: const EdgeInsets.only(bottom: 10),
                                      decoration: BoxDecoration(
                                        color: palette.surfaceVariant,
                                        borderRadius: BorderRadius.circular(
                                          UiTokens.groupRadius,
                                        ),
                                      ),
                                      child: ListTile(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 8,
                                            ),
                                        leading: CircleAvatar(
                                          backgroundColor: palette.primary
                                              .withValues(alpha: 0.16),
                                          foregroundColor: palette.primary,
                                          child: Text('${index + 1}'),
                                        ),
                                        title: Text(
                                          item.name,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleMedium,
                                        ),
                                        subtitle: Text(
                                          item.address,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: palette.textPrimary
                                                    .withValues(alpha: 0.72),
                                              ),
                                        ),
                                        trailing: ReorderableDragStartListener(
                                          index: index,
                                          child: Icon(
                                            Icons.drag_handle_rounded,
                                            color: palette.textPrimary
                                                .withValues(alpha: 0.72),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton(
                                    onPressed: _isTestingAssets
                                        ? null
                                        : _testAssets,
                                    child: Text(
                                      _isTestingAssets ? '...' : copy.assetTest,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _SectionCard(
                        palette: palette,
                        padding: EdgeInsets.zero,
                        child: ExpansionTile(
                          key: const ValueKey('mobile-settings-ai'),
                          maintainState: true,
                          shape: const Border(),
                          collapsedShape: const Border(),
                          leading: Icon(
                            Icons.auto_awesome_rounded,
                            color: palette.primary,
                          ),
                          title: Text(copy.aiApiTitle),
                          subtitle: Text(selectedPreset.label),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            16,
                            0,
                            16,
                            16,
                          ),
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                _ApiDropdownField<_AiPresetOption>(
                                  label: copy.aiApiPresetLabel,
                                  value: selectedPreset,
                                  values: presetOptions,
                                  itemLabel: (_AiPresetOption option) =>
                                      option.label,
                                  onChanged: _applyPreset,
                                ),
                                const SizedBox(height: 12),
                                if (selectedPreset.isCustom) ...<Widget>[
                                  _ApiField(
                                    label: copy.aiApiProviderNameLabel,
                                    controller: _nameController,
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                _ApiField(
                                  label: copy.aiApiUrlLabel,
                                  controller: _urlController,
                                  keyboardType: TextInputType.url,
                                  readOnly: !selectedPreset.isCustom,
                                  onChanged: _handleAiFieldChanged,
                                ),
                                const SizedBox(height: 12),
                                _ApiField(
                                  label: copy.aiApiKeyLabel,
                                  controller: _keyController,
                                  obscureText: true,
                                  onChanged: _handleAiFieldChanged,
                                ),
                                const SizedBox(height: 14),
                                _ModelDiscoveryPanel(
                                  controller: controller,
                                  selectedModel: _selectedModel,
                                  onChanged: (String? model) {
                                    setState(() {
                                      _selectedModel = model;
                                      final supported =
                                          AiModelPolicy.reasoningEfforts(
                                            model ?? '',
                                          );
                                      if (supported != null &&
                                          !supported.contains(
                                            _selectedReasoningEffort,
                                          )) {
                                        _selectedReasoningEffort =
                                            AiReasoningEffort.automatic;
                                      }
                                    });
                                  },
                                ),
                                const SizedBox(height: 14),
                                _ApiDropdownField<AiReasoningEffort>(
                                  label: copy.aiApiReasoningEffortLabel,
                                  placeholder: copy.aiApiReasoningSelectHint,
                                  value: _selectedReasoningEffort,
                                  values: visibleReasoning,
                                  itemLabel: copy.aiApiReasoningEffortName,
                                  onChanged: (AiReasoningEffort? value) {
                                    if (value != null) {
                                      setState(
                                        () => _selectedReasoningEffort = value,
                                      );
                                    }
                                  },
                                ),
                                if (!supportedReasoning.contains(
                                  _selectedReasoningEffort,
                                )) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    copy.aiApiReasoningUnsupported,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: palette.textPrimary.withValues(
                                            alpha: 0.68,
                                          ),
                                          height: 1.35,
                                        ),
                                  ),
                                ],
                                const SizedBox(height: 14),
                                _ApiDropdownField<AiResponseSpeed>(
                                  label: copy.aiApiResponseSpeedLabel,
                                  value: _selectedResponseSpeed,
                                  values: AiResponseSpeed.selectableValues,
                                  itemLabel: copy.aiApiResponseSpeedName,
                                  onChanged: (AiResponseSpeed? value) {
                                    if (value != null) {
                                      setState(
                                        () => _selectedResponseSpeed = value,
                                      );
                                    }
                                  },
                                ),
                                if (_selectedResponseSpeed ==
                                    AiResponseSpeed.fast) ...[
                                  const SizedBox(height: 6),
                                  Tooltip(
                                    message:
                                        copy.aiApiGenerationCompatibilityHint,
                                    child: Text(
                                      copy.aiApiResponseSpeedHint,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: palette.textPrimary
                                                .withValues(alpha: 0.68),
                                            height: 1.35,
                                          ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 14),
                                Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: FilledButton(
                                        onPressed: _isTesting
                                            ? null
                                            : _testAndSaveConfig,
                                        child: Text(copy.aiApiSave),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: _resetDefault,
                                        child: Text(copy.aiApiReset),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                if (_lastTestMessage != null) ...<Widget>[
                                  const SizedBox(height: 10),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: (_lastTestSucceeded ?? false)
                                          ? palette.success.withValues(
                                              alpha: 0.14,
                                            )
                                          : palette.error.withValues(
                                              alpha: 0.14,
                                            ),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: (_lastTestSucceeded ?? false)
                                            ? palette.success.withValues(
                                                alpha: 0.32,
                                              )
                                            : palette.error.withValues(
                                                alpha: 0.32,
                                              ),
                                      ),
                                    ),
                                    child: Text(
                                      _lastTestMessage!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: palette.textPrimary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  if (_lastTestSucceeded == false &&
                                      RegExp(
                                        r'cors|cross.origin|跨域|failed to fetch|xmlhttprequest',
                                        caseSensitive: false,
                                      ).hasMatch(_lastTestMessage!) &&
                                      _isCrossOriginWebUrl(
                                        _urlController.text,
                                      )) ...[
                                    const SizedBox(height: 8),
                                    Tooltip(
                                      message: copy.localized(
                                        '请确认服务商允许浏览器跨域访问，或使用同源代理。',
                                        'Check that your provider allows browser cross-origin requests, or use a same-origin proxy.',
                                      ),
                                      child: Text(
                                        copy.localized(
                                          '跨域访问可能受限 ⓘ',
                                          'Cross-origin access may be restricted ⓘ',
                                        ),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ),
                                  ],
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _SectionTitle(
                        title: copy.appUpdateTitle,
                        icon: Icons.system_update_outlined,
                      ),
                      const SizedBox(height: 10),
                      _SectionCard(
                        palette: palette,
                        child: SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: controller.checkForUpdates,
                          onChanged: controller.setCheckForUpdates,
                          title: Text(copy.checkForUpdatesTitle),
                          subtitle: Text(copy.checkForUpdatesHint),
                          secondary: const Icon(Icons.system_update_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _SectionCard(
                        palette: palette,
                        padding: EdgeInsets.zero,
                        child: ListTile(
                          key: const ValueKey('mobile-settings-about'),
                          leading: Icon(
                            Icons.info_outline_rounded,
                            color: palette.primary,
                          ),
                          title: Text(copy.localized('关于应用', 'About the app')),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: widget.onOpenAbout,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _testAndSaveConfig() async {
    final controller = widget.controller;
    final copy = controller.copy;
    if (_selectedPreset.isCustom) {
      final String providerName = _nameController.text.trim();
      if (providerName.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(copy.aiApiProviderNameRequired)));
        return;
      }
      if (AiApiConfig.isBuiltInProviderName(providerName)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(copy.aiApiProviderNameReserved)));
        return;
      }
    }
    if (_isTesting) {
      return;
    }

    final AiApiConfig draft = _draftConfig();
    setState(() {
      _isTesting = true;
      _lastTestMessage = null;
      _lastTestSucceeded = null;
    });

    List<AiModel>? models;
    Object? modelError;
    try {
      if (draft.baseUrl.trim().isNotEmpty && draft.apiKey.trim().isNotEmpty) {
        models = await _refreshModels(draft);
      } else {
        controller.invalidateAiModels();
      }
    } catch (error) {
      modelError = error;
    }

    // Saving is intentionally independent from model discovery. A provider
    // configuration remains useful even when /models is temporarily blocked,
    // unavailable, or returns an incompatible response.
    final AiApiConfig next = _draftConfig();
    try {
      await controller.saveAiApiConfig(next);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _lastTestMessage = '$error';
        _lastTestSucceeded = false;
        _isTesting = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
      return;
    }
    if (!mounted) {
      return;
    }

    final List<_AiPresetOption> options = _presetOptions(controller);
    final _AiPresetOption savedPreset = _presetForConfig(options, next);
    final String resultMessage;
    final bool succeeded;
    if (models != null && models.isNotEmpty) {
      resultMessage = copy.aiApiModelsSaved(models.length);
      succeeded = true;
    } else if (models != null) {
      resultMessage = copy.aiApiModelsEmpty;
      succeeded = false;
    } else if (modelError != null) {
      final String detail =
          controller.aiModelLoadState == AiModelLoadState.empty
          ? copy.aiApiModelsEmpty
          : controller.aiModelLoadError ?? '$modelError';
      resultMessage = copy.aiApiSavedWithModelFailure(detail);
      succeeded = false;
    } else {
      resultMessage = copy.aiApiSavedWithoutModelDiscovery;
      succeeded = false;
    }
    setState(() {
      _selectedPreset = savedPreset;
      _lastTestMessage = resultMessage;
      _lastTestSucceeded = succeeded;
      _isTesting = false;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(resultMessage)));
  }

  Future<void> _resetDefault() async {
    final _AiPresetOption openAi = _presetOptions(
      widget.controller,
    ).firstWhere((_AiPresetOption option) => option.id == 'builtin:openai');
    _applyPreset(openAi);
    final AiApiConfig next = _draftConfig();
    await widget.controller.saveAiApiConfig(next);
    if (!mounted) {
      return;
    }
    setState(() {
      _lastTestMessage = null;
      _lastTestSucceeded = null;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(widget.controller.copy.aiApiSaved)));
  }

  AiApiConfig _draftConfig() {
    final current = widget.controller.aiApiConfig;
    return current.copyWith(
      name: _selectedPreset.isCustom
          ? _nameController.text.trim()
          : _selectedPreset.config.name,
      baseUrl: _urlController.text.trim(),
      apiKey: _keyController.text.trim(),
      model: _selectedModel ?? '',
      reasoningEffort: _selectedReasoningEffort,
      responseSpeed: _selectedResponseSpeed,
    );
  }

  void _applyPreset(_AiPresetOption? preset) {
    if (preset == null) {
      return;
    }
    final AiApiConfig config = preset.config;
    setState(() {
      _selectedPreset = preset;
      // A new custom preset must start with an empty user-editable name. The
      // internal template label is reserved for display only and would be
      // rejected by the save validation as a built-in provider name.
      _nameController.text = preset.isNewCustom
          ? ''
          : (preset.isCustom ? config.name : '');
      _urlController.text = preset.isNewCustom ? '' : config.baseUrl;
      _keyController.text = preset.isNewCustom ? '' : config.apiKey;
      _selectedModel = preset.isNewCustom || config.model.trim().isEmpty
          ? null
          : config.model.trim();
      _selectedReasoningEffort = config.reasoningEffort;
      _selectedResponseSpeed = config.responseSpeed;
    });
    widget.controller.invalidateAiModels();
  }

  List<_AiPresetOption> _presetOptions(AppController controller) {
    final AppCopy copy = controller.copy;
    return <_AiPresetOption>[
      _AiPresetOption(
        id: 'builtin:openai',
        label: copy.aiProviderPresetName(AiProviderPreset.openAi),
        config: AiApiConfig.defaultOpenAi,
      ),
      _AiPresetOption(
        id: 'builtin:deepseek',
        label: copy.aiProviderPresetName(AiProviderPreset.deepSeek),
        config: AiApiConfig.defaultDeepSeek,
      ),
      ...controller.customAiPresets
          .where(
            (AiApiConfig config) =>
                !AiApiConfig.isBuiltInProviderName(config.name),
          )
          .map(
            (AiApiConfig config) => _AiPresetOption(
              id: 'custom:${config.normalizedName}',
              label: config.name,
              config: config,
            ),
          ),
      _AiPresetOption(
        id: 'custom:new',
        label: copy.aiProviderPresetName(AiProviderPreset.custom),
        config: AiApiConfig.defaultCustom,
        isNewCustom: true,
      ),
    ];
  }

  _AiPresetOption _presetForConfig(
    List<_AiPresetOption> options,
    AiApiConfig config,
  ) {
    final String id = switch (config.providerPreset) {
      AiProviderPreset.openAi => 'builtin:openai',
      AiProviderPreset.deepSeek => 'builtin:deepseek',
      AiProviderPreset.custom =>
        config.normalizedName.isEmpty ||
                AiApiConfig.isBuiltInProviderName(config.name)
            ? 'custom:new'
            : 'custom:${config.normalizedName}',
    };
    return _presetForId(options, id);
  }

  _AiPresetOption _presetForId(List<_AiPresetOption> options, String id) {
    return options.firstWhere(
      (_AiPresetOption option) => option.id == id,
      orElse: () => options.last,
    );
  }

  void _invalidateModels() {
    if (_selectedModel != null) {
      setState(() => _selectedModel = null);
    }
    widget.controller.invalidateAiModels();
  }

  void _handleAiFieldChanged(String _) {
    _invalidateModels();
  }

  bool _isCrossOriginWebUrl(String value) {
    if (!kIsWeb) {
      return false;
    }
    final Uri? endpoint = Uri.tryParse(value.trim());
    if (endpoint == null || !endpoint.hasScheme || endpoint.host.isEmpty) {
      return false;
    }
    final Uri page = Uri.base;
    return endpoint.scheme != page.scheme ||
        endpoint.host != page.host ||
        endpoint.port != page.port;
  }

  Future<List<AiModel>> _refreshModels(AiApiConfig config) async {
    final List<AiModel> models = await widget.controller.refreshAiModels(
      config: config.copyWith(model: ''),
    );
    if (!mounted) {
      return models;
    }
    setState(() {
      // Discovery never deletes an existing selection. The request policy
      // blocks it if it is outside the allowed catalog.
    });
    return models;
  }

  Future<void> _reorderSources(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final next = List<AssetSourceConfig>.from(_assetSourceConfigs);
    final item = next.removeAt(oldIndex);
    next.insert(newIndex, item);
    setState(() {
      _assetSourceConfigs = next;
    });
    await widget.controller.saveAssetSourceConfigs(next);
  }

  Future<void> _testAssets() async {
    setState(() => _isTestingAssets = true);
    try {
      await widget.controller.refreshAssetAccessStatus();
      if (!mounted) {
        return;
      }
      final statuses = widget.controller.assetSourceStatuses;
      final lines = _assetSourceConfigs
          .map((source) {
            final status = statuses[source.id];
            final stateLabel = _stateLabel(
              status?.state,
              widget.controller.copy,
            );
            return '${source.name}: $stateLabel${status == null ? '' : ' · ${status.message}'}';
          })
          .join('\n');
      final hasFailure = _assetSourceConfigs.any((source) {
        final status = statuses[source.id];
        return status == null || status.state == ConnectivityState.failure;
      });
      final hasSuccess = _assetSourceConfigs.any((source) {
        final status = statuses[source.id];
        return status?.state == ConnectivityState.success;
      });
      showDialog<void>(
        context: context,
        builder: (context) {
          final palette = AppPalette.of(context);
          return AlertDialog(
            title: Text(widget.controller.copy.assetStatusDialogTitle),
            content: Text(
              lines,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: palette.textPrimary.withValues(alpha: 0.88),
                height: 1.5,
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(widget.controller.copy.dialogClose),
              ),
            ],
          );
        },
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.controller.copy.assetTestDone),
          backgroundColor: hasFailure
              ? (hasSuccess
                    ? AppPalette.of(context).warning
                    : AppPalette.of(context).error)
              : AppPalette.of(context).success,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isTestingAssets = false);
      }
    }
  }

  String _stateLabel(ConnectivityState? state, AppCopy copy) {
    if (state == null) {
      return copy.localized('未检测', 'Not checked');
    }
    if (state == ConnectivityState.success) {
      return copy.localized('成功', 'Available');
    }
    if (state == ConnectivityState.failure) {
      return copy.localized('失败', 'Failed');
    }
    if (state == ConnectivityState.warning) {
      return copy.localized('受限', 'Limited');
    }
    if (state == ConnectivityState.loading) {
      return copy.localized('加载中', 'Checking');
    }
    return copy.localized('未检测', 'Not checked');
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: palette.primary),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.palette,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final AppPalette palette;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(UiTokens.groupRadius),
        border: Border.all(color: palette.outline),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: 0.035),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({
    required this.palette,
    required this.title,
    required this.swatch,
    required this.selected,
    required this.onTap,
  });

  final AppPalette palette;
  final String title;
  final Color swatch;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: title,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          height: 90,
          decoration: BoxDecoration(
            color: selected
                ? palette.primaryContainer.withValues(alpha: 0.45)
                : palette.surfaceVariant,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? palette.primary : palette.outline,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: swatch,
                  shape: BoxShape.circle,
                ),
                child: selected
                    ? Icon(
                        Icons.check_rounded,
                        size: 17,
                        color: palette.onPrimary,
                      )
                    : null,
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Text(
                  title,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AiPresetOption {
  const _AiPresetOption({
    required this.id,
    required this.label,
    required this.config,
    this.isNewCustom = false,
  });

  final String id;
  final String label;
  final AiApiConfig config;
  final bool isNewCustom;

  bool get isCustom =>
      isNewCustom || config.providerPreset == AiProviderPreset.custom;

  @override
  bool operator ==(Object other) {
    return other is _AiPresetOption && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

class _ModelDiscoveryPanel extends StatelessWidget {
  const _ModelDiscoveryPanel({
    required this.controller,
    required this.selectedModel,
    required this.onChanged,
  });

  final AppController controller;
  final String? selectedModel;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppCopy copy = controller.copy;
    final AppPalette palette = AppPalette.of(context);
    final List<AiModel> models = controller.availableAiModels;
    final String? validSelection =
        models.any((AiModel model) => model.id == selectedModel)
        ? selectedModel
        : null;

    Widget status = const SizedBox.shrink();
    switch (controller.aiModelLoadState) {
      case AiModelLoadState.idle:
        status = Text(
          copy.aiApiModelsNotLoaded,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: palette.textPrimary.withValues(alpha: 0.68),
          ),
        );
      case AiModelLoadState.loading:
        status = Row(
          children: <Widget>[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(copy.aiApiModelsLoading),
          ],
        );
      case AiModelLoadState.success:
        break;
      case AiModelLoadState.empty:
        status = Text(
          copy.aiApiModelsEmpty,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: palette.warning),
        );
      case AiModelLoadState.failure:
        status = Text(
          '${copy.aiApiModelsFailed}: ${controller.aiModelLoadError ?? ''}',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: palette.error),
        );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          copy.aiApiModelLabel,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: palette.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (models.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            key: ValueKey<String?>(validSelection),
            initialValue: validSelection,
            isExpanded: true,
            onChanged: onChanged,
            items: models
                .map(
                  (AiModel model) => DropdownMenuItem<String>(
                    value: model.id,
                    child: Text(model.label, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(growable: false),
            decoration: _settingsInputDecoration(
              context,
              hintText: copy.aiApiModelSelectHint,
            ),
          ),
        ],
        const SizedBox(height: 6),
        if (selectedModel != null && !AiModelPolicy.allowsModel(selectedModel!))
          Text(
            copy.aiApiModelNotAllowed,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.warning),
          ),
        status,
      ],
    );
  }
}

class _ApiField extends StatelessWidget {
  const _ApiField({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.obscureText = false,
    this.readOnly = false,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool readOnly;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          readOnly: readOnly,
          onChanged: onChanged,
          decoration: _settingsInputDecoration(context),
        ),
      ],
    );
  }
}

class _ApiDropdownField<T> extends StatelessWidget {
  const _ApiDropdownField({
    required this.label,
    this.placeholder,
    required this.value,
    required this.values,
    required this.itemLabel,
    required this.onChanged,
  });

  final String label;
  final String? placeholder;
  final T value;
  final List<T> values;
  final String Function(T value) itemLabel;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        InputDecorator(
          decoration: _settingsInputDecoration(context),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: values.contains(value) ? value : null,
              hint: Text(placeholder ?? label),
              isExpanded: true,
              onChanged: onChanged,
              items: values
                  .map(
                    (item) => DropdownMenuItem<T>(
                      value: item,
                      child: Text(
                        itemLabel(item),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ),
      ],
    );
  }
}

InputDecoration _settingsInputDecoration(
  BuildContext context, {
  String? hintText,
}) {
  final palette = AppPalette.of(context);
  return InputDecoration(
    hintText: hintText,
    filled: true,
    fillColor: palette.inputSurface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: palette.outline),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: palette.outline),
    ),
  );
}
