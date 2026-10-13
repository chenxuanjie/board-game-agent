import 'package:flutter/material.dart';
import 'dart:async';
import '../../core/theme/app_motion.dart';

final _activeModals = Expando<Set<String>>();

/// Observe the standard Flutter popup route rather than copying its engine.
class AppMenuLifetime {
  TransitionRoute<dynamic>? _route;
  void capture(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route is TransitionRoute<dynamic>) _route = route;
  }

  Future<void> get closed async {
    await _route?.completed;
  }
}

/// Keep the guard through the reverse animation, including rapid reopen taps.
Future<T?> presentAppModal<T>({
  required BuildContext context,
  required String kind,
  required TransitionRoute<T> route,
  bool rootNavigator = true,
}) async {
  final navigator = Navigator.of(context, rootNavigator: rootNavigator);
  final active = _activeModals[navigator] ??= <String>{};
  if (!active.add(kind)) return null;
  unawaited(
    route.completed.then<void>(
      (_) {
        active.remove(kind);
      },
      onError: (Object _, StackTrace _) {
        active.remove(kind);
      },
    ),
  );
  try {
    // Return the choice immediately. Only the entry guard waits for exit.
    return await navigator.push<T>(route);
  } catch (_) {
    active.remove(kind);
    rethrow;
  }
}

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  AnimationStyle? animationStyle,
  bool barrierDismissible = true,
}) => presentAppModal<T>(
  context: context,
  kind: 'dialog',
  route: DialogRoute<T>(
    context: context,
    builder: builder,
    themes: InheritedTheme.capture(
      from: context,
      to: Navigator.of(context, rootNavigator: true).context,
    ),
    barrierDismissible: barrierDismissible,
    animationStyle: animationStyle ?? AppMotion.menuStyle(context),
  ),
);

Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  bool? showDragHandle,
  AnimationStyle? sheetAnimationStyle,
}) => presentAppModal<T>(
  context: context,
  kind: 'sheet',
  rootNavigator: false,
  route: ModalBottomSheetRoute<T>(
    builder: builder,
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: Navigator.of(context).context,
    ),
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    showDragHandle: showDragHandle,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    modalBarrierColor: Theme.of(context).bottomSheetTheme.modalBarrierColor,
    sheetAnimationStyle: sheetAnimationStyle ?? AppMotion.panelStyle(context),
  ),
);
