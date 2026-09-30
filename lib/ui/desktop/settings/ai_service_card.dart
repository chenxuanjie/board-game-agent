part of '../settings_pane.dart';

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
    required this.checkStep,
    required this.reasoningEffort,
    required this.responseSpeed,
    required this.feedback,
    required this.feedbackSucceeded,
    required this.onProviderChanged,
    required this.onAiFieldChanged,
    required this.onModelChanged,
    required this.onReasoningChanged,
    required this.onSpeedChanged,
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
  final DesktopAiCheckStep? checkStep;
  final AiReasoningEffort reasoningEffort;
  final AiResponseSpeed responseSpeed;
  final String? feedback;
  final bool? feedbackSucceeded;
  final ValueChanged<String?> onProviderChanged;
  final ValueChanged<String> onAiFieldChanged;
  final ValueChanged<String?> onModelChanged;
  final ValueChanged<AiReasoningEffort> onReasoningChanged;
  final ValueChanged<AiResponseSpeed> onSpeedChanged;
  final VoidCallback onToggleApiKey;
  final VoidCallback onSaveAndCheck;

  @override
  Widget build(BuildContext context) {
    final AppCopy copy = controller.copy;
    final bool hasKey = apiKeyController.text.trim().isNotEmpty;
    final List<AiReasoningEffort> supportedEfforts =
        AiModelPolicy.reasoningEfforts(modelController.text) ??
        const <AiReasoningEffort>[AiReasoningEffort.automatic];
    final List<AiReasoningEffort> visibleEfforts = <AiReasoningEffort>[
      if (!supportedEfforts.contains(reasoningEffort)) reasoningEffort,
      ...supportedEfforts,
    ];
    final AiApiConfig savedConfig = controller.aiApiConfig;
    final bool draftChanged =
        providerController.text.trim() != savedConfig.name.trim() ||
        modelController.text.trim() != savedConfig.model.trim() ||
        apiKeyController.text.trim() != savedConfig.apiKey.trim() ||
        baseUrlController.text.trim() != savedConfig.baseUrl.trim() ||
        reasoningEffort != savedConfig.reasoningEffort ||
        responseSpeed != savedConfig.responseSpeed;

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
          Row(
            children: <Widget>[
              Expanded(
                child: _AiOptionDropdownField<AiReasoningEffort>(
                  fieldKey: const ValueKey<String>(
                    'desktop-settings-ai-reasoning',
                  ),
                  label: copy.aiApiReasoningEffortLabel,
                  value: reasoningEffort,
                  values: visibleEfforts,
                  itemLabel: copy.aiApiReasoningEffortName,
                  enabled: !saving,
                  onChanged: (AiReasoningEffort? value) {
                    if (value != null) onReasoningChanged(value);
                  },
                ),
              ),
              SizedBox(width: _px(context, 9)),
              Expanded(
                child: _AiOptionDropdownField<AiResponseSpeed>(
                  fieldKey: const ValueKey<String>('desktop-settings-ai-speed'),
                  label: copy.aiApiResponseSpeedLabel,
                  value: responseSpeed,
                  values: AiResponseSpeed.values,
                  itemLabel: copy.aiApiResponseSpeedName,
                  enabled: !saving,
                  onChanged: (AiResponseSpeed? value) {
                    if (value != null) onSpeedChanged(value);
                  },
                ),
              ),
            ],
          ),
          SizedBox(height: _px(context, 10)),
          _AiStatusLabel(
            status: controller.aiConnectivityStatus,
            hasKey: hasKey,
            copy: copy,
            saving: saving,
            checkStep: checkStep,
            draftChanged: draftChanged,
            feedback: feedback,
            feedbackSucceeded: feedbackSucceeded,
            fastSelected: responseSpeed == AiResponseSpeed.fast,
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
        ],
      ),
    );
  }
}

class _AiOptionDropdownField<T> extends StatelessWidget {
  const _AiOptionDropdownField({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.values,
    required this.itemLabel,
    required this.enabled,
    required this.onChanged,
  });

  final Key fieldKey;
  final String label;
  final T value;
  final List<T> values;
  final String Function(T) itemLabel;
  final bool enabled;
  final ValueChanged<T?> onChanged;

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
          child: Theme(
            data: _dropdownTheme(context),
            child: DropdownButtonFormField<T>(
              key: ValueKey<T>(value),
              initialValue: value,
              isExpanded: true,
              borderRadius: BorderRadius.circular(_px(context, 12)),
              dropdownColor: DesktopColors.card,
              icon: Icon(Icons.expand_more_rounded, size: _px(context, 18)),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
              items: values
                  .map(
                    (T option) => DropdownMenuItem<T>(
                      value: option,
                      child: _dropdownOption(
                        context,
                        itemLabel(option),
                        selected: option == value,
                      ),
                    ),
                  )
                  .toList(growable: false),
              selectedItemBuilder: (context) => <Widget>[
                for (final option in values)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      itemLabel(option),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ),
      ),
    ],
  );
}

class _AiStatusLabel extends StatelessWidget {
  const _AiStatusLabel({
    required this.status,
    required this.hasKey,
    required this.copy,
    required this.saving,
    required this.checkStep,
    required this.draftChanged,
    required this.feedback,
    required this.feedbackSucceeded,
    required this.fastSelected,
  });

  final ConnectivityStatus status;
  final bool hasKey;
  final AppCopy copy;
  final bool saving;
  final DesktopAiCheckStep? checkStep;
  final bool draftChanged;
  final String? feedback;
  final bool? feedbackSucceeded;
  final bool fastSelected;

  @override
  Widget build(BuildContext context) {
    final String message;
    final Color color;
    if (saving) {
      message = switch (checkStep) {
        DesktopAiCheckStep.saving => copy.localized(
          '正在保存配置…',
          'Saving configuration…',
        ),
        DesktopAiCheckStep.loadingModels => copy.localized(
          '正在获取 /models（最长 15 秒）…',
          'Fetching /models (up to 15 s)…',
        ),
        DesktopAiCheckStep.probingChat => copy.localized(
          '正在探测 Chat Completions（最长 20 秒；不验证强度与 Fast）…',
          'Probing Chat Completions (up to 20 s; effort and Fast unverified)…',
        ),
        null => copy.localized('正在检测…', 'Checking…'),
      };
      color = DesktopColors.brown;
    } else if (feedback != null) {
      final bool success = feedbackSucceeded == true;
      final String label = success
          ? status.state == ConnectivityState.warning
                ? copy.localized('待选模型', 'Select a model')
                : copy.localized('连接正常', 'Connection ready')
          : copy.localized('检测失败', 'Check failed');
      message = '$label：$feedback';
      color = success
          ? status.state == ConnectivityState.warning
                ? const Color(0xFF945D31)
                : const Color(0xFF497461)
          : const Color(0xFF9F4D5D);
    } else if (draftChanged) {
      message = copy.localized(
        '配置已修改，请保存并检测',
        'Changes pending; save and check',
      );
      color = DesktopColors.brown;
    } else if (!hasKey) {
      message = copy.localized('未配置', 'Not configured');
      color = DesktopColors.secondaryText;
    } else {
      switch (status.state) {
        case ConnectivityState.success:
          message =
              '${copy.localized('连接正常', 'Connection ready')}：${status.message}';
          color = const Color(0xFF497461);
        case ConnectivityState.loading:
          message = status.message;
          color = DesktopColors.brown;
        case ConnectivityState.warning:
          message = status.message;
          color = const Color(0xFF945D31);
        case ConnectivityState.failure:
          message = status.message;
          color = const Color(0xFF9F4D5D);
        case ConnectivityState.unknown:
          message = copy.localized('尚未检测', 'Not checked');
          color = DesktopColors.secondaryText;
      }
    }
    final String fastNote = copy.localized(
      'Fast 可能额外计费，是否生效由服务商决定。',
      'Fast may cost more; availability depends on the provider.',
    );
    final String fullMessage =
        '${copy.localized('AI 服务', 'AI Service')} · $message'
        '${fastSelected && !saving ? ' $fastNote' : ''}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          margin: EdgeInsets.only(top: _px(context, 5)),
          width: _px(context, 7),
          height: _px(context, 7),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: _px(context, 6)),
        Flexible(
          child: Text(
            fullMessage,
            key: const ValueKey<String>('desktop-settings-ai-status'),
            style: TextStyle(
              fontSize: _font(context, 11),
              height: 1.3,
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
          child: Theme(
            data: _dropdownTheme(context),
            child: DropdownButtonFormField<String>(
              key: ValueKey<String>('provider-$selectedId'),
              initialValue: selectedId,
              isExpanded: true,
              borderRadius: BorderRadius.circular(_px(context, 12)),
              dropdownColor: DesktopColors.card,
              icon: Icon(Icons.expand_more_rounded, size: _px(context, 18)),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
                    (_DesktopAiProviderOption option) =>
                        DropdownMenuItem<String>(
                          value: option.id,
                          child: _dropdownOption(
                            context,
                            option.label,
                            selected: option.id == selectedId,
                          ),
                        ),
                  )
                  .toList(growable: false),
              selectedItemBuilder: (context) => <Widget>[
                for (final option in options)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(option.label, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: enabled ? onChanged : null,
            ),
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
            child: Theme(
              data: _dropdownTheme(context),
              child: DropdownButtonFormField<String>(
                key: ValueKey<String>(
                  'model-${loadState.name}-$normalizedSelection-${models.length}',
                ),
                initialValue: selectionAvailable ? normalizedSelection : null,
                isExpanded: true,
                borderRadius: BorderRadius.circular(_px(context, 12)),
                dropdownColor: DesktopColors.card,
                hint: Text(hint, overflow: TextOverflow.ellipsis),
                icon: loadState == AiModelLoadState.loading
                    ? SizedBox.square(
                        dimension: _px(context, 14),
                        child: CircularProgressIndicator(
                          strokeWidth: _px(context, 1.6),
                        ),
                      )
                    : Icon(Icons.expand_more_rounded, size: _px(context, 18)),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
                        child: _dropdownOption(
                          context,
                          model.label,
                          selected: model.id == normalizedSelection,
                        ),
                      ),
                    )
                    .toList(growable: false),
                selectedItemBuilder: (context) => <Widget>[
                  for (final model in models)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(model.label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: enabled && models.isNotEmpty ? onChanged : null,
              ),
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
