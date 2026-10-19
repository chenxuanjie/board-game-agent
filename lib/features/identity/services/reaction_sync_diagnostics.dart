import 'dart:async';
import 'dart:collection';

import 'package:app_identity/app_identity.dart';
import 'package:flutter/foundation.dart';

enum ReactionTraceStatus { running, success, failure, info }

final class ReactionTraceEvent {
  const ReactionTraceEvent(
    this.run,
    this.at,
    this.elapsed,
    this.stage,
    this.status,
    this.detail,
  );
  final int run;
  final DateTime at;
  final Duration elapsed;
  final String stage, detail;
  final ReactionTraceStatus status;
}

/// Bounded, session-only observations. Never accepts credentials or HTTP bodies.
/// The same collector drives the native UI and platform debug output.
final class ReactionSyncDiagnostics extends ChangeNotifier {
  final _events = Queue<ReactionTraceEvent>();
  final _active = <int, ({String stage, Stopwatch clock})>{};
  final _watched = <String>{};
  int _sequence = 0, _generation = 0;
  bool _disposed = false;
  bool visible = false;
  List<ReactionTraceEvent> get events => List.unmodifiable(_events);
  List<String> get activeStages =>
      List.unmodifiable(_active.values.map((run) => run.stage));
  Duration? waitingSince(ReactionTraceEvent event) {
    final run = _active[event.run];
    return run == null ? null : run.clock.elapsed - event.elapsed;
  }

  Set<String> get watchedSlugs => Set.unmodifiable(_watched);

  ReactionTrace start(String stage, {bool show = false, String detail = ''}) {
    if (show) visible = true;
    final trace = ReactionTrace._(this, ++_sequence, _generation, stage);
    trace.event(stage, status: ReactionTraceStatus.running, detail: detail);
    return trace;
  }

  void watch(String slug) {
    if (!RegExp(r'^[a-z0-9_-]{1,128}$').hasMatch(slug)) return;
    _watched.add(slug);
    while (_watched.length > 12) {
      _watched.remove(_watched.first);
    }
  }

  void show() {
    visible = true;
    _notify();
  }

  void hide() {
    visible = false;
    _notify();
  }

  /// Switching identity erases observations and invalidates late old callbacks.
  void reset() {
    _generation++;
    _events.clear();
    _active.clear();
    _watched.clear();
    visible = false;
    _notify();
  }

  static String failureLabel(Object failure) => switch (failure) {
    PrivateFileException() =>
      'NAS ${failure.failure.name}'
          '${failure.code == null ? '' : '，代码 ${failure.code}'}',
    TimeoutException() => '请求或本机提交超时',
    FormatException() => '记录格式不正确',
    _ => '操作失败（${failure.runtimeType}）',
  };

  void _add(
    ReactionTrace trace,
    String stage,
    ReactionTraceStatus status,
    String detail, {
    bool complete = false,
  }) {
    if (_disposed || trace.generation != _generation) return;
    String bounded(String value) {
      final clean = value.replaceAll(RegExp(r'[\r\n\x00-\x1f]'), ' ');
      return clean.length > 240 ? clean.substring(0, 240) : clean;
    }

    final event = ReactionTraceEvent(
      trace.id,
      DateTime.now(),
      trace.clock.elapsed,
      bounded(stage),
      status,
      bounded(detail),
    );
    _events.add(event);
    while (_events.length > 180) {
      _events.removeFirst();
    }
    if (complete) {
      _active.remove(trace.id);
    } else if (status == ReactionTraceStatus.running) {
      _active[trace.id] = (stage: event.stage, clock: trace.clock);
    }
    debugPrint(
      '[reaction-sync #${event.run} +${event.elapsed.inMilliseconds}ms] '
      '${event.status.name} ${event.stage} ${event.detail}',
    );
    _notify();
  }

  String export() => events
      .map(
        (e) =>
            '${e.at.toIso8601String()} #${e.run} +${e.elapsed.inMilliseconds}ms '
            '${e.status.name} ${e.stage}${e.detail.isEmpty ? '' : ' | ${e.detail}'}',
      )
      .join('\n');

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final class ReactionTrace {
  ReactionTrace._(this.owner, this.id, this.generation, this.label);
  final ReactionSyncDiagnostics owner;
  final int id, generation;
  final String label;
  final clock = Stopwatch()..start();
  bool _complete = false;
  void event(
    String stage, {
    ReactionTraceStatus status = ReactionTraceStatus.info,
    String detail = '',
  }) {
    if (!_complete) owner._add(this, stage, status, detail);
  }

  Future<T> measure<T>(
    String stage,
    Future<T> Function() work, {
    String detail = '',
  }) async {
    event(stage, status: ReactionTraceStatus.running, detail: detail);
    final timer = Stopwatch()..start();
    try {
      final result = await work();
      event(
        stage,
        status: result == false
            ? ReactionTraceStatus.failure
            : ReactionTraceStatus.success,
        detail:
            '${timer.elapsedMilliseconds} ms${detail.isEmpty ? '' : ' · $detail'}',
      );
      return result;
    } catch (failure) {
      event(
        stage,
        status: ReactionTraceStatus.failure,
        detail:
            '${timer.elapsedMilliseconds} ms · ${ReactionSyncDiagnostics.failureLabel(failure)}',
      );
      rethrow;
    }
  }

  void finish({String detail = '', bool failed = false}) {
    if (_complete) return;
    owner._add(
      this,
      label,
      failed ? ReactionTraceStatus.failure : ReactionTraceStatus.success,
      detail,
      complete: true,
    );
    _complete = true;
    clock.stop();
  }
}
