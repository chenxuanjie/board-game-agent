import 'dart:async';
import 'dart:math' as math;

import 'package:app_ai_client/app_ai_client.dart';
import 'package:flutter/material.dart';

import '../../../app/state/app_controller.dart';
import '../../../core/localization/app_copy.dart';
import '../../../core/theme/app_palette.dart';
import '../../../features/assistant/models/ai_api_config.dart';
import '../../../features/assistant/models/ai_model_policy.dart';
import '../../../core/theme/app_motion.dart';

class AssistantModelSelector extends StatefulWidget {
  const AssistantModelSelector({
    super.key,
    required this.controller,
    required this.enabled,
  });

  final AppController controller;
  final bool enabled;

  @override
  State<AssistantModelSelector> createState() => _AssistantModelSelectorState();
}

class _AssistantModelSelectorState extends State<AssistantModelSelector> {
  bool _open = false;
  bool _hovered = false;
  bool _focused = false;

  Future<void> _showPicker() async {
    if (!widget.enabled || _open) return;
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final Rect trigger = box.localToGlobal(Offset.zero) & box.size;
    setState(() => _open = true);
    try {
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: widget.controller.copy.localized(
          '关闭模型选择',
          'Close model picker',
        ),
        barrierColor: Colors.black.withValues(alpha: 0.12),
        transitionDuration: AppMotion.duration(context, AppMotion.menu),
        pageBuilder: (BuildContext context, _, _) =>
            _AssistantModelPickerPanel(controller: widget.controller),
        transitionBuilder: (context, animation, _, child) => LayoutBuilder(
          builder: (context, constraints) {
            // Recompute on window resize and keyboard changes. The anchor can
            // move with the composer while this route remains open.
            final media = MediaQuery.of(context);
            final viewport = constraints.biggest;
            final anchor = box.attached && box.hasSize
                ? box.localToGlobal(Offset.zero) & box.size
                : trigger;
            final safeTop = media.padding.top + 8;
            final safeBottom = math.max(
              safeTop + 120,
              viewport.height -
                  math.max(media.viewInsets.bottom, media.padding.bottom) -
                  8,
            );
            final width = math.min(390.0, math.max(120.0, viewport.width - 24));
            const desiredHeight = 430.0;
            final above = math.max(0.0, anchor.top - safeTop - 8);
            final below = math.max(0.0, safeBottom - anchor.bottom - 8);
            final openAbove = above >= desiredHeight || above >= below;
            final available = openAbove ? above : below;
            final height = math.min(
              desiredHeight,
              math.min(safeBottom - safeTop, math.max(160.0, available)),
            );
            final left = (anchor.right - width)
                .clamp(12.0, math.max(12.0, viewport.width - width - 12))
                .toDouble();
            final edge = (openAbove ? anchor.top - 8 : anchor.bottom + 8)
                .clamp(
                  safeTop + (openAbove ? height : 0),
                  safeBottom - (openAbove ? 0 : height),
                )
                .toDouble();
            final Animation<double> curved = CurvedAnimation(
              parent: animation,
              curve: AppMotion.curve,
              reverseCurve: AppMotion.exitCurve,
            );
            return Stack(
              children: <Widget>[
                Positioned(
                  left: left,
                  top: openAbove ? null : edge,
                  bottom: openAbove ? viewport.height - edge : null,
                  width: width,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: height),
                    child: FadeTransition(
                      opacity: curved,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: Offset(0, (openAbove ? 6 : -6) / height),
                          end: Offset.zero,
                        ).animate(curved),
                        child: child,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      if (mounted) setState(() => _open = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final AppCopy copy = widget.controller.copy;
    final String model = widget.controller.aiApiConfig.model.trim();
    final AiReasoningEffort effort =
        widget.controller.aiApiConfig.reasoningEffort;
    final String modelLabel = AiModelPolicy.allowsModel(model)
        ? _modelLabel(widget.controller, model)
        : copy.desktopModel;
    final String effortLabel =
        AiModelPolicy.selectableReasoningEfforts(model)?.contains(effort) ==
            true
        ? copy.aiApiReasoningEffortName(effort)
        : copy.aiApiReasoningEffortLabel;
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label:
          '${copy.desktopModel}: $modelLabel, '
          '${copy.aiApiReasoningEffortLabel}: $effortLabel',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey<String>('desktop-model-selector'),
          onTap: widget.enabled ? _showPicker : null,
          onHover: (bool value) => setState(() => _hovered = value),
          onFocusChange: (bool value) => setState(() => _focused = value),
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: AppMotion.duration(context),
            curve: AppMotion.curve,
            constraints: const BoxConstraints(maxWidth: 310, minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: _open || _hovered || _focused
                  ? palette.primaryContainer.withValues(alpha: 0.45)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _open || _focused
                    ? palette.primary.withValues(alpha: 0.5)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Flexible(
                  child: Text(
                    modelLabel,
                    maxLines: 2,
                    overflow: TextOverflow.clip,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 14,
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: AppMotion.duration(context),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AssistantModelPickerPanel extends StatefulWidget {
  const _AssistantModelPickerPanel({required this.controller});

  final AppController controller;

  @override
  State<_AssistantModelPickerPanel> createState() =>
      _AssistantModelPickerPanelState();
}

class _AssistantModelPickerPanelState
    extends State<_AssistantModelPickerPanel> {
  final TextEditingController _search = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.controller.availableAiModels.isEmpty &&
        widget.controller.aiApiConfig.apiKey.trim().isNotEmpty &&
        widget.controller.aiApiConfig.baseUrl.trim().isNotEmpty &&
        widget.controller.aiModelLoadState != AiModelLoadState.loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_refreshModels());
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refreshModels() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.refreshAiModels();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = widget.controller.copy.localized(
            '模型获取失败，请重试。',
            'Could not load models. Try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _selectModel(String model) async {
    if (_busy) return;
    if (model == widget.controller.aiApiConfig.model.trim()) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.setAiModel(model);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = widget.controller.copy.localized(
            '切换模型失败，请重试。',
            'Could not switch models. Try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _selectEffort(AiReasoningEffort effort) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.setAiReasoningEffort(effort);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = widget.controller.copy.localized(
            '保存推理强度失败，请重试。',
            'Could not save reasoning effort. Try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final copy = widget.controller.copy;
    final canRefresh =
        widget.controller.aiApiConfig.apiKey.trim().isNotEmpty &&
        widget.controller.aiApiConfig.baseUrl.trim().isNotEmpty;
    return Material(
      key: const ValueKey('desktop-model-picker-panel'),
      color: palette.surface,
      elevation: 14,
      shadowColor: palette.shadow.withValues(alpha: .22),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      copy.localized('模型与推理', 'Model & reasoning'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: copy.desktopRefreshModels,
                    onPressed: _busy || !canRefresh ? null : _refreshModels,
                    icon: const Icon(Icons.refresh_rounded, size: 19),
                  ),
                  IconButton(
                    tooltip: copy.localized('关闭', 'Close'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 19),
                  ),
                ],
              ),
            ),
            if (_busy ||
                widget.controller.aiModelLoadState == AiModelLoadState.loading)
              LinearProgressIndicator(
                minHeight: 2,
                color: palette.primary,
                backgroundColor: palette.surfaceContainer,
              )
            else
              const SizedBox(height: 2),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Text(
                  _error!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: palette.error),
                ),
              ),
            Flexible(
              fit: FlexFit.loose,
              child: AbsorbPointer(
                absorbing: _busy,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final hasOptions = AiModelPolicy.allowsModel(
                      widget.controller.aiApiConfig.model,
                    );
                    if (constraints.maxHeight < 280 ||
                        MediaQuery.textScalerOf(context).scale(14) > 17) {
                      return SingleChildScrollView(
                        key: const ValueKey('assistant-model-picker-scroll'),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _modelPage(context),
                            if (hasOptions) _options(context),
                          ],
                        ),
                      );
                    }
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Flexible(
                          fit: FlexFit.loose,
                          child: _modelPage(context),
                        ),
                        if (hasOptions) _options(context),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _options(BuildContext context) {
    final copy = widget.controller.copy;
    final palette = AppPalette.of(context);
    final efforts = AiModelPolicy.selectableReasoningEfforts(
      widget.controller.aiApiConfig.model,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            copy.aiApiReasoningEffortLabel,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: 7),
          if (efforts == null)
            Text(
              copy.aiApiReasoningUnsupported,
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final effort in efforts)
                  _effortOption(
                    context,
                    effort,
                    effort == widget.controller.aiApiConfig.reasoningEffort,
                  ),
              ],
            ),
          const SizedBox(height: 12),
          Text(
            copy.aiApiResponseSpeedLabel,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tier in AiResponseSpeed.selectableValues)
                ChoiceChip(
                  key: ValueKey('assistant-service-tier-${tier.name}'),
                  label: Text(copy.aiApiResponseSpeedName(tier)),
                  selected: widget.controller.aiApiConfig.responseSpeed == tier,
                  onSelected: (_) => _selectTier(tier),
                ),
            ],
          ),
          if (widget.controller.aiApiConfig.responseSpeed ==
              AiResponseSpeed.fast) ...[
            const SizedBox(height: 6),
            Text(
              copy.aiApiResponseSpeedHint,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _selectTier(AiResponseSpeed tier) async {
    if (_busy || widget.controller.aiApiConfig.responseSpeed == tier) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.saveAiApiConfig(
        widget.controller.aiApiConfig.copyWith(responseSpeed: tier),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = widget.controller.copy.localized(
            '保存服务等级失败，请重试。',
            'Could not save the service tier. Try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _modelPage(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final AppCopy copy = widget.controller.copy;
    final String selected = widget.controller.aiApiConfig.model.trim();
    final List<String> all = <String>[
      if (AiModelPolicy.allowsModel(selected)) selected,
      for (final AiModel model in widget.controller.availableAiModels)
        if (model.id.isNotEmpty && model.id != selected) model.id,
    ];
    final String query = _search.text.trim().toLowerCase();
    final List<String> visible = all
        .where(
          (String id) =>
              id.toLowerCase().contains(query) ||
              _modelLabel(widget.controller, id).toLowerCase().contains(query),
        )
        .toList(growable: false);
    return Column(
      key: const ValueKey<String>('desktop-model-picker-model-page'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (all.length > 6 || query.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 9),
            child: SizedBox(
              height: 38,
              child: TextField(
                key: const ValueKey<String>('desktop-model-picker-search'),
                controller: _search,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                style: Theme.of(context).textTheme.bodySmall,
                decoration: InputDecoration(
                  hintText: copy.localized('搜索模型', 'Search models'),
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: copy.localized('清除搜索', 'Clear search'),
                          onPressed: () => setState(_search.clear),
                          icon: const Icon(Icons.close_rounded, size: 16),
                        ),
                  filled: true,
                  fillColor: palette.inputSurface,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 9),
                ),
              ),
            ),
          ),
        Flexible(
          fit: FlexFit.loose,
          child: visible.isEmpty
              ? Center(
                  heightFactor: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          query.isNotEmpty
                              ? copy.localized('没有匹配的模型', 'No matching models')
                              : widget.controller.aiApiConfig.apiKey
                                    .trim()
                                    .isEmpty
                              ? copy.localized(
                                  '请先在设置中配置 AI 服务',
                                  'Configure the AI service in Settings',
                                )
                              : widget.controller.aiModelLoadState ==
                                    AiModelLoadState.loading
                              ? copy.aiApiModelsLoading
                              : widget.controller.aiModelLoadState ==
                                    AiModelLoadState.failure
                              ? copy.aiApiModelsFailed
                              : copy.localized('暂无可用模型', 'No models available'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: palette.textSecondary),
                        ),
                        if (query.isEmpty &&
                            widget.controller.aiApiConfig.apiKey
                                .trim()
                                .isNotEmpty) ...<Widget>[
                          const SizedBox(height: 8),
                          TextButton.icon(
                            key: const ValueKey<String>(
                              'desktop-model-picker-retry',
                            ),
                            onPressed: _busy ? null : _refreshModels,
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: Text(copy.localized('重新获取', 'Retry')),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  key: const ValueKey<String>('desktop-model-picker-list'),
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final String id = visible[index];
                    final bool chosen = id == selected;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          key: ValueKey<String>('desktop-model-option-$id'),
                          onTap: () => _selectModel(id),
                          borderRadius: BorderRadius.circular(10),
                          child: AnimatedContainer(
                            duration: AppMotion.duration(context),
                            curve: AppMotion.curve,
                            constraints: const BoxConstraints(minHeight: 43),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: chosen
                                  ? palette.primaryContainer.withValues(
                                      alpha: 0.65,
                                    )
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    _modelLabel(widget.controller, id),
                                    maxLines: 2,
                                    overflow: TextOverflow.clip,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: chosen
                                              ? palette.primary
                                              : palette.textPrimary,
                                          fontWeight: chosen
                                              ? FontWeight.w600
                                              : FontWeight.w500,
                                        ),
                                  ),
                                ),
                                if (chosen)
                                  Icon(
                                    Icons.check_rounded,
                                    size: 18,
                                    color: palette.primary,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _effortOption(
    BuildContext context,
    AiReasoningEffort effort,
    bool selected,
  ) {
    final AppPalette palette = AppPalette.of(context);
    final AppCopy copy = widget.controller.copy;
    final String requestValue = effort.requestValue == null
        ? copy.localized('使用服务默认强度', 'Use the service default')
        : copy.localized(
            '请求推理强度：${copy.aiApiReasoningEffortName(effort)}',
            'Requested reasoning effort: ${copy.aiApiReasoningEffortName(effort)}',
          );
    return Tooltip(
      message: requestValue,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey<String>(
            'desktop-reasoning-option-${effort.storageValue}',
          ),
          onTap: () => _selectEffort(effort),
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: AppMotion.duration(context),
            curve: AppMotion.curve,
            constraints: const BoxConstraints(minWidth: 42, minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: selected
                  ? palette.primaryContainer
                  : palette.surfaceContainer,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected
                    ? palette.primary.withValues(alpha: 0.55)
                    : palette.outline,
              ),
            ),
            child: Center(
              widthFactor: 1,
              child: Text(
                widget.controller.copy.aiApiReasoningEffortName(effort),
                maxLines: 1,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: selected ? palette.primary : palette.textPrimary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _modelLabel(AppController controller, String id) {
  for (final AiModel model in controller.availableAiModels) {
    if (model.id == id) return model.label;
  }
  return id;
}
