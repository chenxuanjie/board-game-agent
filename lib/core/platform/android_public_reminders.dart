import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Cancels pending platform-call deadlines when their owner is disposed.
final class ReminderCancellation {
  final Set<void Function()> _callbacks = {};
  bool _cancelled = false;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final callback in _callbacks.toList()) {
      callback();
    }
    _callbacks.clear();
  }
}

/// Android-only, anonymous system-scheduled public release reminders.
abstract final class AndroidPublicReminders {
  static const _channel = MethodChannel('board_game_agent/public_reminders');
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<T> _bounded<T>(
    Future<T> operation,
    Duration limit,
    ReminderCancellation? cancellation,
  ) {
    final result = Completer<T>();
    late final Timer timer;
    late final void Function() cancel;
    void finishError(Object error, StackTrace stack) {
      if (result.isCompleted) return;
      timer.cancel();
      cancellation?._callbacks.remove(cancel);
      result.completeError(error, stack);
    }

    cancel = () => finishError(
      StateError('Reminder operation cancelled'),
      StackTrace.current,
    );
    timer = Timer(
      limit,
      () => finishError(
        TimeoutException('Reminder operation timed out', limit),
        StackTrace.current,
      ),
    );
    if (cancellation?._cancelled == true) {
      cancel();
    } else {
      cancellation?._callbacks.add(cancel);
    }
    operation.then((value) {
      if (result.isCompleted) return;
      timer.cancel();
      cancellation?._callbacks.remove(cancel);
      result.complete(value);
    }, onError: finishError);
    return result.future;
  }

  static Future<void> configure(
    Uri origin,
    bool checkUpdates, {
    ReminderCancellation? cancellation,
  }) async {
    if (!supported) return;
    await _bounded(
      _channel.invokeMethod<void>('configure', {
        'origin': origin.origin,
        'checkUpdates': checkUpdates,
      }),
      const Duration(seconds: 5),
      cancellation,
    );
  }

  static Future<({bool enabled, bool allowed})> state({
    ReminderCancellation? cancellation,
  }) async {
    if (!supported) return (enabled: false, allowed: false);
    final raw = await _bounded(
      _channel.invokeMapMethod<String, dynamic>('state'),
      const Duration(seconds: 5),
      cancellation,
    );
    return (enabled: raw?['enabled'] == true, allowed: raw?['allowed'] == true);
  }

  static Future<void> setEnabled(
    bool enabled, {
    ReminderCancellation? cancellation,
  }) async {
    if (!supported) return;
    await _bounded(
      _channel.invokeMethod<void>(enabled ? 'enable' : 'disable'),
      enabled ? const Duration(minutes: 2) : const Duration(seconds: 5),
      cancellation,
    );
  }
}
