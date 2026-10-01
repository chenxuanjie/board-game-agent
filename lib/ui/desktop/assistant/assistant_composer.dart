part of '../business_panes.dart';

class _DesktopContextPanel extends StatelessWidget {
  const _DesktopContextPanel({
    required this.controller,
    required this.useGlobalMode,
  });

  final AppController controller;
  final bool useGlobalMode;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => _content(context),
  );

  Widget _content(BuildContext context) {
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
          duration: AppMotion.duration(context),
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
