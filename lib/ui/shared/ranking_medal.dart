import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';

/// Rank ornament drawn as vectors, with a neutral badge for zero counts.
class RankingMedal extends StatelessWidget {
  const RankingMedal({
    super.key,
    required this.rank,
    required this.decorated,
    required this.size,
    required this.labelKey,
  });
  static const gold = Color(0xFFFFB43B);
  static const silver = Color(0xFF93AEC4);
  static const bronze = Color(0xFFF2986B);
  final int rank;
  final bool decorated;
  final double size;
  final Key labelKey;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = switch (rank) {
      1 => gold,
      2 => silver,
      _ => bronze,
    };
    return SizedBox(
      width: size,
      height: size * 1.15,
      child: CustomPaint(
        painter: decorated ? _MedalPainter(color) : null,
        child: Center(
          child: Container(
            width: size * 0.8,
            height: size * 0.8,
            alignment: Alignment.center,
            decoration: decorated
                ? null
                : BoxDecoration(
                    color: palette.surfaceContainer,
                    shape: BoxShape.circle,
                  ),
            child: Text(
              '$rank',
              key: labelKey,
              textScaler: TextScaler.noScaling,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontSize: size * 0.36,
                fontWeight: FontWeight.w800,
                color: decorated ? Colors.white : palette.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MedalPainter extends CustomPainter {
  const _MedalPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 115);
    final crown = Path()
      ..moveTo(19, 35)
      ..lineTo(12, 15)
      ..lineTo(34, 24)
      ..lineTo(50, 4)
      ..lineTo(66, 24)
      ..lineTo(88, 15)
      ..lineTo(81, 35)
      ..close();
    canvas.drawPath(
      crown,
      Paint()..color = Color.lerp(color, Colors.white, 0.3)!,
    );
    for (final tip in [
      const Offset(12, 15),
      const Offset(50, 4),
      const Offset(88, 15),
    ]) {
      canvas.drawCircle(tip, 4, Paint()..color = color);
    }
    final ribbons = Path()
      ..moveTo(20, 77)
      ..lineTo(28, 110)
      ..lineTo(40, 100)
      ..lineTo(50, 107)
      ..lineTo(60, 100)
      ..lineTo(72, 110)
      ..lineTo(80, 77)
      ..close();
    canvas.drawPath(ribbons, Paint()..color = color);
    const center = Offset(50, 57.5);
    canvas.drawCircle(
      center,
      41,
      Paint()..color = Color.lerp(color, Colors.white, 0.4)!,
    );
    canvas.drawCircle(
      center,
      35,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, Colors.black, 0.15)!],
        ).createShader(const Rect.fromLTWH(15, 22.5, 70, 70)),
    );
    canvas.drawCircle(
      center,
      35,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MedalPainter oldDelegate) => oldDelegate.color != color;
}
