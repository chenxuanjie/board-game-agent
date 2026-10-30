import 'package:flutter/material.dart';

import '../../core/localization/app_copy.dart';
import '../../core/theme/app_palette.dart';

/// Reserved visual entry. Camera access and scanning are not connected yet.
class MobileScanPlaceholder extends StatelessWidget {
  const MobileScanPlaceholder({super.key, required this.copy});

  final AppCopy copy;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('mobile-scan-placeholder'),
    tooltip: copy.localized('扫一扫（暂未开放）', 'Scan (coming soon)'),
    onPressed: null,
    constraints: const BoxConstraints.tightFor(width: 48, height: 48),
    style: IconButton.styleFrom(
      disabledForegroundColor: AppPalette.of(context).textPrimary,
    ),
    icon: const Icon(Icons.qr_code_scanner_rounded, size: 24),
  );
}
