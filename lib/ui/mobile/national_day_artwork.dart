part of 'national_day_screen.dart';

class _HolidayTitle extends StatelessWidget {
  const _HolidayTitle();
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: .5,
              colors: [Color(0xFFFDE8C6), Color(0xDAFFE5BD), Color(0x00FFE5BD)],
              stops: [0, .5, 1],
            ),
          ),
        ),
        Center(
          child: SizedBox(
            width: constraints.maxWidth * .60,
            child: FittedBox(
              child: SizedBox(
                width: 320,
                height: 210,
                child: MediaQuery.withNoTextScaling(
                  child: CustomPaint(
                    painter: const _TitleFlourishes(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _display('国庆想玩', 58),
                        _display('桌游', 64),
                        Transform.rotate(
                          angle: -.055,
                          child: const Text(
                            'dde，敢来吗？',
                            style: TextStyle(
                              fontFamily: 'National Day Display',
                              fontSize: 29,
                              fontStyle: FontStyle.italic,
                              color: _wine,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _display(String text, double size) => ShaderMask(
    blendMode: BlendMode.srcIn,
    shaderCallback: (bounds) => const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFFF6130), Color(0xFFB80B03)],
    ).createShader(bounds),
    child: Text(
      text,
      style: TextStyle(
        fontFamily: 'National Day Display',
        fontSize: size,
        fontWeight: FontWeight.w900,
        height: 1.1,
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
      ..color = _orange
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final center in [
      const Offset(18, 70),
      const Offset(298, 66),
      const Offset(51, 112),
      const Offset(160, 1),
    ]) {
      for (var i = 0; i < 8; i++) {
        final direction = Offset(
          math.cos(i * math.pi / 4),
          math.sin(i * math.pi / 4),
        );
        canvas.drawLine(center + direction * 4, center + direction * 10, paint);
      }
    }
    canvas.drawPath(
      Path()
        ..moveTo(97, 193)
        ..quadraticBezierTo(210, 163, 274, 173)
        ..quadraticBezierTo(252, 185, 171, 200),
      paint,
    );
    canvas.drawLine(const Offset(275, 145), const Offset(280, 130), paint);
    canvas.drawLine(const Offset(286, 150), const Offset(302, 140), paint);
  }

  @override
  bool shouldRepaint(_TitleFlourishes oldDelegate) => false;
}

class _CloudPanelClipper extends CustomClipper<Path> {
  const _CloudPanelClipper();
  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, 55)
    ..quadraticBezierTo(0, 20, size.width * .15, 30)
    ..quadraticBezierTo(size.width * .22, 3, size.width * .31, 17)
    ..quadraticBezierTo(size.width * .5, -15, size.width * .69, 17)
    ..quadraticBezierTo(size.width * .78, 3, size.width * .85, 30)
    ..quadraticBezierTo(size.width, 20, size.width, 55)
    ..lineTo(size.width, size.height - 24)
    ..quadraticBezierTo(size.width, size.height, size.width - 24, size.height)
    ..lineTo(24, size.height)
    ..quadraticBezierTo(0, size.height, 0, size.height - 24)
    ..close();
  @override
  bool shouldReclip(_CloudPanelClipper oldClipper) => false;
}

class _DashedFrame extends CustomPainter {
  const _DashedFrame();
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(4),
          const Radius.circular(12),
        ),
      );
    final paint = Paint()
      ..color = const Color(0xFFDFB28A)
      ..strokeWidth = .8
      ..style = PaintingStyle.stroke;
    for (final metric in path.computeMetrics()) {
      for (double offset = 0; offset < metric.length; offset += 8) {
        canvas.drawPath(
          metric.extractPath(offset, math.min(offset + 4, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DashedFrame oldDelegate) => false;
}
