import 'package:flutter/material.dart';

import '../models/color_scheme_option.dart';

class AppPalette {
  const AppPalette({
    required this.scheme,
    required this.nameZh,
    required this.nameEn,
    required this.scaffoldBackground,
    required this.primaryGradient,
    required this.homeSurface,
    required this.homeSearchBackground,
    required this.homeSearchHint,
    required this.homeTextPrimary,
    required this.homeTextSecondary,
    required this.cardSurface,
    required this.cardBorder,
    required this.cardShadow,
    required this.aiPrimary,
    required this.aiSecondary,
    required this.accentPrimary,
    required this.accentSecondary,
    required this.rankChip,
    required this.detailSurface,
    required this.detailOverlayTop,
    required this.detailOverlayMid,
    required this.detailOverlayBottom,
    required this.buttonOutline,
    required this.buttonFill,
    required this.buttonText,
    required this.inputFill,
    required this.messageUserBubble,
    required this.messageAssistantBubble,
    required this.messageAssistantText,
    required this.splashBackground,
  });

  final ColorSchemeOption scheme;
  final String nameZh;
  final String nameEn;
  final Color scaffoldBackground;
  final List<Color> primaryGradient;
  final Color homeSurface;
  final Color homeSearchBackground;
  final Color homeSearchHint;
  final Color homeTextPrimary;
  final Color homeTextSecondary;
  final Color cardSurface;
  final Color cardBorder;
  final Color cardShadow;
  final Color aiPrimary;
  final Color aiSecondary;
  final Color accentPrimary;
  final Color accentSecondary;
  final Color rankChip;
  final Color detailSurface;
  final Color detailOverlayTop;
  final Color detailOverlayMid;
  final Color detailOverlayBottom;
  final Color buttonOutline;
  final Color buttonFill;
  final Color buttonText;
  final Color inputFill;
  final Color messageUserBubble;
  final Color messageAssistantBubble;
  final Color messageAssistantText;
  final Color splashBackground;
}
