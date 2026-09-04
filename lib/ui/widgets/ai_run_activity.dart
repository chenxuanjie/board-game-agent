import 'package:flutter/material.dart';

import '../../models/ai_run.dart';
import '../../models/rule_citation.dart';
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
    this.contextKey,
    this.initialExpanded,
    this.onExpandedChanged,
  });

  final List<AiRunEvent> events;
  final bool isRunning;
  final AppPalette palette;
  final AppCopy copy;
  final String? contextKey;
  final bool? initialExpanded;
  final ValueChanged<bool>? onExpandedChanged;

  @override
  Widget build(BuildContext context) {
    if (!isRunning && events.isEmpty) {
      return const SizedBox.shrink();
    }

    final List<_ActivityStep> steps = _steps;
    final bool hasTimeline = steps.isNotEmpty;
    final bool isRunCompleted =
        !isRunning &&
        events.any(
          (AiRunEvent event) => event.type == AiRunEventType.completed,
        );
    Widget buildTimeline(bool expandDetails) {
      return steps.isEmpty
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
      initialExpanded: initialExpanded,
      onExpandedChanged: onExpandedChanged,
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

  List<_ActivityStep> get _steps {
    final Map<String, _ActivityStep> byKey = <String, _ActivityStep>{};
    final List<_ActivityStep> ordered = <_ActivityStep>[];
    final List<String> pendingStageIds = <String>[];
    String? lastStageKey;
    _ActivityStep? active;
    _ActivityStep? connectionStep;
    final List<String> connectionDetails = <String>[];

    _ActivityStep createStage(String id) {
      final _StageMeta meta = _stageMeta(id);
      final String key = 'stage:$id';
      final _ActivityStep step = _ActivityStep(
        key: key,
        runningTitle: meta.runningTitle,
        completedTitle: meta.completedTitle,
        failedTitle: meta.failedTitle,
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

    _ActivityStep ensureConnectionStep() {
      return connectionStep ??= (() {
        final _ActivityStep step = _ActivityStep(
          key: 'connection',
          runningTitle: 'resume',
          completedTitle: 'resume',
          failedTitle: _text('resume 失败', 'resume failed'),
          detail: _text('正在恢复连接', 'Restoring the connection'),
          icon: Icons.refresh_rounded,
        );
        ordered.add(step);
        return step;
      })();
    }

    void addCitation(_ActivityStep step, RuleCitation citation) {
      final String key = _citationKey(citation);
      final bool alreadyAdded = step.citations.any(
        (RuleCitation existing) => _citationKey(existing) == key,
      );
      if (!alreadyAdded) step.citations.add(citation);
    }

    void addInspectedSource(_ActivityStep step, RuleCitation citation) {
      final String key = _citationKey(citation);
      final bool alreadyAdded = step.inspectedSources.any(
        (RuleCitation existing) => _citationKey(existing) == key,
      );
      if (!alreadyAdded) step.inspectedSources.add(citation);
    }

    void updateConnection(AiRunEvent event, _ActivityStepStatus status) {
      // A reconnect belongs to the stage whose response stream was active.
      // Keep it in that stage's detail area instead of presenting a second
      // top-level `resume` row that looks like another answer.
      _ActivityStep? activeStage = active;
      if (activeStage == null) {
        // Some transports batch lifecycle events and can clear the logical
        // pointer before the reconnect event is observed. Recover the latest
        // visibly running stage first, then fall back to the latest stage that
        // was rendered for this run. A run that already has stage context must
        // never grow a second top-level `resume` row just because one event
        // arrived without a stage pointer.
        for (final _ActivityStep candidate in ordered.reversed) {
          if (candidate.status == _ActivityStepStatus.running) {
            activeStage = candidate;
            break;
          }
        }
      }
      activeStage ??= ordered.isEmpty ? null : ordered.last;
      final bool mergedIntoStage = activeStage != null;
      final _ActivityStep step = activeStage ?? ensureConnectionStep();
      if (!mergedIntoStage) {
        step.status = status;
      }
      step.connectionActivity = true;
      step.connectionStatus = status;
      final String detail = _readableConnectionDetail(
        event.detail?.trim() ?? event.errorMessage?.trim() ?? '',
      );
      if (event.attempt != null) {
        final String attempt = _text(
          '第 ${event.attempt} 次尝试（共 ${event.maxAttempts ?? 3} 次）',
          'Attempt ${event.attempt} of ${event.maxAttempts ?? 3}',
        );
        if (!connectionDetails.contains(attempt)) {
          connectionDetails.add(attempt);
        }
      }
      if (detail.isNotEmpty && !connectionDetails.contains(detail)) {
        connectionDetails.add(detail);
      }
      if (connectionDetails.isNotEmpty) {
        step.expandedDetail = connectionDetails.join('\n');
        final String connectionLabel = switch (status) {
          _ActivityStepStatus.failed => _text(
            '无法恢复连接',
            'Unable to restore connection',
          ),
          _ActivityStepStatus.completed => _text(
            '连接已恢复',
            'Connection restored',
          ),
          _ => _text('正在重连', 'Reconnecting'),
        };
        step.detail = connectionLabel;
      }
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

    void completeStage(String id, AiStageResult? result) {
      final _ActivityStep? step =
          byKey['stage:$id'] ?? (id.trim().isEmpty ? null : stageFor(id));
      if (step == null) return;
      final AiStageStatus? status = result?.status;
      final _StageMeta meta = _stageMeta(id);
      step.stageResult = result;
      if (result != null) {
        for (final RuleCitation citation in result.inspectedSources) {
          addInspectedSource(step, citation);
        }
        for (final RuleCitation citation in result.citations) {
          addCitation(step, citation);
        }
      }
      step.status = switch (status) {
        AiStageStatus.failed ||
        AiStageStatus.incomplete => _ActivityStepStatus.failed,
        AiStageStatus.insufficient ||
        AiStageStatus.unavailable ||
        AiStageStatus.skipped => _ActivityStepStatus.warning,
        _ => _ActivityStepStatus.completed,
      };
      step.detail = _stageSummary(id, status, step, meta);
      step.detailLines = _stageDetailLines(id, status, step, result);
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

    // A provider or transport may deliver a stale terminal error while the
    // same run has already committed response.completed. The completed event
    // is authoritative; suppress only the duplicate run-level failure while
    // retaining genuine failed stage results rendered above.
    final bool hasCompletedEvent = orderedEvents.any(
      (AiRunEvent event) => event.type == AiRunEventType.completed,
    );

    for (final AiRunEvent event in orderedEvents) {
      final String stageId = event.stageId?.trim() ?? '';
      switch (event.type) {
        case AiRunEventType.stageStarted:
          startStage(stageId);
          break;
        case AiRunEventType.stageCompleted:
          completeStage(stageId, event.stageResult);
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
              updateActive(_citationSummary(active!.citationCount, 'web'));
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
            updateActive(_citationSummary(active!.citationCount, 'web'));
          }
          break;
        case AiRunEventType.citationAdded:
          final _ActivityStep? step = stageId.isNotEmpty
              ? byKey['stage:$stageId']
              : active ?? (lastStageKey == null ? null : byKey[lastStageKey]);
          if (step != null) {
            final RuleCitation? citation = event.citation;
            if (citation != null) addCitation(step, citation);
            step.citationCount = step.citations.length;
            step.detail = _citationSummary(step.citations.length, stageId);
          }
          break;
        case AiRunEventType.retry:
          updateConnection(event, _ActivityStepStatus.running);
          break;
        case AiRunEventType.responseStreamStarted:
          // Healthy streams stay invisible. A connection row is created only
          // after the first interruption event.
          break;
        case AiRunEventType.responseStreamFailed:
          updateConnection(event, _ActivityStepStatus.running);
          break;
        case AiRunEventType.resumeStarted:
          updateConnection(event, _ActivityStepStatus.running);
          break;
        case AiRunEventType.resumeCompleted:
          updateConnection(event, _ActivityStepStatus.completed);
          break;
        case AiRunEventType.failed:
        case AiRunEventType.incomplete:
        case AiRunEventType.cancelled:
          if (hasCompletedEvent) break;
          if (active != null) {
            active!.status = event.type == AiRunEventType.cancelled
                ? _ActivityStepStatus.warning
                : _ActivityStepStatus.failed;
            final String detail = _readableError(
              event.errorCode,
              event.errorMessage,
            );
            if (detail.isNotEmpty) active!.detail = detail;
            if (detail.isNotEmpty) {
              active!.detailLines = <String>[
                _text('原因：$detail', 'Reason: $detail'),
              ];
            }
            active = null;
            pendingStageIds.clear();
          } else {
            if (connectionStep != null &&
                connectionStep!.status == _ActivityStepStatus.running) {
              updateConnection(
                event,
                event.type == AiRunEventType.cancelled
                    ? _ActivityStepStatus.warning
                    : _ActivityStepStatus.failed,
              );
              break;
            }
            final _ActivityStep? lastStep = lastStageKey == null
                ? null
                : byKey[lastStageKey];
            if (lastStep != null) {
              // A terminal event closes the current stage. Do not append a
              // second "answer incomplete" card for the same failure.
              if (lastStep.status != _ActivityStepStatus.warning) {
                lastStep.status = event.type == AiRunEventType.cancelled
                    ? _ActivityStepStatus.warning
                    : _ActivityStepStatus.failed;
              }
              final String detail = _readableError(
                event.errorCode,
                event.errorMessage,
              );
              if (detail.isNotEmpty) lastStep.detail = detail;
              if (detail.isNotEmpty) {
                lastStep.detailLines = <String>[
                  _text('原因：$detail', 'Reason: $detail'),
                ];
              }
              break;
            }
            if (connectionStep != null) {
              connectionStep!.status = event.type == AiRunEventType.cancelled
                  ? _ActivityStepStatus.warning
                  : _ActivityStepStatus.failed;
              final String detail = _readableError(
                event.errorCode,
                event.errorMessage,
              );
              if (detail.isNotEmpty) connectionStep!.detail = detail;
              break;
            }
            final _ActivityStep step = byKey.putIfAbsent('terminal', () {
              final _ActivityStep value = _ActivityStep(
                key: 'terminal',
                runningTitle: _text('回答未完成', 'Answer incomplete'),
                completedTitle: _text('回答未完成', 'Answer incomplete'),
                failedTitle: _text('回答未完成', 'Answer incomplete'),
                detail: '',
                icon: Icons.error_outline_rounded,
              );
              ordered.add(value);
              return value;
            });
            step.status = event.type == AiRunEventType.cancelled
                ? _ActivityStepStatus.warning
                : _ActivityStepStatus.failed;
            step.detail = _readableError(event.errorCode, event.errorMessage);
            if (step.detail.isNotEmpty) {
              step.detailLines = <String>[
                _text('原因：${step.detail}', 'Reason: ${step.detail}'),
              ];
            }
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
    // A provider may deliver an annotation just after the stage terminal
    // event. Rebuild completed-stage details once more so late citations are
    // still reflected in the same card instead of creating a second one.
    for (final _ActivityStep step in ordered) {
      final AiStageResult? result = step.stageResult;
      if (result == null) continue;
      step.citationCount = step.citations.length;
      step.detail = _stageSummary(
        result.stageId,
        result.status,
        step,
        _stageMeta(result.stageId),
      );
      step.detailLines = _stageDetailLines(
        result.stageId,
        result.status,
        step,
        result,
      );
    }
    // A reconnect must stay inside the same Run timeline. A transport can
    // emit its first interruption without a stageId and create a temporary
    // connection row before the stage event arrives. Once any stage context
    // exists, fold that temporary row into the latest stage and remove it so
    // the UI cannot show both an answer row and a second `resume` row.
    if (connectionStep != null) {
      final _ActivityStep pendingConnection = connectionStep!;
      _ActivityStep? connectionStage;
      for (final _ActivityStep step in ordered.reversed) {
        if (step.key != pendingConnection.key &&
            step.status == _ActivityStepStatus.running) {
          connectionStage = step;
          break;
        }
      }
      if (connectionStage == null) {
        for (final _ActivityStep step in ordered.reversed) {
          if (step.key != pendingConnection.key) {
            connectionStage = step;
            break;
          }
        }
      }
      if (connectionStage != null) {
        final String connectionDetail =
            pendingConnection.expandedDetail?.trim() ?? '';
        if (connectionDetail.isNotEmpty) {
          final List<String> mergedLines = <String>[
            if (connectionStage.expandedDetail?.trim().isNotEmpty ?? false)
              ...connectionStage.expandedDetail!.split('\n'),
            ...connectionDetail.split('\n'),
          ];
          connectionStage.expandedDetail = mergedLines.toSet().join('\n');
        }
        if (pendingConnection.status == _ActivityStepStatus.failed) {
          connectionStage.status = _ActivityStepStatus.failed;
          connectionStage.detail = _text('无法恢复连接', 'Unable to restore connection');
        } else if (pendingConnection.connectionStatus ==
            _ActivityStepStatus.completed) {
          connectionStage.detail = _text('连接已恢复', 'Connection restored');
        }
        ordered.remove(pendingConnection);
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
        failedTitle: _text('问题范围判断未完成', 'Request classification incomplete'),
        runningDetail: _text(
          '确定是否需要查阅桌游资料',
          'Deciding whether game sources are needed',
        ),
        icon: Icons.tune_rounded,
      ),
      'official' => _StageMeta(
        runningTitle: _text('正在查阅官方规则', 'Checking official rules'),
        completedTitle: _text('已查阅官方规则', 'Official rules checked'),
        failedTitle: _text('官方规则查阅未完成', 'Official rules lookup incomplete'),
        runningDetail: _text(
          '从当前桌游资料中查找依据',
          'Looking for evidence in the game sources',
        ),
        icon: Icons.menu_book_rounded,
      ),
      'community' => _StageMeta(
        runningTitle: _text('正在查阅社区资料', 'Checking community sources'),
        completedTitle: _text('已查阅社区资料', 'Community sources checked'),
        failedTitle: _text('社区资料查阅未完成', 'Community lookup incomplete'),
        runningDetail: _text(
          '查找补充说明和实际案例',
          'Looking for clarifications and examples',
        ),
        icon: Icons.forum_outlined,
      ),
      'web' => _StageMeta(
        runningTitle: _text('正在搜索相关资料', 'Searching relevant sources'),
        completedTitle: _text('已完成资料搜索', 'Source search completed'),
        failedTitle: _text('资料搜索未完成', 'Source search incomplete'),
        runningDetail: _text(
          '仅在本地资料不足时联网查找',
          'Searching online only when local sources are insufficient',
        ),
        icon: Icons.public_rounded,
      ),
      'answering' || 'general' || 'fallback' => _StageMeta(
        runningTitle: _text('正在生成回答', 'Generating the answer'),
        completedTitle: _text('回答已生成', 'Answer generated'),
        failedTitle: _text('回答未完成', 'Answer incomplete'),
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
        failedTitle: _text('处理未完成', 'Processing incomplete'),
        runningDetail: _text('正在处理当前请求', 'Processing the request'),
        icon: Icons.auto_awesome_rounded,
      );

  String _stageSummary(
    String id,
    AiStageStatus? status,
    _ActivityStep step,
    _StageMeta meta,
  ) {
    return switch (status) {
      AiStageStatus.insufficient =>
        step.inspectedSources.isEmpty
            ? id == 'community'
                  ? _text('未找到有效补充', 'No useful community supplement found')
                  : _text('未找到可直接引用的内容', 'No directly citable content found')
            : id == 'community'
            ? _text(
                '已检查 ${step.inspectedSources.length} 份资料，未找到有效补充',
                'Checked ${step.inspectedSources.length} sources; no useful supplement found',
              )
            : _text(
                '已检查 ${step.inspectedSources.length} 份资料，未找到可直接引用的内容',
                'Checked ${step.inspectedSources.length} sources; no directly citable content found',
              ),
      AiStageStatus.unavailable ||
      AiStageStatus.skipped => _text('当前范围未启用', 'Not enabled for this scope'),
      AiStageStatus.failed ||
      AiStageStatus.incomplete => _text('这一阶段未完成', 'This stage did not finish'),
      AiStageStatus.answered when step.citations.isNotEmpty => _citationSummary(
        step.citations.length,
        id,
      ),
      AiStageStatus.answered when step.inspectedSources.isNotEmpty => _text(
        '已检查 ${step.inspectedSources.length} 份资料',
        'Checked ${step.inspectedSources.length} sources',
      ),
      AiStageStatus.answered when id == 'general' || id == 'fallback' => _text(
        '普通回答已生成',
        'General answer generated',
      ),
      _ => meta.completedTitle,
    };
  }

  List<String> _stageDetailLines(
    String id,
    AiStageStatus? status,
    _ActivityStep step,
    AiStageResult? result,
  ) {
    final List<String> lines = <String>[];
    if (step.inspectedSources.isNotEmpty) {
      lines.add(
        _text(
          '已检查资料：${step.inspectedSources.length} 份',
          'Inspected sources: ${step.inspectedSources.length}',
        ),
      );
      for (final RuleCitation citation in step.inspectedSources) {
        final String? label = _citationLabel(citation);
        if (label != null) {
          lines.add(_text('资料：$label', 'Source: $label'));
        }
      }
    }
    final List<String> citationLines = <String>[];
    for (final RuleCitation citation in step.citations) {
      citationLines.addAll(_citationLines(citation));
    }
    if (citationLines.isNotEmpty) {
      lines.add(_text('已确认引用', 'Confirmed citations'));
      lines.addAll(citationLines);
    }
    final String error = _readableError(
      result?.errorCode,
      result?.errorMessage,
    );
    if (error.isNotEmpty &&
        (status == AiStageStatus.failed ||
            status == AiStageStatus.incomplete)) {
      lines.add(_text('原因：$error', 'Reason: $error'));
    }
    return lines.toSet().toList(growable: false);
  }

  String _citationSummary(int count, String stageId) {
    if (count <= 0) {
      return stageId == 'web'
          ? _text('搜索已完成，未发现可引用来源', 'Search complete; no citable sources found')
          : _text('尚未确认引用', 'No citation confirmed');
    }
    return stageId == 'web'
        ? _text('找到 $count 个可引用来源', '$count citable sources found')
        : _text('确认引用：$count 个来源', 'Confirmed citations: $count sources');
  }

  String _citationKey(RuleCitation citation) => <String>[
    citation.sourceId,
    citation.page?.toString() ?? '',
    citation.section?.trim() ?? '',
    citation.url?.trim() ?? '',
  ].join('|');

  String? _citationLabel(RuleCitation citation) {
    final String title = citation.title?.trim() ?? '';
    if (title.isNotEmpty) return title;
    final String path = citation.path?.trim() ?? '';
    if (path.isNotEmpty) {
      final int slash = path.lastIndexOf(RegExp(r'[\\/]'));
      return slash >= 0 && slash + 1 < path.length
          ? path.substring(slash + 1)
          : path;
    }
    final Uri? uri = Uri.tryParse(citation.url?.trim() ?? '');
    if (uri != null && uri.host.isNotEmpty) return uri.host;
    return null;
  }

  List<String> _citationLines(RuleCitation citation) {
    final List<String> lines = <String>[];
    final String? label = _citationLabel(citation);
    if (label != null) lines.add(_text('资料：$label', 'Source: $label'));
    final String section = citation.section?.trim() ?? '';
    if (section.isNotEmpty) {
      lines.add(_text('章节：$section', 'Section: $section'));
    }
    if (citation.page != null) {
      lines.add(_text('页码：第 ${citation.page} 页', 'Page: ${citation.page}'));
    }
    final String quote = citation.quote?.trim() ?? '';
    if (quote.isNotEmpty) {
      final String shortened = quote.length <= 220
          ? quote
          : '${quote.substring(0, 217)}…';
      lines.add(_text('引用：$shortened', 'Quote: $shortened'));
    }
    final Uri? uri = Uri.tryParse(citation.url?.trim() ?? '');
    if (uri != null && uri.host.isNotEmpty && label != uri.host) {
      lines.add(_text('来源：${uri.host}', 'Domain: ${uri.host}'));
    }
    return lines;
  }

  String _readableConnectionDetail(String value) {
    if (value == 'response.completed 尚未到达' ||
        value.toLowerCase().contains('response.completed')) {
      return _text(
        '响应尚未完成，连接已中断',
        'The response was interrupted before completion',
      );
    }
    if (value == 'Responses stream ended before response.completed.') {
      return _text('响应流在完成前结束', 'The response stream ended before completion');
    }
    if (value.contains('重新建立事件流')) {
      return _text('已重新建立事件流', 'Event stream restored');
    }
    if (value.contains('sequence')) {
      return _text('已从中断位置继续监听', 'Listening again from the interruption point');
    }
    if (value.contains('AiClientException') ||
        value.contains('SocketException') ||
        value.contains('TimeoutException')) {
      return _readableError(null, value);
    }
    return value;
  }

  String _readableError(String? code, String? message) {
    final String normalized = '${code ?? ''} ${message ?? ''}'.toLowerCase();
    if (normalized.trim().isEmpty) return '';
    if (normalized.contains('401') ||
        normalized.contains('403') ||
        normalized.contains('unauthorized') ||
        normalized.contains('api key') ||
        normalized.contains('authentication')) {
      return _text('模型服务鉴权失败', 'Model service authentication failed');
    }
    if (normalized.contains('404') ||
        normalized.contains('model not found') ||
        normalized.contains('model_not_found') ||
        normalized.contains('no such model')) {
      return _text('模型不可用', 'Model unavailable');
    }
    if (normalized.contains('429') ||
        normalized.contains('rate limit') ||
        normalized.contains('too many requests')) {
      return _text('服务商暂时繁忙，请稍后重试', 'Provider is busy; try again later');
    }
    if (normalized.contains('timeout') || normalized.contains('timed out')) {
      return _text('网络请求超时', 'Network request timed out');
    }
    if (normalized.contains('socket') ||
        normalized.contains('network') ||
        normalized.contains('connection') ||
        normalized.contains('dns')) {
      return _text('网络连接失败', 'Network connection failed');
    }
    if (normalized.contains('500') ||
        normalized.contains('502') ||
        normalized.contains('503') ||
        normalized.contains('504') ||
        normalized.contains('server error')) {
      return _text('服务商暂时不可用', 'Provider temporarily unavailable');
    }
    if (normalized.contains('parse') ||
        normalized.contains('json') ||
        normalized.contains('protocol') ||
        normalized.contains('aiclientexception')) {
      return _text('服务商返回了无法识别的响应', 'Provider returned an unreadable response');
    }
    if (normalized.contains('stage stream ended') ||
        normalized.contains('response stream ended') ||
        normalized.contains('response was incomplete') ||
        normalized.contains('response failed') ||
        normalized.contains('without a validated answer')) {
      return _text('回答未完整生成', 'The answer was not fully generated');
    }
    final String readable = message?.trim() ?? '';
    return readable.length > 180 ? '${readable.substring(0, 177)}…' : readable;
  }

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
    this.initialExpanded,
    this.onExpandedChanged,
    required this.timelineBuilder,
  });

  final String? runId;
  final bool isRunning;
  final bool isCompleted;
  final Duration duration;
  final AppPalette palette;
  final AppCopy copy;
  final bool? initialExpanded;
  final ValueChanged<bool>? onExpandedChanged;
  final Widget Function(bool expandDetails) timelineBuilder;

  @override
  State<_AiRunActivityView> createState() => _AiRunActivityViewState();
}

class _AiRunActivityViewState extends State<_AiRunActivityView> {
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initialExpanded ?? !widget.isCompleted;
  }

  @override
  void didUpdateWidget(covariant _AiRunActivityView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool runChanged =
        widget.runId != null && widget.runId != oldWidget.runId;
    final bool completedNow = !oldWidget.isCompleted && widget.isCompleted;
    if (completedNow) {
      _expanded = false;
      widget.onExpandedChanged?.call(false);
    } else if (runChanged) {
      _expanded = widget.initialExpanded ?? !widget.isCompleted;
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
                onTap: () {
                  final bool next = !_expanded;
                  setState(() => _expanded = next);
                  widget.onExpandedChanged?.call(next);
                },
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
    required this.failedTitle,
    required this.runningDetail,
    required this.icon,
  });

  final String runningTitle;
  final String completedTitle;
  final String failedTitle;
  final String runningDetail;
  final IconData icon;
}

class _ActivityStep {
  _ActivityStep({
    required this.key,
    required this.runningTitle,
    required this.completedTitle,
    required this.failedTitle,
    required this.detail,
    required this.icon,
  });

  final String key;
  final String runningTitle;
  final String completedTitle;
  final String failedTitle;
  final IconData icon;
  String detail;
  String? expandedDetail;
  bool connectionActivity = false;
  _ActivityStepStatus? connectionStatus;
  List<String> detailLines = <String>[];
  AiStageResult? stageResult;
  final List<RuleCitation> inspectedSources = <RuleCitation>[];
  final List<RuleCitation> citations = <RuleCitation>[];
  int citationCount = 0;
  _ActivityStepStatus status = _ActivityStepStatus.running;

  String get title => switch (status) {
    _ActivityStepStatus.running => runningTitle,
    _ActivityStepStatus.failed => failedTitle,
    _ => completedTitle,
  };
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
    final bool running =
        widget.isRunning && step.status == _ActivityStepStatus.running;
    final bool failed = step.status == _ActivityStepStatus.failed;
    final bool hasDetails =
        step.detailLines.isNotEmpty ||
        (step.expandedDetail?.trim().isNotEmpty ?? false);
    final ThemeData theme = Theme.of(context);
    final Color accent = failed
        ? palette.error
        : step.status == _ActivityStepStatus.warning
        ? palette.warning
        : running
        ? palette.primary
        : palette.success;
    return Theme(
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
              ? Center(
                  child: SizedBox.square(
                    dimension: 18,
                    child: Padding(
                      padding: const EdgeInsets.all(1),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accent,
                      ),
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
            : hasDetails
            ? Icon(
                _expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: palette.textSecondary,
              )
            : const SizedBox(width: 20),
        children: <Widget>[
          if (hasDetails)
            _ActivityDetailBox(
              lines: step.expandedDetail?.trim().isNotEmpty ?? false
                  ? <String>[
                      ...step.detailLines,
                      ...step.expandedDetail!.split('\n'),
                    ]
                  : step.detailLines,
              palette: palette,
            ),
        ],
      ),
    );
  }
}

class _ActivityDetailBox extends StatelessWidget {
  const _ActivityDetailBox({required this.lines, required this.palette});

  final List<String> lines;
  final AppPalette palette;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int index = 0; index < lines.length; index++)
            Padding(
              padding: EdgeInsets.only(
                bottom: index == lines.length - 1 ? 0 : 4,
              ),
              child: Text(
                lines[index],
                style: theme.textTheme.labelSmall?.copyWith(
                  color: palette.textSecondary,
                  height: 1.45,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
