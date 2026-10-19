import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/identity/services/reaction_sync_diagnostics.dart';

/// Shared Windows/Android overlay; survives page navigation. Network work is
/// never started by this view. Its timer only updates elapsed waiting time.
class ReactionSyncDiagnosticsHost extends StatefulWidget {
  const ReactionSyncDiagnosticsHost({
    super.key,
    required this.diagnostics,
    required this.child,
  });
  final ReactionSyncDiagnostics diagnostics;
  final Widget child;
  @override
  State<ReactionSyncDiagnosticsHost> createState() =>
      _ReactionSyncDiagnosticsHostState();
}

class _ReactionSyncDiagnosticsHostState
    extends State<ReactionSyncDiagnosticsHost> {
  bool _expanded = true;
  Timer? _ticker;
  @override
  void initState() {
    super.initState();
    widget.diagnostics.addListener(_changed);
    _changed();
  }

  @override
  void didUpdateWidget(covariant ReactionSyncDiagnosticsHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.diagnostics != widget.diagnostics) {
      oldWidget.diagnostics.removeListener(_changed);
      widget.diagnostics.addListener(_changed);
      _changed();
    }
  }

  void _changed() {
    final waiting =
        widget.diagnostics.visible &&
        widget.diagnostics.activeStages.isNotEmpty;
    if (waiting && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!waiting) {
      _ticker?.cancel();
      _ticker = null;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.diagnostics.removeListener(_changed);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final log = widget.diagnostics;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Overlay.wrap(
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (log.visible)
            SafeArea(
              top: false,
              child: Align(
                alignment: Alignment.bottomRight,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 760;
                    final expanded =
                        _expanded &&
                        constraints.maxHeight >= 320 &&
                        MediaQuery.viewInsetsOf(context).bottom == 0;
                    final events = log.events;
                    final latestByRun = {
                      for (final event in events) event.run: event,
                    };
                    return Padding(
                      padding: EdgeInsets.all(wide ? 16 : 8),
                      child: Material(
                        key: const ValueKey('reaction-sync-diagnostics'),
                        elevation: 8,
                        color: scheme.surfaceContainerHigh,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: scheme.outlineVariant),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: SizedBox(
                          width: wide
                              ? 520
                              : math.max(0, constraints.maxWidth - 16),
                          height: expanded
                              ? math.min(320, constraints.maxHeight * .45)
                              : 52,
                          child: Column(
                            children: [
                              SizedBox(
                                height: 52,
                                child: Row(
                                  children: [
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextButton(
                                        onPressed: () => setState(
                                          () => _expanded = !_expanded,
                                        ),
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            '喜欢同步过程${log.activeStages.isEmpty ? '' : ' · 进行中'}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: '复制过程记录',
                                      icon: const Icon(Icons.copy_all_rounded),
                                      onPressed: () async {
                                        await Clipboard.setData(
                                          ClipboardData(text: log.export()),
                                        );
                                        if (context.mounted) {
                                          ScaffoldMessenger.maybeOf(
                                            context,
                                          )?.showSnackBar(
                                            const SnackBar(
                                              content: Text('同步记录已复制'),
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                    IconButton(
                                      tooltip: expanded ? '收起过程' : '展开过程',
                                      onPressed: () => setState(
                                        () => _expanded = !_expanded,
                                      ),
                                      icon: Icon(
                                        expanded
                                            ? Icons.expand_more
                                            : Icons.expand_less,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: '关闭过程窗口',
                                      onPressed: log.hide,
                                      icon: const Icon(Icons.close),
                                    ),
                                  ],
                                ),
                              ),
                              if (expanded) ...[
                                const Divider(height: 1),
                                Expanded(
                                  child: SelectionArea(
                                    child: ListView.builder(
                                      key: const ValueKey(
                                        'reaction-sync-events',
                                      ),
                                      reverse: true,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      itemCount: events.length,
                                      itemBuilder: (context, index) {
                                        final event =
                                            events[events.length - index - 1];
                                        final color =
                                            event.status ==
                                                ReactionTraceStatus.failure
                                            ? scheme.error
                                            : scheme.onSurfaceVariant;
                                        final waiting =
                                            event.status ==
                                                ReactionTraceStatus.running &&
                                            identical(
                                              latestByRun[event.run],
                                              event,
                                            ) &&
                                            log.waitingSince(event) != null;
                                        final elapsed = waiting
                                            ? ' · 已等待 ${log.waitingSince(event)!.inSeconds}s'
                                            : '';
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 10,
                                          ),
                                          child: Text(
                                            '#${event.run} +${event.elapsed.inMilliseconds}ms · '
                                            '${switch (event.status) {
                                              ReactionTraceStatus.running => '开始',
                                              ReactionTraceStatus.success => '完成',
                                              ReactionTraceStatus.failure => '失败',
                                              ReactionTraceStatus.info => '记录',
                                            }} '
                                            '${event.stage}$elapsed${event.detail.isEmpty ? '' : '\n${event.detail}'}',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(color: color),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
