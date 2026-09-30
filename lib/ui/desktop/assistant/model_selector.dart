part of '../business_panes.dart';

enum _ModelPickerPage { models, reasoning }

class _DesktopModelAndReasoningSelector extends StatefulWidget {
  const _DesktopModelAndReasoningSelector({
    required this.controller,
    required this.enabled,
  });

  final AppController controller;
  final bool enabled;

  @override
  State<_DesktopModelAndReasoningSelector> createState() =>
      _DesktopModelAndReasoningSelectorState();
}

class _DesktopModelAndReasoningSelectorState
    extends State<_DesktopModelAndReasoningSelector> {
  bool _open = false;
  bool _hovered = false;
  bool _focused = false;

  Future<void> _showPicker() async {
    if (!widget.enabled || _open) return;
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final Rect trigger = box.localToGlobal(Offset.zero) & box.size;
    final Size viewport = MediaQuery.sizeOf(context);
    final double width = math.min(390, math.max(240, viewport.width - 24));
    final String currentModel = widget.controller.aiApiConfig.model.trim();
    final int modelCount =
        widget.controller.availableAiModels.length +
        (AiModelPolicy.allowsModel(currentModel) &&
                !widget.controller.availableAiModels.any(
                  (AiModel model) => model.id == currentModel,
                )
            ? 1
            : 0);
    final double desiredHeight = math.min(
      430,
      math.max(330, 170 + modelCount * 47),
    );
    final double above = trigger.top - 16;
    final double below = viewport.height - trigger.bottom - 16;
    final bool openAbove = above >= 330 || above >= below;
    final double height = math.min(
      desiredHeight,
      math.max(160, openAbove ? above : below),
    );
    final double left = (trigger.right - width).clamp(
      12.0,
      math.max(12.0, viewport.width - width - 12),
    );
    final double top = openAbove
        ? math.max(8, trigger.top - height - 8)
        : math.min(viewport.height - height - 8, trigger.bottom + 8);
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
        transitionDuration: const Duration(milliseconds: 190),
        pageBuilder: (BuildContext context, _, _) =>
            _DesktopModelPickerPanel(controller: widget.controller),
        transitionBuilder: (context, animation, _, child) {
          final Animation<double> curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return Stack(
            children: <Widget>[
              Positioned(
                left: left,
                top: top,
                width: width,
                height: height,
                child: FadeTransition(
                  opacity: curved,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: Offset(0, openAbove ? 0.045 : -0.045),
                      end: Offset.zero,
                    ).animate(curved),
                    child: child,
                  ),
                ),
              ),
            ],
          );
        },
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
        ? _desktopModelLabel(widget.controller, model)
        : copy.desktopModel;
    final String effortLabel =
        AiModelPolicy.reasoningEfforts(model)?.contains(effort) == true
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
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(maxWidth: 214, minHeight: 36),
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
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: palette.primary,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    modelLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Container(width: 1, height: 15, color: palette.outline),
                const SizedBox(width: 5),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 76),
                  child: Text(
                    effortLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 3),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 170),
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

class _DesktopModelPickerPanel extends StatefulWidget {
  const _DesktopModelPickerPanel({required this.controller});

  final AppController controller;

  @override
  State<_DesktopModelPickerPanel> createState() =>
      _DesktopModelPickerPanelState();
}

class _DesktopModelPickerPanelState extends State<_DesktopModelPickerPanel> {
  final TextEditingController _search = TextEditingController();
  _ModelPickerPage _page = _ModelPickerPage.models;
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
      setState(() => _page = _ModelPickerPage.reasoning);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.setAiModel(model);
      if (mounted) setState(() => _page = _ModelPickerPage.reasoning);
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
      if (mounted) Navigator.of(context).pop();
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
    final AppPalette palette = AppPalette.of(context);
    final AppCopy copy = widget.controller.copy;
    final bool canRefresh =
        widget.controller.aiApiConfig.apiKey.trim().isNotEmpty &&
        widget.controller.aiApiConfig.baseUrl.trim().isNotEmpty;
    return Material(
      key: const ValueKey<String>('desktop-model-picker-panel'),
      color: palette.surface,
      elevation: 18,
      shadowColor: palette.shadow.withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 10, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      copy.localized('模型与推理', 'Model & reasoning'),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Row(
                children: <Widget>[
                  _pageButton(
                    context,
                    page: _ModelPickerPage.models,
                    label: copy.desktopModel,
                  ),
                  const SizedBox(width: 7),
                  _pageButton(
                    context,
                    page: _ModelPickerPage.reasoning,
                    label: copy.aiApiReasoningEffortLabel,
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
                padding: const EdgeInsets.fromLTRB(16, 7, 16, 0),
                child: Text(
                  _error!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: palette.error),
                ),
              ),
            Expanded(
              child: AbsorbPointer(
                absorbing: _busy,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.025, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: _page == _ModelPickerPage.models
                      ? _modelPage(context)
                      : _reasoningPage(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pageButton(
    BuildContext context, {
    required _ModelPickerPage page,
    required String label,
  }) {
    final AppPalette palette = AppPalette.of(context);
    final bool selected = _page == page;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey<String>('desktop-model-picker-tab-${page.name}'),
          borderRadius: BorderRadius.circular(9),
          onTap: () => setState(() {
            _page = page;
            _error = null;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOutCubic,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? palette.primaryContainer
                  : palette.surfaceContainer,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: selected ? palette.primary : palette.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
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
              _desktopModelLabel(
                widget.controller,
                id,
              ).toLowerCase().contains(query),
        )
        .toList(growable: false);
    return Column(
      key: const ValueKey<String>('desktop-model-picker-model-page'),
      children: <Widget>[
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
        Expanded(
          child: visible.isEmpty
              ? Center(
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
                            duration: const Duration(milliseconds: 150),
                            curve: Curves.easeOutCubic,
                            height: 43,
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
                                    _desktopModelLabel(widget.controller, id),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
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

  Widget _reasoningPage(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final AppCopy copy = widget.controller.copy;
    final String model = widget.controller.aiApiConfig.model.trim();
    final AiReasoningEffort selected =
        widget.controller.aiApiConfig.reasoningEffort;
    final List<AiReasoningEffort>? options = AiModelPolicy.reasoningEfforts(
      model,
    );
    return SingleChildScrollView(
      key: const ValueKey<String>('desktop-model-picker-reasoning-page'),
      padding: const EdgeInsets.fromLTRB(17, 11, 17, 17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            model.isEmpty
                ? copy.localized('请先选择模型', 'Select a model first')
                : model,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: palette.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            copy.localized(
              '仅显示可用强度；自动不会发送强度参数',
              'Supported efforts only; Automatic omits the parameter',
            ),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: 16),
          if (options == null)
            Text(
              copy.aiApiReasoningUnsupported,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.warning),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final AiReasoningEffort effort in options)
                  _effortOption(context, effort, effort == selected),
              ],
            ),
        ],
      ),
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
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minWidth: 104),
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
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

String _desktopModelLabel(AppController controller, String id) {
  for (final AiModel model in controller.availableAiModels) {
    if (model.id == id) return model.label;
  }
  return id;
}
