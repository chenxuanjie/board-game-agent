import 'package:flutter/material.dart';

import '../../core/localization/app_copy.dart';
import '../../core/theme/app_palette.dart';

/// Reserved visual entry. Camera access and scanning are not connected yet.
class MobileScanPlaceholder extends StatelessWidget {
  const MobileScanPlaceholder({super.key, required this.copy});

  final AppCopy copy;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    const size = 24.0;
    const canvas = 1254.0;
    // Fit the supplied icon's visible strokes, excluding its transparent margin.
    final bounds = const Rect.fromLTRB(378, 415, 877, 897).inflate(8);
    final scale = size / bounds.longestSide;
    return IconButton(
      key: const ValueKey('mobile-scan-placeholder'),
      tooltip: copy.localized('扫一扫（暂未开放）', 'Scan (coming soon)'),
      onPressed: null,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      style: IconButton.styleFrom(disabledForegroundColor: palette.textPrimary),
      icon: SizedBox.square(
        dimension: size,
        child: ClipRect(
          child: Stack(
            children: [
              Positioned(
                left: (size - bounds.width * scale) / 2 - bounds.left * scale,
                top: (size - bounds.height * scale) / 2 - bounds.top * scale,
                width: canvas * scale,
                height: canvas * scale,
                child: Image.asset(
                  'assets/mobile/mine/scan_icon.png',
                  color: palette.textPrimary,
                  colorBlendMode: BlendMode.srcIn,
                  fit: BoxFit.fill,
                  excludeFromSemantics: true,
                  filterQuality: FilterQuality.high,
                  cacheWidth:
                      (canvas * scale * MediaQuery.devicePixelRatioOf(context))
                          .ceil(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
