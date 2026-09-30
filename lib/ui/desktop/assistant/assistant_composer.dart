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
                          disabledBorder: InputBorder.none,
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
