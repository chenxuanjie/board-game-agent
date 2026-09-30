part of 'business_panes.dart';

class DesktopActivityPopup extends StatefulWidget {
  const DesktopActivityPopup({
    super.key,
    required this.controller,
    required this.maxHeight,
    required this.onClose,
    required this.onActivityTap,
  });

  final AppController controller;
  final double maxHeight;
  final VoidCallback onClose;
  final ValueChanged<AppActivity> onActivityTap;

  @override
  State<DesktopActivityPopup> createState() => DesktopActivityPopupState();
}

class DesktopActivityPopupState extends State<DesktopActivityPopup> {
  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final AppCopy copy = widget.controller.copy;
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, Widget? child) {
        final List<AppActivity> activities = widget.controller.activities
            .map(widget.controller.resolveActivityTarget)
            .toList(growable: false);
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool compact = constraints.maxWidth < 320;
            final EdgeInsets panelPadding = EdgeInsets.fromLTRB(
              compact ? 12 : 16,
              compact ? 10 : 14,
              compact ? 12 : 16,
              compact ? 10 : 12,
            );
            final double listMaxHeight = math.max(
              0,
              widget.maxHeight - (compact ? 74 : 82),
            );
            return Material(
              color: Colors.transparent,
              elevation: 18,
              shadowColor: Colors.black.withValues(alpha: 0.32),
              borderRadius: BorderRadius.circular(12),
              child: DecoratedBox(
                key: const ValueKey<String>('desktop-activity-popup'),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: palette.outline),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: widget.maxHeight),
                  child: Padding(
                    padding: panelPadding,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(
                              Icons.notifications_none_rounded,
                              size: compact ? 21 : 24,
                              color: palette.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              copy.activityTitle,
                              style:
                                  (compact
                                          ? Theme.of(
                                              context,
                                            ).textTheme.titleMedium
                                          : Theme.of(
                                              context,
                                            ).textTheme.titleLarge)
                                      ?.copyWith(
                                        color: palette.textPrimary,
                                        fontWeight: FontWeight.w700,
                                      ),
                            ),
                            if (activities.isNotEmpty) ...<Widget>[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: palette.primary.withValues(
                                    alpha: 0.14,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${activities.length}',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: palette.primary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ),
                            ],
                            const Spacer(),
                            IconButton(
                              tooltip: copy.dialogClose,
                              visualDensity: compact
                                  ? VisualDensity.compact
                                  : VisualDensity.standard,
                              onPressed: widget.onClose,
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        Divider(height: 16, color: palette.outline),
                        if (activities.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              copy.activityEmpty,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: palette.textSecondary),
                            ),
                          )
                        else
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: listMaxHeight,
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              itemCount: activities.length,
                              separatorBuilder:
                                  (BuildContext context, int index) => Divider(
                                    height: 1,
                                    color: palette.outline,
                                  ),
                              itemBuilder: (BuildContext context, int index) =>
                                  _DesktopActivityTile(
                                    activity: activities[index],
                                    compact: false,
                                    controller: widget.controller,
                                    onTap: () =>
                                        widget.onActivityTap(activities[index]),
                                  ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _DesktopActivityTile extends StatelessWidget {
  const _DesktopActivityTile({
    required this.controller,
    required this.activity,
    required this.compact,
    this.onTap,
  });

  final AppController controller;
  final AppActivity activity;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final AppCopy copy = controller.copy;
    final Color accent = _activityColor(palette, activity.kind);
    final Widget content = Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 4,
        vertical: compact ? 10 : 8,
      ),
      decoration: compact
          ? BoxDecoration(
              color: palette.surfaceContainer.withValues(alpha: 0.52),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(_activityIcon(activity.kind), size: 17, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  activity.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  activity.message,
                  maxLines: compact ? 1 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: palette.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: _activityAbsoluteTime(activity.createdAt),
            child: Text(
              _activityTime(copy, activity.createdAt),
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: palette.textSecondary),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(compact ? 11 : 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(compact ? 11 : 8),
        onTap: onTap,
        child: content,
      ),
    );
  }
}

IconData _activityIcon(AppActivityKind kind) {
  return switch (kind) {
    AppActivityKind.serviceRefresh => Icons.sync_rounded,
    AppActivityKind.aiCompleted => Icons.check_circle_outline_rounded,
    AppActivityKind.aiFailed => Icons.error_outline_rounded,
    AppActivityKind.libraryUpdate => Icons.system_update_alt_rounded,
    AppActivityKind.libraryLoadFailed => Icons.error_outline_rounded,
    AppActivityKind.info => Icons.info_outline_rounded,
  };
}

Color _activityColor(AppPalette palette, AppActivityKind kind) {
  return switch (kind) {
    AppActivityKind.serviceRefresh => palette.primary,
    AppActivityKind.aiCompleted => palette.success,
    AppActivityKind.aiFailed => palette.error,
    AppActivityKind.libraryUpdate => palette.warning,
    AppActivityKind.libraryLoadFailed => palette.error,
    AppActivityKind.info => palette.textSecondary,
  };
}

String _activityTime(AppCopy copy, DateTime createdAt) {
  final Duration age = DateTime.now().difference(createdAt);
  if (age.isNegative || age.inSeconds < 60) {
    return copy.activityJustNow;
  }
  if (age.inMinutes < 60) {
    return copy.activityMinutesAgo(age.inMinutes);
  }
  if (age.inHours < 24) {
    return copy.activityHoursAgo(age.inHours);
  }
  if (age.inDays < 7) {
    return copy.activityDaysAgo(age.inDays);
  }
  final DateTime local = createdAt.toLocal();
  final String hour = local.hour.toString().padLeft(2, '0');
  final String minute = local.minute.toString().padLeft(2, '0');
  return '${local.month}/${local.day} $hour:$minute';
}

String _activityAbsoluteTime(DateTime createdAt) {
  final DateTime local = createdAt.toLocal();
  final String month = local.month.toString().padLeft(2, '0');
  final String day = local.day.toString().padLeft(2, '0');
  final String hour = local.hour.toString().padLeft(2, '0');
  final String minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}
