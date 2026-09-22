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
