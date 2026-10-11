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
    this.crownOnly = false,
  });
  static const gold = Color(0xFFFFB43B);
  static const silver = Color(0xFF93AEC4);
  static const bronze = Color(0xFFF2986B);
  final int rank;
  final bool decorated;
  final double size;
  final Key labelKey;
  final bool crownOnly;

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
        painter: decorated
            ? crownOnly
                  ? _CrownPainter(color)
                  : _MedalPainter(color)
            : null,
        child: Center(
          child: Container(
            width: size * 0.8,
            height: size * 0.8,
            alignment: Alignment.center,
            decoration: decorated || crownOnly
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
                fontSize: size * (crownOnly ? 0.55 : 0.36),
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

class _CrownPainter extends CustomPainter {
  const _CrownPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 115);
    final crown = Path()
      ..moveTo(12, 24)
      ..lineTo(30, 40)
      ..lineTo(50, 8)
      ..lineTo(70, 40)
      ..lineTo(88, 24)
      ..lineTo(79, 96)
      ..quadraticBezierTo(50, 103, 21, 96)
      ..close();
    canvas.drawShadow(crown, color.withValues(alpha: 0.25), 3, false);
    canvas.drawPath(
      crown,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(color, Colors.white, 0.25)!,
            Color.lerp(color, Colors.black, 0.25)!,
          ],
        ).createShader(const Rect.fromLTWH(0, 0, 100, 100)),
    );
    for (final tip in [
      const Offset(12, 24),
      const Offset(50, 8),
      const Offset(88, 24),
    ]) {
      canvas.drawCircle(
        tip,
        6,
        Paint()..color = Color.lerp(color, Colors.white, 0.2)!,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CrownPainter oldDelegate) => oldDelegate.color != color;
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
