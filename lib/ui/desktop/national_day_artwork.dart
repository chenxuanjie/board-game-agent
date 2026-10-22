part of 'national_day_page.dart';

class _HolidayTitle extends StatelessWidget {
  const _HolidayTitle();

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: const _TitleFlourishes(),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.topCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _display('国庆聚会', 80),
          _display('桌游清单', 112),
          const SizedBox(height: 9),
          Transform.rotate(
            angle: -.055,
            child: const Text(
              'dde，敢来吗？',
              style: TextStyle(
                fontFamily: 'National Day Display',
                fontSize: 46,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w500,
                color: _wine,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _display(String text, double size) => ShaderMask(
    shaderCallback: (bounds) => const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFFF7535), Color(0xFFB50505)],
    ).createShader(bounds),
    blendMode: BlendMode.srcIn,
    child: Text(
      text,
      style: TextStyle(
        fontFamily: 'National Day Display',
        fontSize: size,
        fontWeight: FontWeight.w900,
        height: 1.18,
        letterSpacing: 3,
        color: Colors.white,
      ),
    ),
  );
}

class _TitleFlourishes extends CustomPainter {
  const _TitleFlourishes();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFF57524)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final (center, radius) in [
      (const Offset(95, 78), 18.0),
      (const Offset(487, 80), 12.0),
      (const Offset(54, 158), 15.0),
      (const Offset(548, 155), 18.0),
    ]) {
      for (var i = 0; i < 8; i++) {
        final direction = Offset(
          math.cos(i * math.pi / 4),
          math.sin(i * math.pi / 4),
        );
        canvas.drawLine(
          center + direction * 7,
          center + direction * radius,
          paint,
        );
      }
    }
    canvas.drawPath(
      Path()
        ..moveTo(164, 316)
        ..quadraticBezierTo(352, 274, 505, 294)
        ..quadraticBezierTo(476, 310, 355, 328),
      paint..strokeWidth = 3,
    );
    canvas.drawLine(const Offset(521, 262), const Offset(527, 245), paint);
    canvas.drawLine(const Offset(536, 271), const Offset(553, 253), paint);
    canvas.drawLine(const Offset(547, 279), const Offset(568, 274), paint);
  }

  @override
  bool shouldRepaint(_TitleFlourishes oldDelegate) => false;
}

class _DashedFrame extends CustomPainter {
  const _DashedFrame();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(25),
        ).deflate(6),
      );
    final paint = Paint()
      ..color = const Color(0xFFDE9A6E)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    for (final metric in path.computeMetrics()) {
      for (double offset = 0; offset < metric.length; offset += 12) {
        canvas.drawPath(
          metric.extractPath(offset, math.min(offset + 7, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DashedFrame oldDelegate) => false;
}
