import 'package:app_about/app_about.dart';
import 'package:app_ai_client/app_ai_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/ai_api_config.dart';
import '../../models/asset_source_config.dart';
import '../../models/app_language.dart';
import '../../models/connectivity_status.dart';
import '../../models/color_scheme_option.dart';
import '../../state/app_controller.dart';
import '../../theme/app_palette.dart';
import '../app_copy.dart';

class LanguageSheet extends StatefulWidget {
  const LanguageSheet({
    super.key,
    required this.controller,
    required this.onOpenAbout,
  });

  final AppController controller;
  final VoidCallback onOpenAbout;

  @override
  State<LanguageSheet> createState() => _LanguageSheetState();
}

class _LanguageSheetState extends State<LanguageSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _keyController;
  late List<AssetSourceConfig> _assetSourceConfigs;
  late _AiPresetOption _selectedPreset;
  String? _selectedModel;
  AiReasoningEffort _selectedReasoningEffort = AiReasoningEffort.automatic;
  AiResponseSpeed _selectedResponseSpeed = AiResponseSpeed.automatic;
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
        final List<_AiPresetOption> presetOptions = _presetOptions(controller);
        final _AiPresetOption selectedPreset = _presetForId(
          presetOptions,
          _selectedPreset.id,
        );
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.88,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: palette.textPrimary.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _SectionTitle(title: copy.languageTitle),
                  const SizedBox(height: 12),
                  _SectionCard(
                    palette: palette,
                    child: Column(
                      children: <Widget>[
                        _ChoiceTile(
                          palette: palette,
                          title: '简体中文',
                          subtitle: '默认语言，适合这版首发原型',
                          selected: controller.language == AppLanguage.zhHans,
                          onTap: () =>
                              controller.setLanguage(AppLanguage.zhHans),
                        ),
                        const SizedBox(height: 12),
                        _ChoiceTile(
                          palette: palette,
                          title: 'English',
                          subtitle:
                              'Useful for demos, sharing, and API testing later',
                          selected: controller.language == AppLanguage.en,
                          onTap: () => controller.setLanguage(AppLanguage.en),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _SectionTitle(title: copy.colorSchemeTitle),
                  const SizedBox(height: 8),
                  Text(
                    copy.colorSchemeHint,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    palette: palette,
                    child: Column(
                      children: <Widget>[
                        _ChoiceTile(
                          palette: palette,
                          title: copy.colorSchemeName(
                            ColorSchemeOption.classic,
                          ),
                          selected:
                              controller.colorScheme ==
                              ColorSchemeOption.classic,
                          onTap: () => controller.setColorScheme(
                            ColorSchemeOption.classic,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _ChoiceTile(
                          palette: palette,
                          title: copy.colorSchemeName(
                            ColorSchemeOption.sunsetCoast,
                          ),
                          selected:
                              controller.colorScheme ==
                              ColorSchemeOption.sunsetCoast,
                          onTap: () => controller.setColorScheme(
                            ColorSchemeOption.sunsetCoast,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _ChoiceTile(
                          palette: palette,
                          title: copy.colorSchemeName(
                            ColorSchemeOption.warmwoodStudy,
                          ),
                          selected:
                              controller.colorScheme ==
                              ColorSchemeOption.warmwoodStudy,
                          onTap: () => controller.setColorScheme(
                            ColorSchemeOption.warmwoodStudy,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _SectionTitle(title: copy.assetPriorityTitle),
                  const SizedBox(height: 8),
                  Text(
                    copy.assetPriorityHint,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: palette.textPrimary.withValues(alpha: 0.72),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    palette: palette,
                    child: Column(
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
                                color: palette.surface,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                leading: CircleAvatar(
                                  backgroundColor: palette.primary.withValues(
                                    alpha: 0.16,
                                  ),
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
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: palette.textPrimary.withValues(
                                          alpha: 0.72,
                                        ),
                                      ),
                                ),
                                trailing: ReorderableDragStartListener(
                                  index: index,
                                  child: Icon(
                                    Icons.drag_handle_rounded,
                                    color: palette.textPrimary.withValues(
                                      alpha: 0.72,
                                    ),
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
                            onPressed: _isTestingAssets ? null : _testAssets,
                            child: Text(
                              _isTestingAssets ? '...' : copy.assetTest,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _SectionTitle(title: copy.aiApiTitle),
                  const SizedBox(height: 12),
                  _SectionCard(
                    palette: palette,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _ApiDropdownField<_AiPresetOption>(
                          label: copy.aiApiPresetLabel,
                          value: selectedPreset,
                          values: presetOptions,
                          itemLabel: (_AiPresetOption option) => option.label,
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
                        if (_isCrossOriginWebUrl(
                          _urlController.text,
                        )) ...<Widget>[
                          const SizedBox(height: 8),
                          Text(
                            copy.aiApiWebCorsHint,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: palette.textPrimary.withValues(
                                    alpha: 0.72,
                                  ),
                                  height: 1.35,
                                ),
                          ),
                        ],
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
                            setState(() => _selectedModel = model);
                          },
                        ),
                        const SizedBox(height: 14),
                        _ApiDropdownField<AiReasoningEffort>(
                          label: copy.aiApiReasoningEffortLabel,
                          value: _selectedReasoningEffort,
                          values: AiReasoningEffort.values,
                          itemLabel: copy.aiApiReasoningEffortName,
                          onChanged: (AiReasoningEffort? value) {
                            if (value != null) {
                              setState(() => _selectedReasoningEffort = value);
                            }
                          },
                        ),
                        const SizedBox(height: 6),
                        Text(
                          copy.aiApiReasoningEffortHint,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: palette.textPrimary.withValues(
                                  alpha: 0.68,
                                ),
                                height: 1.35,
                              ),
                        ),
                        const SizedBox(height: 14),
                        _ApiDropdownField<AiResponseSpeed>(
                          label: copy.aiApiResponseSpeedLabel,
                          value: _selectedResponseSpeed,
                          values: AiResponseSpeed.values,
                          itemLabel: copy.aiApiResponseSpeedName,
                          onChanged: (AiResponseSpeed? value) {
                            if (value != null) {
                              setState(() => _selectedResponseSpeed = value);
                            }
                          },
                        ),
                        const SizedBox(height: 6),
                        Text(
                          copy.aiApiResponseSpeedHint,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: palette.textPrimary.withValues(
                                  alpha: 0.68,
                                ),
                                height: 1.35,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          copy.aiApiGenerationCompatibilityHint,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: palette.warning, height: 1.35),
                        ),
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
                                  ? palette.success.withValues(alpha: 0.14)
                                  : palette.error.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: (_lastTestSucceeded ?? false)
                                    ? palette.success.withValues(alpha: 0.32)
                                    : palette.error.withValues(alpha: 0.32),
                              ),
                            ),
                            child: Text(
                              _lastTestMessage!,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: palette.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _SectionTitle(title: copy.appUpdateTitle),
                  const SizedBox(height: 12),
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
                  AppAboutSettingsTile(onTap: widget.onOpenAbout),
                ],
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
    if (models != null) {
      resultMessage = copy.aiApiModelsSaved(models.length);
      succeeded = true;
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
      if (_selectedModel != null &&
          models.every((AiModel model) => model.id != _selectedModel)) {
        _selectedModel = null;
      }
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
            final stateLabel = _stateLabel(status?.state);
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

  String _stateLabel(ConnectivityState? state) {
    if (state == null) {
      return '未检测';
    }
    if (state == ConnectivityState.success) {
      return '成功';
    }
    if (state == ConnectivityState.failure) {
      return '失败';
    }
    if (state == ConnectivityState.warning) {
      return '受限';
    }
    if (state == ConnectivityState.loading) {
      return '加载中';
    }
    return '未检测';
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: Theme.of(context).textTheme.titleLarge);
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.palette, required this.child});

  final AppPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.outline),
      ),
      child: child,
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.palette,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final AppPalette palette;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color selectedBackground = selected
        ? palette.primaryContainer
        : palette.surface;
    final Color selectedForeground = selected
        ? palette.onPrimaryContainer
        : palette.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: selectedBackground,
          border: Border.all(
            color: selected ? palette.primary : palette.outline,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: selected
                          ? selectedForeground
                          : palette.textPrimary,
                    ),
                  ),
                  if (subtitle case final subtitle?) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: selected
                            ? selectedForeground.withValues(alpha: 0.84)
                            : palette.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? palette.primary : palette.textSecondary,
            ),
          ],
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
        status = Text(
          copy.aiApiModelsLoaded(models.length),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: palette.textPrimary.withValues(alpha: 0.68),
          ),
        );
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
            decoration: InputDecoration(hintText: copy.aiApiModelSelectHint),
          ),
        ],
        const SizedBox(height: 6),
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
          decoration: const InputDecoration(),
        ),
      ],
    );
  }
}

class _ApiDropdownField<T> extends StatelessWidget {
  const _ApiDropdownField({
    required this.label,
    required this.value,
    required this.values,
    required this.itemLabel,
    required this.onChanged,
  });

  final String label;
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
          decoration: const InputDecoration(),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
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
