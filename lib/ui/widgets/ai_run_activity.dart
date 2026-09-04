import 'package:flutter/material.dart';

import '../../models/ai_run.dart';
import '../../theme/app_palette.dart';
import '../app_copy.dart';

/// Presents the safe, user-facing activity of one AI answer.
///
/// This is deliberately a response activity area rather than a second chat
/// bubble or a diagnostic console. It only renders actions that can be
/// explained to a user: routing, source lookup, web search, retries, and the
/// final response state. Provider event names, raw output items, and hidden
/// reasoning are never shown here.
class AiRunActivity extends StatelessWidget {
  const AiRunActivity({
    super.key,
    required this.events,
    required this.isRunning,
    required this.palette,
    required this.copy,
  });

  final List<AiRunEvent> events;
  final bool isRunning;
  final AppPalette palette;
  final AppCopy copy;

  @override
  Widget build(BuildContext context) {
    if (!isRunning && events.isEmpty) {
      return const SizedBox.shrink();
    }

    final List<_ActivityStep> steps = _steps;
    final List<_ProtocolCard> protocolCards = _protocolCards;
    final bool hasTimeline = steps.isNotEmpty || protocolCards.isNotEmpty;
    final bool isRunCompleted =
        !isRunning &&
        events.any(
          (AiRunEvent event) => event.type == AiRunEventType.completed,
        );
    Widget buildTimeline(bool expandDetails) {
      return steps.isEmpty && protocolCards.isEmpty
          ? _EmptyActivityStep(palette: palette, copy: copy)
          : DecoratedBox(
              decoration: BoxDecoration(
                border: hasTimeline
                    ? Border(
                        left: BorderSide(
                          color: palette.outline.withValues(
                            alpha: isRunning ? 0.38 : 0.18,
                          ),
                          width: 1,
                        ),
                      )
                    : null,
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (int index = 0; index < steps.length; index++)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: index == steps.length - 1 ? 0 : 7,
                        ),
                        child: _ActivityStepTile(
                          key: ValueKey<String>(steps[index].key),
                          step: steps[index],
                          palette: palette,
                          isChinese: copy.isChinese,
                          isRunning: isRunning,
                          isRunCompleted: isRunCompleted,
                          forceExpanded: expandDetails,
                        ),
                      ),
                    for (int index = 0; index < protocolCards.length; index++)
                      Padding(
                        padding: EdgeInsets.only(
                          top: steps.isEmpty && index == 0 ? 0 : 7,
                          bottom: index == protocolCards.length - 1 ? 0 : 7,
                        ),
                        child: _ProtocolCardTile(
                          key: ValueKey<_ProtocolCardKind>(
                            protocolCards[index].kind,
                          ),
                          card: protocolCards[index],
                          palette: palette,
                          isChinese: copy.isChinese,
                          isRunning: isRunning,
                          isRunCompleted: isRunCompleted,
                          forceExpanded: expandDetails,
                        ),
                      ),
                  ],
                ),
              ),
            );
    }

    return _AiRunActivityView(
      runId: events.isEmpty ? null : events.first.runId,
      isRunning: isRunning,
      isCompleted: isRunCompleted,
      duration: _runDuration,
      palette: palette,
      copy: copy,
      timelineBuilder: buildTimeline,
    );
  }

  Duration get _runDuration {
    if (events.isEmpty) return Duration.zero;
    final List<AiRunEvent> ordered = events.toList(growable: false)
      ..sort((AiRunEvent a, AiRunEvent b) {
        final int sequence = a.sequence.compareTo(b.sequence);
        return sequence != 0 ? sequence : a.timestamp.compareTo(b.timestamp);
      });
    final Duration duration = ordered.last.timestamp.difference(
      ordered.first.timestamp,
    );
    return duration.isNegative ? Duration.zero : duration;
  }

  List<_ProtocolCard> get _protocolCards {
    final List<AiRunEvent> orderedEvents = events.toList(growable: false)
      ..sort((AiRunEvent a, AiRunEvent b) => a.sequence.compareTo(b.sequence));
    final List<_ProtocolCard> cards = <_ProtocolCard>[];

    void upsertStream(_ProtocolCard card) {
      final int index = cards.indexWhere(
        (_ProtocolCard value) => value.kind == _ProtocolCardKind.stream,
      );
      if (index < 0) {
        cards.add(card);
      } else {
        cards[index] = card;
      }
    }

    void upsertResume(_ProtocolCard card) {
      final int index = cards.indexWhere(
        (_ProtocolCard value) => value.kind == _ProtocolCardKind.resume,
      );
      if (index < 0) {
        cards.add(card);
      } else {
        cards[index] = card;
      }
    }

    for (final AiRunEvent event in orderedEvents) {
      switch (event.type) {
        case AiRunEventType.responseStreamStarted:
          upsertStream(
            _ProtocolCard(
              kind: _ProtocolCardKind.stream,
              status: _ProtocolCardStatus.running,
              title: 'response stream',
              subtitle: _text('正在监听事件流', 'Listening to the event stream'),
              event: event,
            ),
          );
        case AiRunEventType.responseStreamFailed:
          final _ProtocolCard failedCard = _ProtocolCard(
            kind: _ProtocolCardKind.stream,
            status: _ProtocolCardStatus.failed,
            title: 'response stream',
            subtitle: event.detail?.trim().isNotEmpty == true
                ? event.detail!.trim()
                : _text('响应流中断', 'Response stream interrupted'),
            event: event,
          );
          upsertStream(failedCard);
        case AiRunEventType.resumeStarted:
          upsertResume(
            _ProtocolCard(
              kind: _ProtocolCardKind.resume,
              status: _ProtocolCardStatus.running,
              title: 'resume',
              subtitle: event.detail?.trim().isNotEmpty == true
                  ? event.detail!.trim()
                  : _text('正在恢复连接', 'Resuming the connection'),
              event: event,
            ),
          );
        case AiRunEventType.resumeCompleted:
          final int resumeIndex = cards.indexWhere(
            (_ProtocolCard card) => card.kind == _ProtocolCardKind.resume,
          );
          if (resumeIndex >= 0) {
            cards[resumeIndex] = cards[resumeIndex].copyWith(
              status: _ProtocolCardStatus.completed,
              subtitle: event.detail?.trim().isNotEmpty == true
                  ? event.detail!.trim()
                  : _text('已恢复', 'Resumed'),
              event: event,
            );
          }
        case AiRunEventType.status:
          if (event.status == 'response_completed') {
            final int streamIndex = cards.indexWhere(
              (_ProtocolCard card) => card.kind == _ProtocolCardKind.stream,
            );
            if (streamIndex >= 0) {
              cards[streamIndex] = cards[streamIndex].copyWith(
                status: _ProtocolCardStatus.completed,
                subtitle: _text('事件流已完成', 'Event stream completed'),
                event: event,
              );
            }
          }
          break;
        case AiRunEventType.retry:
          upsertResume(
            _ProtocolCard(
              kind: _ProtocolCardKind.resume,
              status: _ProtocolCardStatus.running,
              title: 'resume',
              subtitle: event.detail?.trim().isNotEmpty == true
                  ? event.detail!.trim()
                  : _text('正在重试连接', 'Retrying the connection'),
              event: event,
            ),
          );
          break;
        default:
          break;
      }
    }
    return cards;
  }

  List<_ActivityStep> get _steps {
    final Map<String, _ActivityStep> byKey = <String, _ActivityStep>{};
    final List<_ActivityStep> ordered = <_ActivityStep>[];
    final List<String> pendingStageIds = <String>[];
    String? lastStageKey;
    _ActivityStep? active;

    _ActivityStep createStage(String id) {
      final _StageMeta meta = _stageMeta(id);
      final String key = 'stage:$id';
      final _ActivityStep step = _ActivityStep(
        key: key,
        runningTitle: meta.runningTitle,
        completedTitle: meta.completedTitle,
        detail: meta.runningDetail,
        icon: meta.icon,
      );
      byKey[key] = step;
      ordered.add(step);
      return step;
    }

    _ActivityStep? stageFor(String id) {
      if (id.trim().isEmpty) return null;
      final String key = 'stage:$id';
      return byKey[key] ?? createStage(id);
    }

    void startStageNow(String id, {String? detail}) {
      final _StageMeta? meta = _stageMetaOrNull(id);
      if (meta == null) return;
      final String key = 'stage:$id';
      final _ActivityStep step = stageFor(id)!;
      step.status = _ActivityStepStatus.running;
      step.detail = detail ?? meta.runningDetail;
      active = step;
      lastStageKey = key;
    }

    void startStage(String id, {String? detail}) {
      final _StageMeta? meta = _stageMetaOrNull(id);
      if (meta == null) return;
      final String key = 'stage:$id';
      if (active != null &&
          active!.status == _ActivityStepStatus.running &&
          active!.key != key) {
        // A provider may batch or reorder lifecycle notifications. Preserve
        // the later stage, but do not expose it until the active stage emits
        // its completion event. This is the key invariant behind the
        // Codex/OpenHands-style activity timeline.
        if (!pendingStageIds.contains(id)) pendingStageIds.add(id);
        return;
      }
      startStageNow(id, detail: detail);
    }

    void updateActive(String? detail) {
      final String value = detail?.trim() ?? '';
      if (active != null && value.isNotEmpty) active!.detail = value;
    }

    void completeStage(String id, AiStageStatus? status) {
      final _ActivityStep? step = byKey['stage:$id'];
      if (step == null) return;
      final _StageMeta meta = _stageMeta(id);
      step.status = switch (status) {
        AiStageStatus.failed ||
        AiStageStatus.incomplete => _ActivityStepStatus.failed,
        AiStageStatus.insufficient ||
        AiStageStatus.unavailable ||
        AiStageStatus.skipped => _ActivityStepStatus.warning,
        _ => _ActivityStepStatus.completed,
      };
      step.detail = _stageCompletedDetail(status, meta);
      lastStageKey = step.key;
      if (active?.key == step.key) {
        active = null;
        if (pendingStageIds.isNotEmpty) {
          final String nextStageId = pendingStageIds.removeAt(0);
          startStageNow(nextStageId);
        }
      }
    }

    // The controller normally appends events in provider order, but keeping
    // the renderer defensive matters when a rebuild races a terminal event or
    // a platform transport delivers two notifications in one frame. Never
    // infer a future step from the declared workflow; only render events that
    // have actually arrived for the current run.
    final String? currentRunId = events.isEmpty ? null : events.first.runId;
    final List<AiRunEvent> orderedEvents =
        events
            .where(
              (AiRunEvent event) =>
                  currentRunId == null || event.runId == currentRunId,
            )
            .toList(growable: false)
          ..sort((AiRunEvent a, AiRunEvent b) {
            final int sequence = a.sequence.compareTo(b.sequence);
            return sequence != 0
                ? sequence
                : a.timestamp.compareTo(b.timestamp);
          });

    for (final AiRunEvent event in orderedEvents) {
      final String stageId = event.stageId?.trim() ?? '';
      switch (event.type) {
        case AiRunEventType.stageStarted:
          startStage(stageId);
          break;
        case AiRunEventType.stageCompleted:
          completeStage(stageId, event.stageResult?.status);
          break;
        case AiRunEventType.status:
          final String status = event.status?.trim() ?? '';
          if (status == 'routing') {
            if (active == null || active!.key == 'stage:routing') {
              startStage(
                'routing',
                detail: _text(
                  '确定是否需要查阅桌游资料',
                  'Deciding whether game sources are needed',
                ),
              );
            }
          } else if (status == 'answering') {
            if (active == null || active!.key == 'stage:answering') {
              startStage(
                'answering',
                detail: _text('整合已确认的信息', 'Combining confirmed information'),
              );
            }
          } else if (status == 'web_search') {
            if (active == null || active!.key == 'stage:web') {
              startStage(
                'web',
                detail: _text('正在搜索相关资料', 'Searching relevant sources'),
              );
            }
          } else if (status == 'web_search_completed') {
            if (active?.key == 'stage:web') {
              updateActive(_citationDetail(active!.citationCount));
            }
          } else if (status == 'reconnecting') {
            updateActive(
              _text('连接暂时中断，正在重试', 'The connection paused; retrying'),
            );
          }
          break;
        case AiRunEventType.toolStarted:
          final String tool = event.toolName?.trim() ?? '';
          if (tool == 'web_search') {
            if (active == null || active!.key == 'stage:web') {
              startStage(
                'web',
                detail: _text('正在搜索相关资料', 'Searching relevant sources'),
              );
            }
          }
          break;
        case AiRunEventType.toolCompleted:
          final String tool = event.toolName?.trim() ?? '';
          if (tool == 'web_search' && active?.key == 'stage:web') {
            updateActive(_citationDetail(active!.citationCount));
          }
          break;
        case AiRunEventType.citationAdded:
          final _ActivityStep? step =
              active ?? (lastStageKey == null ? null : byKey[lastStageKey]);
          if (step != null) {
            step.citationCount += 1;
            step.detail = _citationDetail(step.citationCount);
          }
          break;
        case AiRunEventType.retry:
          updateActive(
            event.detail?.trim().isNotEmpty == true
                ? event.detail!.trim()
                : _text('连接暂时中断，正在重试', 'The connection paused; retrying'),
          );
          break;
        case AiRunEventType.responseStreamStarted:
        case AiRunEventType.responseStreamFailed:
        case AiRunEventType.resumeStarted:
        case AiRunEventType.resumeCompleted:
          break;
        case AiRunEventType.failed:
        case AiRunEventType.incomplete:
        case AiRunEventType.cancelled:
          if (active != null) {
            active!.status = event.type == AiRunEventType.cancelled
                ? _ActivityStepStatus.warning
                : _ActivityStepStatus.failed;
            active!.detail = event.errorMessage?.trim() ?? '';
            active = null;
            pendingStageIds.clear();
          } else {
            final _ActivityStep step = byKey.putIfAbsent('terminal', () {
              final _ActivityStep value = _ActivityStep(
                key: 'terminal',
                runningTitle: _text('回答未完成', 'Answer incomplete'),
                completedTitle: _text('回答未完成', 'Answer incomplete'),
                detail: '',
                icon: Icons.error_outline_rounded,
              );
              ordered.add(value);
              return value;
            });
            step.status = event.type == AiRunEventType.cancelled
                ? _ActivityStepStatus.warning
                : _ActivityStepStatus.failed;
            step.detail = event.errorMessage?.trim() ?? '';
          }
          break;
        case AiRunEventType.runStarted:
        case AiRunEventType.textDelta:
        case AiRunEventType.outputItem:
        case AiRunEventType.completed:
          // Text deltas and provider output-item names are implementation
          // details. The visible answer remains committed by the controller
          // only after the terminal response event.
          break;
      }
    }
    return ordered;
  }

  _StageMeta? _stageMetaOrNull(String id) {
    if (id.trim().isEmpty) return null;
    return switch (id) {
      'routing' => _StageMeta(
        runningTitle: _text('正在判断问题范围', 'Classifying the request'),
        completedTitle: _text('已判断问题范围', 'Request classified'),
        runningDetail: _text(
          '确定是否需要查阅桌游资料',
          'Deciding whether game sources are needed',
        ),
        icon: Icons.tune_rounded,
      ),
      'official' => _StageMeta(
        runningTitle: _text('正在查阅官方规则', 'Checking official rules'),
        completedTitle: _text('已查阅官方规则', 'Official rules checked'),
        runningDetail: _text(
          '从当前桌游资料中查找依据',
          'Looking for evidence in the game sources',
        ),
        icon: Icons.menu_book_rounded,
      ),
      'community' => _StageMeta(
        runningTitle: _text('正在查阅社区资料', 'Checking community sources'),
        completedTitle: _text('已查阅社区资料', 'Community sources checked'),
        runningDetail: _text(
          '查找补充说明和实际案例',
          'Looking for clarifications and examples',
        ),
        icon: Icons.forum_outlined,
      ),
      'web' => _StageMeta(
        runningTitle: _text('正在搜索相关资料', 'Searching relevant sources'),
        completedTitle: _text('已完成资料搜索', 'Source search completed'),
        runningDetail: _text(
          '仅在本地资料不足时联网查找',
          'Searching online only when local sources are insufficient',
        ),
        icon: Icons.public_rounded,
      ),
      'answering' || 'general' || 'fallback' => _StageMeta(
        runningTitle: _text('正在整理回答', 'Preparing the answer'),
        completedTitle: _text('已整理回答', 'Answer prepared'),
        runningDetail: _text('整合已确认的信息', 'Combining confirmed information'),
        icon: Icons.edit_note_rounded,
      ),
      _ => null,
    };
  }

  _StageMeta _stageMeta(String id) =>
      _stageMetaOrNull(id) ??
      _StageMeta(
        runningTitle: _text('正在处理', 'Working'),
        completedTitle: _text('已处理', 'Processed'),
        runningDetail: _text('正在处理当前请求', 'Processing the request'),
        icon: Icons.auto_awesome_rounded,
      );

  String _stageCompletedDetail(AiStageStatus? status, _StageMeta meta) {
    return switch (status) {
      AiStageStatus.insufficient => _text(
        '当前资料不足，继续查找其他来源',
        'Not enough evidence here; continuing',
      ),
      AiStageStatus.unavailable ||
      AiStageStatus.skipped => _text('当前范围未启用', 'Not enabled for this scope'),
      AiStageStatus.failed ||
      AiStageStatus.incomplete => _text('这一阶段没有完成', 'This step did not finish'),
      _ => meta.completedTitle,
    };
  }

  String _citationDetail(int count) => count <= 0
      ? _text('已完成搜索，正在整理结果', 'Search complete; organizing results')
      : _text(
          '已找到 $count 个来源，正在整理结果',
          '$count sources found; organizing results',
        );

  String _text(String zh, String en) => copy.isChinese ? zh : en;
}

class _AiRunActivityView extends StatefulWidget {
  const _AiRunActivityView({
    required this.runId,
    required this.isRunning,
    required this.isCompleted,
    required this.duration,
    required this.palette,
    required this.copy,
    required this.timelineBuilder,
  });

  final String? runId;
  final bool isRunning;
  final bool isCompleted;
  final Duration duration;
  final AppPalette palette;
  final AppCopy copy;
  final Widget Function(bool expandDetails) timelineBuilder;

  @override
  State<_AiRunActivityView> createState() => _AiRunActivityViewState();
}

class _AiRunActivityViewState extends State<_AiRunActivityView> {
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    _expanded = !widget.isCompleted;
  }

  @override
  void didUpdateWidget(covariant _AiRunActivityView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool runChanged =
        widget.runId != null && widget.runId != oldWidget.runId;
    final bool completedNow = !oldWidget.isCompleted && widget.isCompleted;
    if (runChanged || completedNow) {
      _expanded = !widget.isCompleted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool showDuration = widget.isCompleted;
    final Widget content = showDuration
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _DurationToggle(
                duration: widget.duration,
                palette: widget.palette,
                copy: widget.copy,
                expanded: _expanded,
                onTap: () => setState(() => _expanded = !_expanded),
              ),
              if (_expanded) widget.timelineBuilder(true),
            ],
          )
        : widget.timelineBuilder(false);
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: content,
    );
  }
}

class _DurationToggle extends StatelessWidget {
  const _DurationToggle({
    required this.duration,
    required this.palette,
    required this.copy,
    required this.expanded,
    required this.onTap,
  });

  final Duration duration;
  final AppPalette palette;
  final AppCopy copy;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int hours = duration.inHours;
    final int minutes = duration.inMinutes.remainder(60);
    final int seconds = duration.inSeconds.remainder(60);
    final String label = copy.isChinese
        ? hours > 0
              ? '用时 $hours 小时 $minutes 分钟 $seconds 秒'
              : minutes > 0
              ? '用时 $minutes 分钟 $seconds 秒'
              : '用时 $seconds 秒'
        : hours > 0
        ? 'Duration ${hours}h ${minutes}m ${seconds}s'
        : minutes > 0
        ? 'Duration ${minutes}m ${seconds}s'
        : 'Duration ${seconds}s';
    return Semantics(
      button: true,
      expanded: expanded,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: <Widget>[
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: palette.textSecondary,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                expanded
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.chevron_right_rounded,
                size: 20,
                color: palette.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Divider(color: palette.outline.withValues(alpha: 0.35)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ActivityStepStatus { running, completed, warning, failed }

class _StageMeta {
  const _StageMeta({
    required this.runningTitle,
    required this.completedTitle,
    required this.runningDetail,
    required this.icon,
  });

  final String runningTitle;
  final String completedTitle;
  final String runningDetail;
  final IconData icon;
}

class _ActivityStep {
  _ActivityStep({
    required this.key,
    required this.runningTitle,
    required this.completedTitle,
    required this.detail,
    required this.icon,
  });

  final String key;
  final String runningTitle;
  final String completedTitle;
  final IconData icon;
  String detail;
  int citationCount = 0;
  _ActivityStepStatus status = _ActivityStepStatus.running;

  String get title =>
      status == _ActivityStepStatus.running ? runningTitle : completedTitle;
}

class _EmptyActivityStep extends StatelessWidget {
  const _EmptyActivityStep({required this.palette, required this.copy});

  final AppPalette palette;
  final AppCopy copy;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: 15,
          height: 15,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: palette.primary,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          copy.isChinese ? '正在处理' : 'Working',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
        ),
      ],
    );
  }
}

class _ActivityStepTile extends StatefulWidget {
  const _ActivityStepTile({
    super.key,
    required this.step,
    required this.palette,
    required this.isChinese,
    required this.isRunning,
    required this.isRunCompleted,
    required this.forceExpanded,
  });

  final _ActivityStep step;
  final AppPalette palette;
  final bool isChinese;
  final bool isRunning;
  final bool isRunCompleted;
  final bool forceExpanded;

  @override
  State<_ActivityStepTile> createState() => _ActivityStepTileState();
}

class _ActivityStepTileState extends State<_ActivityStepTile> {
  late final ExpansibleController _controller;
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _controller = ExpansibleController();
    _expanded =
        widget.forceExpanded ||
        (widget.isRunning &&
            (widget.step.status == _ActivityStepStatus.running ||
                widget.step.status == _ActivityStepStatus.failed));
  }

  @override
  void didUpdateWidget(covariant _ActivityStepTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final _ActivityStepStatus oldStatus = oldWidget.step.status;
    final _ActivityStepStatus status = widget.step.status;
    final bool statusChanged = oldStatus != status;
    final bool runResumed = !oldWidget.isRunning && widget.isRunning;
    final bool runEnded = oldWidget.isRunning && !widget.isRunning;
    final bool completed = !oldWidget.isRunCompleted && widget.isRunCompleted;
    final bool expandedNow = !oldWidget.forceExpanded && widget.forceExpanded;
    final bool collapsedNow = oldWidget.forceExpanded && !widget.forceExpanded;

    if (runEnded || completed || collapsedNow) {
      _controller.collapse();
    } else if (expandedNow) {
      _controller.expand();
    } else if (widget.isRunning &&
        (runResumed || statusChanged) &&
        (status == _ActivityStepStatus.running ||
            status == _ActivityStepStatus.failed)) {
      _controller.expand();
    } else if (widget.isRunning &&
        statusChanged &&
        (status == _ActivityStepStatus.completed ||
            status == _ActivityStepStatus.warning)) {
      _controller.collapse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final _ActivityStep step = widget.step;
    final AppPalette palette = widget.palette;
    final bool running = step.status == _ActivityStepStatus.running;
    final bool failed = step.status == _ActivityStepStatus.failed;
    final ThemeData theme = Theme.of(context);
    final Color accent = failed
        ? palette.error
        : step.status == _ActivityStepStatus.warning
        ? palette.warning
        : running
        ? palette.primary
        : palette.success;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfaceContainer.withValues(
          alpha: running ? 0.60 : 0.30,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: running
              ? palette.primary.withValues(alpha: 0.48)
              : palette.outline.withValues(alpha: 0.38),
        ),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          controller: _controller,
          onExpansionChanged: (bool expanded) {
            if (_expanded == expanded || !mounted) return;
            setState(() => _expanded = expanded);
          },
          initiallyExpanded:
              widget.forceExpanded ||
              (widget.isRunning &&
                  (step.status == _ActivityStepStatus.running ||
                      step.status == _ActivityStepStatus.failed)),
          tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
          childrenPadding: const EdgeInsets.fromLTRB(43, 0, 12, 10),
          leading: SizedBox(
            width: 22,
            child: running
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: Padding(
                      padding: const EdgeInsets.all(1),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accent,
                      ),
                    ),
                  )
                : Icon(
                    failed
                        ? Icons.error_outline_rounded
                        : step.status == _ActivityStepStatus.warning
                        ? Icons.info_outline_rounded
                        : Icons.check_circle_outline_rounded,
                    size: 17,
                    color: accent,
                  ),
          ),
          title: Text(
            step.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: step.detail.trim().isEmpty
              ? null
              : Text(
                  step.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.textSecondary,
                    height: 1.3,
                  ),
                ),
          trailing: running
              ? Padding(
                  padding: const EdgeInsets.only(left: 8, top: 1),
                  child: Text(
                    widget.isChinese ? '进行中' : 'Running',
                    style: theme.textTheme.labelSmall?.copyWith(color: accent),
                  ),
                )
              : Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: palette.textSecondary,
                ),
          children: <Widget>[
            if (step.detail.trim().isNotEmpty)
              _ActivityDetailBox(
                text: 'detail: ${step.detail}',
                palette: palette,
              ),
          ],
        ),
      ),
    );
  }
}

enum _ProtocolCardKind { stream, resume }

enum _ProtocolCardStatus { running, completed, failed }

class _ProtocolCard {
  const _ProtocolCard({
    required this.kind,
    required this.status,
    required this.title,
    required this.subtitle,
    required this.event,
  });

  final _ProtocolCardKind kind;
  final _ProtocolCardStatus status;
  final String title;
  final String subtitle;
  final AiRunEvent event;

  _ProtocolCard copyWith({
    _ProtocolCardStatus? status,
    String? subtitle,
    AiRunEvent? event,
  }) => _ProtocolCard(
    kind: kind,
    status: status ?? this.status,
    title: title,
    subtitle: subtitle ?? this.subtitle,
    event: event ?? this.event,
  );
}

class _ProtocolCardTile extends StatefulWidget {
  const _ProtocolCardTile({
    super.key,
    required this.card,
    required this.palette,
    required this.isChinese,
    required this.isRunning,
    required this.isRunCompleted,
    required this.forceExpanded,
  });

  final _ProtocolCard card;
  final AppPalette palette;
  final bool isChinese;
  final bool isRunning;
  final bool isRunCompleted;
  final bool forceExpanded;

  @override
  State<_ProtocolCardTile> createState() => _ProtocolCardTileState();
}

class _ProtocolCardTileState extends State<_ProtocolCardTile> {
  late final ExpansibleController _controller;
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _controller = ExpansibleController();
    _expanded =
        widget.forceExpanded ||
        (widget.isRunning &&
            (widget.card.status == _ProtocolCardStatus.running ||
                widget.card.status == _ProtocolCardStatus.failed));
  }

  @override
  void didUpdateWidget(covariant _ProtocolCardTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final _ProtocolCardStatus oldStatus = oldWidget.card.status;
    final _ProtocolCardStatus status = widget.card.status;
    final bool statusChanged = oldStatus != status;
    final bool runResumed = !oldWidget.isRunning && widget.isRunning;
    final bool runEnded = oldWidget.isRunning && !widget.isRunning;
    final bool completed = !oldWidget.isRunCompleted && widget.isRunCompleted;
    final bool expandedNow = !oldWidget.forceExpanded && widget.forceExpanded;
    final bool collapsedNow = oldWidget.forceExpanded && !widget.forceExpanded;

    if (runEnded || completed || collapsedNow) {
      _controller.collapse();
    } else if (expandedNow) {
      _controller.expand();
    } else if (widget.isRunning &&
        (runResumed || statusChanged) &&
        (status == _ProtocolCardStatus.running ||
            status == _ProtocolCardStatus.failed)) {
      _controller.expand();
    } else if (widget.isRunning &&
        statusChanged &&
        status == _ProtocolCardStatus.completed) {
      _controller.collapse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final _ProtocolCard card = widget.card;
    final AppPalette palette = widget.palette;
    final ThemeData theme = Theme.of(context);
    final bool failed = card.status == _ProtocolCardStatus.failed;
    final bool running = card.status == _ProtocolCardStatus.running;
    final Color accent = failed
        ? palette.error
        : card.kind == _ProtocolCardKind.resume
        ? palette.primary
        : palette.textSecondary;
    final AiRunEvent event = card.event;
    final List<String> logLines = <String>[
      if (event.runId.trim().isNotEmpty) 'runId: ${event.runId}',
      if (event.attempt != null)
        'attempt: ${event.attempt} / ${event.maxAttempts ?? 3}',
      if (event.lastSequence != null) 'lastSequence: ${event.lastSequence}',
      if (event.sequenceNumber != null) 'sequence: ${event.sequenceNumber}',
      if (event.replay != null)
        'replay: ${event.replay == true ? 'enabled' : 'disabled'}',
      if (event.duplicateUserMessagePrevented)
        _text('重复用户消息：已阻止', 'duplicate user message: prevented'),
      if (event.partialOutputRetained)
        _text('部分输出：已保留', 'partial output: retained'),
      if (event.rawType != null) 'event: ${event.rawType}',
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfaceContainer.withValues(
          alpha: running ? 0.56 : 0.38,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: failed
              ? palette.error.withValues(alpha: 0.62)
              : palette.outline.withValues(alpha: 0.52),
        ),
      ),
      child: ExpansionTile(
        controller: _controller,
        onExpansionChanged: (bool expanded) {
          if (_expanded == expanded || !mounted) return;
          setState(() => _expanded = expanded);
        },
        initiallyExpanded:
            widget.forceExpanded ||
            (widget.isRunning &&
                (card.status == _ProtocolCardStatus.running ||
                    card.status == _ProtocolCardStatus.failed)),
        tilePadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 1),
        childrenPadding: const EdgeInsets.fromLTRB(44, 0, 12, 10),
        leading: _ProtocolIcon(
          status: card.status,
          kind: card.kind,
          color: accent,
        ),
        title: Text(
          card.title,
          style: theme.textTheme.bodySmall?.copyWith(
            color: palette.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            card.subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: failed ? palette.error : palette.textSecondary,
              height: 1.3,
            ),
          ),
        ),
        trailing: running
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: accent),
              )
            : Icon(
                failed
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                size: 18,
                color: accent,
              ),
        children: logLines.isEmpty
            ? const <Widget>[]
            : <Widget>[
                _ActivityDetailBox(
                  palette: palette,
                  text: logLines.join('\n'),
                  monospace: true,
                ),
              ],
      ),
    );
  }

  String _text(String zh, String en) => widget.isChinese ? zh : en;
}

class _ActivityDetailBox extends StatelessWidget {
  const _ActivityDetailBox({
    required this.text,
    required this.palette,
    this.monospace = false,
  });

  final String text;
  final AppPalette palette;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: palette.surfaceVariant.withValues(alpha: 0.48),
        border: Border(
          left: BorderSide(
            color: palette.outline.withValues(alpha: 0.52),
            width: 2,
          ),
        ),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: palette.textSecondary,
          height: 1.45,
          fontFamily: monospace ? 'monospace' : null,
        ),
      ),
    );
  }
}

class _ProtocolIcon extends StatelessWidget {
  const _ProtocolIcon({
    required this.status,
    required this.kind,
    required this.color,
  });

  final _ProtocolCardStatus status;
  final _ProtocolCardKind kind;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (status == _ProtocolCardStatus.running) {
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      );
    }
    return Icon(
      status == _ProtocolCardStatus.failed
          ? Icons.link_off_rounded
          : kind == _ProtocolCardKind.resume
          ? Icons.refresh_rounded
          : Icons.link_rounded,
      color: color,
      size: 20,
    );
  }
}
