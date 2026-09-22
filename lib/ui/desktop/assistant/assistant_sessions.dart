part of '../business_panes.dart';

class _DesktopAssistantSessions extends StatelessWidget {
  const _DesktopAssistantSessions({
    required this.controller,
    this.embedded = false,
  });

  final AppController controller;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Container(
      margin: embedded ? const EdgeInsets.only(left: 28) : EdgeInsets.zero,
      padding: embedded
          ? const EdgeInsets.fromLTRB(15, 12, 4, 4)
          : const EdgeInsets.all(14),
      decoration: embedded
          ? BoxDecoration(
              border: Border(left: BorderSide(color: palette.outline)),
            )
          : BoxDecoration(
              color: palette.surface.withValues(alpha: 0.6),
              border: Border(right: BorderSide(color: palette.outline)),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  controller.copy.desktopSessionTitle,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: controller.copy.desktopOpenGlobalAssistant,
                visualDensity: VisualDensity.compact,
                onPressed: controller.openGlobalAssistant,
                icon: const Icon(Icons.add_rounded, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (embedded)
            Flexible(
              fit: FlexFit.loose,
              child: ListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                children: _sessionRows(),
              ),
            )
          else
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: _sessionRows(),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _sessionRows() {
    return <Widget>[
      for (final AiConversation conversation in controller.conversations)
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: _DesktopSessionRow(
            icon: conversation.id == controller.selectedConversationId
                ? Icons.chat_rounded
                : Icons.chat_bubble_outline_rounded,
            title: conversation.title,
            subtitle: controller.copy.desktopConversationSummary(
              conversation.isGlobal,
              conversation.messageCount,
            ),
            selected: conversation.id == controller.selectedConversationId,
            onTap: () => controller.selectConversation(conversation.id),
          ),
        ),
    ];
  }
}

class _DesktopSessionRow extends StatelessWidget {
  const _DesktopSessionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: _desktopOptionDecoration(
          palette,
          selected: selected,
          radius: 7,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: <Widget>[
                Icon(
                  icon,
                  size: 18,
                  color: selected ? palette.primary : palette.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: selected
                                  ? palette.textPrimary
                                  : palette.textSecondary,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
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

class _AssistantAppMark extends StatelessWidget {
  const _AssistantAppMark();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: Image.asset(
        'branding/app_icon.png',
        width: 38,
        height: 38,
        fit: BoxFit.cover,
        errorBuilder:
            (BuildContext context, Object error, StackTrace? stackTrace) =>
                const SizedBox(
                  width: 38,
                  height: 38,
                  child: Icon(Icons.casino_rounded),
                ),
      ),
    );
  }
}

class _AssistantStatusDot extends StatelessWidget {
  const _AssistantStatusDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: const SizedBox(width: 8, height: 8),
    );
  }
}

class _AssistantStatusLabel extends StatelessWidget {
  const _AssistantStatusLabel({required this.label, required this.palette});

  final String label;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _AssistantStatusDot(color: palette.success),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
          ),
        ),
      ],
    );
  }
}
