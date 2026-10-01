import 'package:flutter/material.dart';

/// Presentation timing only. Never use these durations to delay business work.
abstract final class AppMotion {
  static const feedback = Duration(milliseconds: 160);
  static const content = Duration(milliseconds: 200);
  static const menu = Duration(milliseconds: 180);
  static const exit = Duration(milliseconds: 140);
  static const panel = Duration(milliseconds: 240);
  static const scroll = Duration(milliseconds: 280);
  static const curve = Curves.easeOutCubic;
  static const exitCurve = Curves.easeInCubic;

  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);

  static Duration duration(BuildContext context, [Duration value = feedback]) =>
      reduced(context) ? Duration.zero : value;

  static AnimationStyle menuStyle(BuildContext context) => AnimationStyle(
    duration: duration(context, menu),
    reverseDuration: duration(context, exit),
    curve: curve,
    reverseCurve: exitCurve,
  );

  static AnimationStyle panelStyle(BuildContext context) => AnimationStyle(
    duration: duration(context, panel),
    reverseDuration: duration(context, menu),
    curve: curve,
    reverseCurve: exitCurve,
  );
}
