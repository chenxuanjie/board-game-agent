part of '../business_panes.dart';

class _DesktopContextPanel extends StatelessWidget {
  const _DesktopContextPanel({
    required this.controller,
    required this.useGlobalMode,
  });

  final AppController controller;
  final bool useGlobalMode;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final AiConversation? selectedConversation =
        controller.selectedConversation;
    final GameInfo selectedGame = selectedConversation?.gameId == null
        ? controller.featuredGame
        : controller.games.firstWhere(
            (GameInfo item) => item.id == selectedConversation!.gameId,
            orElse: () => controller.featuredGame,
          );
    final bool smartSupplement = controller.allowSmartSupplement(
      useGlobalMode: useGlobalMode,
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.6),
        border: Border(left: BorderSide(color: palette.outline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            controller.copy.desktopContextTitle,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 13),
          if (!useGlobalMode || controller.globalUseCurrentGameKnowledge) ...[
            _DesktopContextLine(
              icon: Icons.casino_outlined,
              label: selectedGame.title,
            ),
            _DesktopContextLine(
              icon: Icons.menu_book_outlined,
              label: controller.copy.desktopRulebook,
            ),
            _DesktopContextLine(
              icon: Icons.fact_check_outlined,
              label: controller.copy.desktopFaq,
            ),
          ],
          const SizedBox(height: 18),
          Text(
            controller.copy.desktopAnswerModeTitle,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          _DesktopContextToggle(
            label: controller.copy.desktopOfficialFirst,
            selected: !smartSupplement,
            onTap: () => controller.setAllowSmartSupplement(
              false,
              useGlobalMode: useGlobalMode,
            ),
          ),
          _DesktopContextToggle(
            label: controller.copy.desktopSmartSupplement,
            selected: smartSupplement,
            onTap: () => controller.setAllowSmartSupplement(
              true,
              useGlobalMode: useGlobalMode,
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopContextLine extends StatelessWidget {
  const _DesktopContextLine({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: AppPalette.of(context).primary),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}

class _DesktopContextToggle extends StatelessWidget {
  const _DesktopContextToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: _desktopOptionDecoration(
            palette,
            selected: selected,
            radius: 9,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
              child: Row(
                children: <Widget>[
                  Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    size: 17,
                    color: selected ? palette.primary : palette.textSecondary,
                  ),
                  const SizedBox(width: 7),
                  Expanded(child: Text(label)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopComposer extends StatelessWidget {
  const _DesktopComposer({
    required this.controller,
    required this.draftController,
    required this.useGlobalMode,
    required this.onSend,
    required this.onOpenContext,
  });

  final AppController controller;
  final TextEditingController draftController;
  final bool useGlobalMode;
  final Future<void> Function() onSend;
  final VoidCallback onOpenContext;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final AppCopy copy = controller.copy;
    return AnimatedBuilder(
      animation: draftController,
      builder: (BuildContext context, Widget? child) {
        final bool isSending = controller.isSendingForContext(
          useGlobalMode: useGlobalMode,
        );
        final bool canSend =
            draftController.text.trim().isNotEmpty && !isSending;
        final bool smartSupplement = controller.allowSmartSupplement(
          useGlobalMode: useGlobalMode,
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AssistantFeatureChip(
                  icon: smartSupplement
                      ? Icons.auto_awesome_rounded
                      : Icons.menu_book_rounded,
                  label: smartSupplement
                      ? copy.smartSupplementLabel
                      : copy.knowledgeOnlyLabel,
                  foregroundColor: smartSupplement
                      ? palette.secondary
                      : palette.primary,
                  backgroundColor:
                      (smartSupplement ? palette.secondary : palette.primary)
                          .withValues(alpha: 0.14),
                  onRemove: onOpenContext,
                ),
              ),
            ),
            Container(
              key: const ValueKey<String>('desktop-composer-box'),
              constraints: const BoxConstraints(minHeight: 52),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: palette.outline),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(7, 4, 7, 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    _DesktopAnswerModeSelector(
                      controller: controller,
                      useGlobalMode: useGlobalMode,
                      enabled: !isSending,
                    ),
                    Expanded(
                      child: TextField(
                        controller: draftController,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: canSend ? (_) => onSend() : null,
                        decoration: InputDecoration(
                          hintText: copy.desktopInputHint,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 7,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _DesktopModelAndReasoningSelector(
                      controller: controller,
                      enabled: !isSending,
                    ),
                    IconButton(
                      key: const ValueKey<String>('desktop-composer-send'),
                      tooltip: isSending
                          ? copy.desktopStopGenerating
                          : copy.desktopSend,
                      onPressed: isSending
                          ? () => controller.stopGenerating(
                              useGlobalMode: useGlobalMode,
                            )
                          : canSend
                          ? onSend
                          : null,
                      style: IconButton.styleFrom(
                        backgroundColor: canSend || controller.isSending
                            ? palette.primary
                            : palette.disabledBackground,
                        foregroundColor: canSend || controller.isSending
                            ? palette.onPrimary
                            : palette.disabledForeground,
                        minimumSize: const Size.square(37),
                        maximumSize: const Size.square(37),
                        fixedSize: const Size.square(37),
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                      icon: Icon(
                        isSending
                            ? Icons.stop_rounded
                            : Icons.arrow_upward_rounded,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DesktopAnswerModeSelector extends StatelessWidget {
  const _DesktopAnswerModeSelector({
    required this.controller,
    required this.useGlobalMode,
    required this.enabled,
  });

  final AppController controller;
  final bool useGlobalMode;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final AppCopy copy = controller.copy;
    final bool smartSupplement = controller.allowSmartSupplement(
      useGlobalMode: useGlobalMode,
    );
    return PopupMenuButton<bool>(
      key: const ValueKey<String>('desktop-answer-mode-selector'),
      enabled: enabled,
      tooltip: copy.desktopAnswerModeTitle,
      onSelected: (bool value) {
        if (value == smartSupplement) return;
        unawaited(
          controller.setAllowSmartSupplement(
            value,
            useGlobalMode: useGlobalMode,
          ),
        );
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<bool>>[
        PopupMenuItem<bool>(
          value: false,
          child: _AnswerModeMenuItem(
            icon: Icons.menu_book_outlined,
            label: copy.desktopOfficialFirst,
            selected: !smartSupplement,
          ),
        ),
        PopupMenuItem<bool>(
          value: true,
          child: _AnswerModeMenuItem(
            icon: Icons.auto_awesome_outlined,
            label: copy.desktopSmartSupplement,
            selected: smartSupplement,
          ),
        ),
      ],
      child: _DesktopComposerIcon(
        icon: Icons.add_rounded,
        palette: palette,
        tooltip: copy.desktopAnswerModeTitle,
      ),
    );
  }
}

class _AnswerModeMenuItem extends StatelessWidget {
  const _AnswerModeMenuItem({
    required this.icon,
    required this.label,
    required this.selected,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: selected ? palette.primary : null),
        const SizedBox(width: 9),
        Expanded(child: Text(label)),
        if (selected)
          Icon(Icons.check_rounded, size: 17, color: palette.primary),
      ],
    );
  }
}

class _DesktopComposerIcon extends StatelessWidget {
  const _DesktopComposerIcon({
    required this.icon,
    required this.palette,
    required this.tooltip,
  });

  final IconData icon;
  final AppPalette palette;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 37,
        height: 37,
        child: Icon(icon, color: palette.textSecondary),
      ),
    );
  }
}

const String _desktopRefreshModelsAction = '__refresh_models__';

class _DesktopModelAndReasoningSelector extends StatelessWidget {
  const _DesktopModelAndReasoningSelector({
    required this.controller,
    required this.enabled,
  });

  final AppController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final AppCopy copy = controller.copy;
    final String selectedModel = controller.aiApiConfig.model.trim();
    final AiReasoningEffort selectedReasoning =
        controller.aiApiConfig.reasoningEffort;
    final List<String> modelIds = <String>[];
    if (selectedModel.isNotEmpty) modelIds.add(selectedModel);
    for (final model in controller.availableAiModels) {
      if (model.id.trim().isNotEmpty && !modelIds.contains(model.id)) {
        modelIds.add(model.id);
      }
    }
    return PopupMenuButton<String>(
      key: const ValueKey<String>('desktop-model-selector'),
      enabled: enabled,
      tooltip: copy.desktopModel,
      onSelected: (String value) {
        if (value == _desktopRefreshModelsAction) {
          unawaited(controller.refreshAiModels());
          return;
        }
        if (value.startsWith('model:')) {
          final String model = value.substring('model:'.length).trim();
          if (model.isNotEmpty && model != selectedModel) {
            unawaited(controller.setAiModel(model));
          }
          return;
        }
        if (value.startsWith('reasoning:')) {
          final AiReasoningEffort effort = AiReasoningEffortX.fromStored(
            value.substring('reasoning:'.length),
          );
          if (effort != selectedReasoning) {
            unawaited(controller.setAiReasoningEffort(effort));
          }
        }
      },
      itemBuilder: (BuildContext context) {
        final List<PopupMenuEntry<String>> items = <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            enabled: false,
            value: 'model-header',
            child: Text(copy.desktopModel),
          ),
          if (modelIds.isEmpty)
            PopupMenuItem<String>(
              enabled: false,
              value: 'model-empty',
              child: Text(_modelStatusLabel(controller, copy)),
            )
          else
            for (final modelId in modelIds)
              PopupMenuItem<String>(
                value: 'model:$modelId',
                child: _DesktopSelectorMenuItem(
                  label: _modelLabel(controller, modelId),
                  selected: modelId == selectedModel,
                ),
              ),
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            enabled: false,
            value: 'reasoning-header',
            child: Text(copy.aiApiReasoningEffortLabel),
          ),
          for (final AiReasoningEffort effort in AiReasoningEffort.values)
            PopupMenuItem<String>(
              value: 'reasoning:${effort.storageValue}',
              child: _DesktopSelectorMenuItem(
                label: copy.aiApiReasoningEffortName(effort),
                selected: effort == selectedReasoning,
              ),
            ),
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: _desktopRefreshModelsAction,
            child: Row(
              children: <Widget>[
                const Icon(Icons.refresh_rounded, size: 18),
                const SizedBox(width: 8),
                Text(
                  controller.aiModelLoadState == AiModelLoadState.loading
                      ? copy.aiApiModelsLoading
                      : copy.desktopRefreshModels,
                ),
              ],
            ),
          ),
        ];
        return items;
      },
      child: _DesktopModelReasoningChoice(
        model: selectedModel.isEmpty
            ? copy.desktopModel
            : _modelLabel(controller, selectedModel),
        reasoning: copy.aiApiReasoningEffortName(selectedReasoning),
        palette: palette,
      ),
    );
  }

  String _modelLabel(AppController controller, String id) {
    for (final model in controller.availableAiModels) {
      if (model.id == id) return model.label;
    }
    return id;
  }

  String _modelStatusLabel(AppController controller, AppCopy copy) {
    return switch (controller.aiModelLoadState) {
      AiModelLoadState.loading => copy.aiApiModelsLoading,
      AiModelLoadState.failure => copy.aiApiModelsFailed,
      AiModelLoadState.empty => copy.aiApiModelsEmpty,
      _ => copy.aiApiModelsNotLoaded,
    };
  }
}

class _DesktopSelectorMenuItem extends StatelessWidget {
  const _DesktopSelectorMenuItem({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        if (selected)
          Icon(Icons.check_rounded, size: 17, color: palette.primary),
      ],
    );
  }
}

class _DesktopModelReasoningChoice extends StatelessWidget {
  const _DesktopModelReasoningChoice({
    required this.model,
    required this.reasoning,
    required this.palette,
  });

  final String model;
  final String reasoning;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 0, maxWidth: 165),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 11),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(
              child: Text(
                model,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              reasoning,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: palette.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
