import 'package:flutter/material.dart';

import 'spinning_face.dart';

/// Pixel-art style icons for powerups, drawn with CustomPainter.
/// No emoji — just clean vector shapes in the app's trail palette.
class PowerupIcon extends StatelessWidget {
  final String type;
  final double size;
  final bool spinning;
  final Duration spinDuration;

  const PowerupIcon({
    super.key,
    required this.type,
    this.size = 22,
    this.spinning = false,
    this.spinDuration = const Duration(milliseconds: 2800),
  });

  @override
  Widget build(BuildContext context) {
    final icon = SizedBox.square(
      dimension: size,
      child: Center(
        child: CustomPaint(size: Size(size, size), painter: _PowerupPainter(type)),
      ),
    );

    if (!spinning) return icon;

    return SizedBox.square(
      dimension: size,
      child: SpinningFace(duration: spinDuration, child: icon),
    );
  }
}

class _PowerupPainter extends CustomPainter {
  final String type;
  _PowerupPainter(this.type);

  @override
  void paint(Canvas canvas, Size size) {
    switch (type.toUpperCase()) {
      case 'LEG_CRAMP':
        _paintLegCramp(canvas, size);
      case 'RED_CARD':
        _paintRedCard(canvas, size);
      case 'SHORTCUT':
        _paintShortcut(canvas, size);
      case 'COMPRESSION_SOCKS':
        _paintCompressionSocks(canvas, size);
      case 'PROTEIN_SHAKE':
        _paintProteinShake(canvas, size);
      case 'RUNNERS_HIGH':
        _paintRunnersHigh(canvas, size);
      case 'SECOND_WIND':
        _paintSecondWind(canvas, size);
      case 'STEALTH_MODE':
        _paintStealthMode(canvas, size);
      case 'WRONG_TURN':
        _paintWrongTurn(canvas, size);
      case 'FANNY_PACK':
        _paintFannyPack(canvas, size);
      case 'TRAIL_MIX':
        _paintTrailMix(canvas, size);
      case 'DETOUR_SIGN':
        _paintDetourSign(canvas, size);
    }
  }

  @override
  bool shouldRepaint(covariant _PowerupPainter old) => old.type != type;

  void _paintMedallion(
    Canvas canvas,
    Size size, {
    required List<Color> fillColors,
    required Color edgeColor,
    required Color ringColor,
    required Color shadowColor,
  }) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.46;
    final badgeRect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center.translate(0, size.height * 0.03),
      radius,
      Paint()..color = shadowColor.withValues(alpha: 0.22),
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: fillColors,
        ).createShader(badgeRect),
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.075
        ..color = edgeColor,
    );

    canvas.drawCircle(
      center,
      radius * 0.78,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.035
        ..color = ringColor,
    );

    final highlightCenter = Offset(
      center.dx - size.width * 0.12,
      center.dy - size.height * 0.14,
    );
    canvas.drawCircle(
      highlightCenter,
      radius * 0.55,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                Colors.white.withValues(alpha: 0.32),
                Colors.white.withValues(alpha: 0.0),
              ],
            ).createShader(
              Rect.fromCircle(center: highlightCenter, radius: radius * 0.55),
            ),
    );
  }

  // Leg Cramp — icy medallion with a stylized calf and cramp slash.
  void _paintLegCramp(Canvas canvas, Size size) {
    _paintMedallion(
      canvas,
      size,
      fillColors: const [
        Color(0xFFD8F7FF),
        Color(0xFF79C9E8),
        Color(0xFF39759C),
      ],
      edgeColor: const Color(0xFF27546B),
      ringColor: const Color(0xFFB8EEFF),
      shadowColor: const Color(0xFF113348),
    );

    final legPath = Path()
      ..moveTo(size.width * 0.42, size.height * 0.18)
      ..quadraticBezierTo(
        size.width * 0.33,
        size.height * 0.26,
        size.width * 0.38,
        size.height * 0.42,
      )
      ..lineTo(size.width * 0.43, size.height * 0.63)
      ..lineTo(size.width * 0.43, size.height * 0.74)
      ..quadraticBezierTo(
        size.width * 0.43,
        size.height * 0.82,
        size.width * 0.51,
        size.height * 0.82,
      )
      ..lineTo(size.width * 0.74, size.height * 0.82)
      ..quadraticBezierTo(
        size.width * 0.82,
        size.height * 0.82,
        size.width * 0.82,
        size.height * 0.75,
      )
      ..quadraticBezierTo(
        size.width * 0.82,
        size.height * 0.69,
        size.width * 0.74,
        size.height * 0.69,
      )
      ..lineTo(size.width * 0.58, size.height * 0.69)
      ..lineTo(size.width * 0.60, size.height * 0.50)
      ..quadraticBezierTo(
        size.width * 0.62,
        size.height * 0.35,
        size.width * 0.58,
        size.height * 0.24,
      )
      ..quadraticBezierTo(
        size.width * 0.53,
        size.height * 0.15,
        size.width * 0.42,
        size.height * 0.18,
      )
      ..close();

    canvas.drawShadow(
      legPath,
      const Color(0xFF1F4156).withValues(alpha: 0.35),
      size.width * 0.03,
      false,
    );

    canvas.drawPath(legPath, Paint()..color = const Color(0xFFF5FCFF));
    canvas.drawPath(
      legPath,
      Paint()
        ..color = const Color(0xFFD7EDF6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.03
        ..strokeJoin = StrokeJoin.round,
    );

    final shinHighlight = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..strokeWidth = size.width * 0.035
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.49, size.height * 0.28),
      Offset(size.width * 0.50, size.height * 0.61),
      shinHighlight,
    );

    final crampBolt = Path()
      ..moveTo(size.width * 0.31, size.height * 0.39)
      ..lineTo(size.width * 0.50, size.height * 0.37)
      ..lineTo(size.width * 0.44, size.height * 0.50)
      ..lineTo(size.width * 0.61, size.height * 0.48)
      ..lineTo(size.width * 0.47, size.height * 0.69)
      ..lineTo(size.width * 0.51, size.height * 0.56)
      ..lineTo(size.width * 0.35, size.height * 0.57)
      ..close();
    canvas.drawPath(crampBolt, Paint()..color = const Color(0xFF214C67));
    canvas.drawPath(
      crampBolt,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.025
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFFBDF6FF).withValues(alpha: 0.75),
    );
  }

  // Red Card — rectangular card shape
  void _paintRedCard(Canvas canvas, Size size) {
    _paintMedallion(
      canvas,
      size,
      fillColors: const [
        Color(0xFFFFCEC8),
        Color(0xFFE34E46),
        Color(0xFF731619),
      ],
      edgeColor: const Color(0xFF4D0C12),
      ringColor: const Color(0xFFFFDDD8),
      shadowColor: const Color(0xFF240609),
    );

    final accentPath = Path()
      ..moveTo(size.width * 0.22, size.height * 0.68)
      ..lineTo(size.width * 0.39, size.height * 0.24)
      ..lineTo(size.width * 0.57, size.height * 0.30)
      ..lineTo(size.width * 0.40, size.height * 0.74)
      ..close();
    canvas.drawPath(
      accentPath,
      Paint()..color = const Color(0xFFFFF1DA).withValues(alpha: 0.92),
    );

    final center = Offset(size.width / 2, size.height / 2);
    final cardRect = Rect.fromCenter(
      center: Offset.zero,
      width: size.width * 0.35,
      height: size.height * 0.54,
    );
    final cardRRect = RRect.fromRectAndRadius(
      cardRect,
      Radius.circular(size.width * 0.04),
    );

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.22);

    canvas.drawRRect(
      cardRRect.shift(Offset(size.width * 0.03, size.height * 0.03)),
      Paint()..color = const Color(0xFF30080A).withValues(alpha: 0.28),
    );

    canvas.drawRRect(
      cardRRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF7C72), Color(0xFFE1362B), Color(0xFFAC1817)],
        ).createShader(cardRect),
    );

    canvas.drawRRect(
      cardRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.03
        ..color = const Color(0xFF5C0C12),
    );

    final innerHighlight = RRect.fromRectAndRadius(
      cardRect.deflate(size.width * 0.03),
      Radius.circular(size.width * 0.03),
    );
    canvas.drawRRect(
      innerHighlight,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.016
        ..color = const Color(0xFFFFD3CC).withValues(alpha: 0.85),
    );

    final sheenPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = size.width * 0.028
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(-size.width * 0.11, -size.height * 0.16),
      Offset(size.width * 0.05, -size.height * 0.02),
      sheenPaint,
    );

    canvas.restore();
  }

  // Shortcut — diagonal arrow cutting across
  void _paintShortcut(Canvas canvas, Size size) {
    _paintMedallion(
      canvas,
      size,
      fillColors: const [
        Color(0xFFE4F5D8),
        Color(0xFF84B66A),
        Color(0xFF345A2F),
      ],
      edgeColor: const Color(0xFF1E3A20),
      ringColor: const Color(0xFFDFF3C7),
      shadowColor: const Color(0xFF142716),
    );

    final routeShadow = Paint()
      ..color = const Color(0xFF244225).withValues(alpha: 0.22)
      ..strokeWidth = size.width * 0.15
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final routePaint = Paint()
      ..color = const Color(0xFFF7EAC9)
      ..strokeWidth = size.width * 0.13
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final routeEdge = Paint()
      ..color = const Color(0xFFD3BE8D)
      ..strokeWidth = size.width * 0.03
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final routePath = Path()
      ..moveTo(size.width * 0.24, size.height * 0.72)
      ..quadraticBezierTo(
        size.width * 0.22,
        size.height * 0.53,
        size.width * 0.39,
        size.height * 0.50,
      )
      ..quadraticBezierTo(
        size.width * 0.58,
        size.height * 0.47,
        size.width * 0.53,
        size.height * 0.28,
      )
      ..quadraticBezierTo(
        size.width * 0.50,
        size.height * 0.17,
        size.width * 0.66,
        size.height * 0.20,
      )
      ..quadraticBezierTo(
        size.width * 0.78,
        size.height * 0.23,
        size.width * 0.79,
        size.height * 0.34,
      );

    canvas.drawPath(
      routePath.shift(Offset(size.width * 0.015, size.height * 0.02)),
      routeShadow,
    );
    canvas.drawPath(routePath, routePaint);
    canvas.drawPath(routePath, routeEdge);

    final breakPaint = Paint()
      ..color = const Color(0xFF648A52)
      ..strokeWidth = size.width * 0.19
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(size.width * 0.40, size.height * 0.56),
      Offset(size.width * 0.56, size.height * 0.41),
      breakPaint,
    );

    final arrowPath = Path()
      ..moveTo(size.width * 0.27, size.height * 0.72)
      ..lineTo(size.width * 0.48, size.height * 0.56)
      ..lineTo(size.width * 0.46, size.height * 0.65)
      ..lineTo(size.width * 0.76, size.height * 0.31)
      ..lineTo(size.width * 0.64, size.height * 0.33)
      ..lineTo(size.width * 0.69, size.height * 0.18)
      ..lineTo(size.width * 0.85, size.height * 0.29)
      ..lineTo(size.width * 0.74, size.height * 0.45)
      ..lineTo(size.width * 0.72, size.height * 0.35)
      ..lineTo(size.width * 0.34, size.height * 0.79)
      ..close();

    canvas.drawShadow(
      arrowPath,
      const Color(0xFF52360B).withValues(alpha: 0.35),
      size.width * 0.03,
      false,
    );
    canvas.drawPath(
      arrowPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE39C), Color(0xFFE0A43A), Color(0xFF925414)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    canvas.drawPath(
      arrowPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.028
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFF6A3E11),
    );

    final arrowHighlight = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = size.width * 0.025
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.38, size.height * 0.67),
      Offset(size.width * 0.67, size.height * 0.34),
      arrowHighlight,
    );
  }

  // Compression Socks — shield shape
  void _paintCompressionSocks(Canvas canvas, Size size) {
    _paintMedallion(
      canvas,
      size,
      fillColors: const [
        Color(0xFFDDF6FF),
        Color(0xFF6FB5E8),
        Color(0xFF2C558B),
      ],
      edgeColor: const Color(0xFF17365A),
      ringColor: const Color(0xFFCDEBFF),
      shadowColor: const Color(0xFF0E2440),
    );

    canvas.save();
    canvas.translate(size.width * 0.49, size.height * 0.53);
    canvas.rotate(-0.18);

    final sockPath = Path()
      ..moveTo(-size.width * 0.11, -size.height * 0.31)
      ..lineTo(size.width * 0.08, -size.height * 0.31)
      ..quadraticBezierTo(
        size.width * 0.11,
        -size.height * 0.31,
        size.width * 0.10,
        -size.height * 0.25,
      )
      ..lineTo(size.width * 0.07, size.height * 0.05)
      ..quadraticBezierTo(
        size.width * 0.06,
        size.height * 0.17,
        size.width * 0.15,
        size.height * 0.21,
      )
      ..lineTo(size.width * 0.23, size.height * 0.21)
      ..quadraticBezierTo(
        size.width * 0.30,
        size.height * 0.21,
        size.width * 0.30,
        size.height * 0.30,
      )
      ..quadraticBezierTo(
        size.width * 0.30,
        size.height * 0.38,
        size.width * 0.20,
        size.height * 0.38,
      )
      ..lineTo(-size.width * 0.01, size.height * 0.38)
      ..quadraticBezierTo(
        -size.width * 0.09,
        size.height * 0.38,
        -size.width * 0.09,
        size.height * 0.30,
      )
      ..lineTo(-size.width * 0.09, size.height * 0.24)
      ..quadraticBezierTo(
        -size.width * 0.09,
        size.height * 0.18,
        -size.width * 0.03,
        size.height * 0.15,
      )
      ..lineTo(-size.width * 0.01, -size.height * 0.25)
      ..quadraticBezierTo(
        -size.width * 0.01,
        -size.height * 0.31,
        -size.width * 0.11,
        -size.height * 0.31,
      )
      ..close();

    canvas.drawShadow(
      sockPath,
      const Color(0xFF18314D).withValues(alpha: 0.35),
      size.width * 0.03,
      false,
    );
    canvas.drawPath(sockPath, Paint()..color = const Color(0xFFF7FBFF));
    canvas.drawPath(
      sockPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.028
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFFD2E6F5),
    );

    final cuffRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        -size.width * 0.11,
        -size.height * 0.31,
        size.width * 0.19,
        size.height * 0.08,
      ),
      Radius.circular(size.width * 0.03),
    );
    canvas.drawRRect(cuffRect, Paint()..color = const Color(0xFF4F8FD0));

    final heelPatch = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        -size.width * 0.01,
        size.height * 0.12,
        size.width * 0.11,
        size.height * 0.10,
      ),
      Radius.circular(size.width * 0.03),
    );
    canvas.drawRRect(heelPatch, Paint()..color = const Color(0xFF88BCEB));

    final toePatch = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.10,
        size.height * 0.22,
        size.width * 0.17,
        size.height * 0.14,
      ),
      Radius.circular(size.width * 0.05),
    );
    canvas.drawRRect(toePatch, Paint()..color = const Color(0xFF6EA8DE));

    final bandPaint = Paint()
      ..color = const Color(0xFF2E6FB5)
      ..strokeWidth = size.width * 0.04
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(-size.width * 0.08, -size.height * 0.16),
      Offset(size.width * 0.06, -size.height * 0.11),
      bandPaint,
    );
    canvas.drawLine(
      Offset(-size.width * 0.08, -size.height * 0.07),
      Offset(size.width * 0.06, -size.height * 0.02),
      bandPaint,
    );
    canvas.drawLine(
      Offset(-size.width * 0.07, size.height * 0.02),
      Offset(size.width * 0.05, size.height * 0.06),
      bandPaint,
    );

    canvas.drawLine(
      Offset(-size.width * 0.03, -size.height * 0.18),
      Offset(size.width * 0.00, size.height * 0.22),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..strokeWidth = size.width * 0.025
        ..strokeCap = StrokeCap.round,
    );

    canvas.restore();
  }

  // Protein Shake — bottle/cup with plus sign
  void _paintProteinShake(Canvas canvas, Size size) {
    _paintMedallion(
      canvas,
      size,
      fillColors: const [
        Color(0xFFE3FFD9),
        Color(0xFF77D856),
        Color(0xFF247236),
      ],
      edgeColor: const Color(0xFF17451E),
      ringColor: const Color(0xFFD7F8C8),
      shadowColor: const Color(0xFF102913),
    );

    final bottlePath = Path()
      ..moveTo(size.width * 0.39, size.height * 0.22)
      ..lineTo(size.width * 0.61, size.height * 0.22)
      ..quadraticBezierTo(
        size.width * 0.64,
        size.height * 0.22,
        size.width * 0.65,
        size.height * 0.26,
      )
      ..lineTo(size.width * 0.68, size.height * 0.38)
      ..lineTo(size.width * 0.74, size.height * 0.73)
      ..quadraticBezierTo(
        size.width * 0.75,
        size.height * 0.82,
        size.width * 0.66,
        size.height * 0.84,
      )
      ..lineTo(size.width * 0.34, size.height * 0.84)
      ..quadraticBezierTo(
        size.width * 0.25,
        size.height * 0.82,
        size.width * 0.26,
        size.height * 0.73,
      )
      ..lineTo(size.width * 0.32, size.height * 0.38)
      ..lineTo(size.width * 0.35, size.height * 0.26)
      ..quadraticBezierTo(
        size.width * 0.36,
        size.height * 0.22,
        size.width * 0.39,
        size.height * 0.22,
      )
      ..close();

    canvas.drawShadow(
      bottlePath,
      const Color(0xFF17311A).withValues(alpha: 0.35),
      size.width * 0.035,
      false,
    );
    canvas.drawPath(bottlePath, Paint()..color = const Color(0xFFF9FFF7));
    canvas.drawPath(
      bottlePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.03
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFFD0E8C9),
    );

    final lidRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.36,
        size.height * 0.16,
        size.width * 0.28,
        size.height * 0.10,
      ),
      Radius.circular(size.width * 0.035),
    );
    canvas.drawRRect(lidRect, Paint()..color = const Color(0xFF1E5A26));
    canvas.drawRRect(
      lidRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.02
        ..color = const Color(0xFF0C3313),
    );

    canvas.drawLine(
      Offset(size.width * 0.48, size.height * 0.14),
      Offset(size.width * 0.58, size.height * 0.06),
      Paint()
        ..color = const Color(0xFFF8FFF6)
        ..strokeWidth = size.width * 0.035
        ..strokeCap = StrokeCap.round,
    );

    final labelRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.31,
        size.height * 0.47,
        size.width * 0.38,
        size.height * 0.19,
      ),
      Radius.circular(size.width * 0.04),
    );
    canvas.drawRRect(labelRect, Paint()..color = const Color(0xFF53C340));
    canvas.drawRRect(
      labelRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.02
        ..color = const Color(0xFF1D6A28),
    );

    final plusPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = size.width * 0.055
      ..strokeCap = StrokeCap.round;
    final cx = size.width / 2;
    final cy = size.height * 0.565;
    final pr = size.width * 0.08;
    canvas.drawLine(Offset(cx - pr, cy), Offset(cx + pr, cy), plusPaint);
    canvas.drawLine(Offset(cx, cy - pr), Offset(cx, cy + pr), plusPaint);

    canvas.drawLine(
      Offset(size.width * 0.42, size.height * 0.30),
      Offset(size.width * 0.50, size.height * 0.70),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.72)
        ..strokeWidth = size.width * 0.03
        ..strokeCap = StrokeCap.round,
    );
  }

  // Runner's High — double up arrows (speed boost)
  void _paintRunnersHigh(Canvas canvas, Size size) {
    _paintMedallion(
      canvas,
      size,
      fillColors: const [
        Color(0xFFFFF0B8),
        Color(0xFFFFB33F),
        Color(0xFFB85A0B),
      ],
      edgeColor: const Color(0xFF713408),
      ringColor: const Color(0xFFFFE6A6),
      shadowColor: const Color(0xFF3D1D05),
    );

    final haloCenter = Offset(size.width / 2, size.height * 0.46);
    canvas.drawCircle(
      haloCenter,
      size.width * 0.30,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                const Color(0xFFFFF7D4).withValues(alpha: 0.65),
                const Color(0xFFFFD56E).withValues(alpha: 0.0),
              ],
            ).createShader(
              Rect.fromCircle(center: haloCenter, radius: size.width * 0.30),
            ),
    );

    final echoPaint = Paint()
      ..color = const Color(0xFFFFF2C6).withValues(alpha: 0.85)
      ..strokeWidth = size.width * 0.045
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final leftEcho = Path()
      ..moveTo(size.width * 0.28, size.height * 0.66)
      ..quadraticBezierTo(
        size.width * 0.27,
        size.height * 0.47,
        size.width * 0.37,
        size.height * 0.28,
      );
    final rightEcho = Path()
      ..moveTo(size.width * 0.72, size.height * 0.66)
      ..quadraticBezierTo(
        size.width * 0.73,
        size.height * 0.47,
        size.width * 0.63,
        size.height * 0.28,
      );
    canvas.drawPath(leftEcho, echoPaint);
    canvas.drawPath(rightEcho, echoPaint);

    final surgePath = Path()
      ..moveTo(size.width * 0.50, size.height * 0.16)
      ..lineTo(size.width * 0.66, size.height * 0.37)
      ..lineTo(size.width * 0.58, size.height * 0.37)
      ..lineTo(size.width * 0.61, size.height * 0.75)
      ..lineTo(size.width * 0.39, size.height * 0.75)
      ..lineTo(size.width * 0.42, size.height * 0.37)
      ..lineTo(size.width * 0.34, size.height * 0.37)
      ..close();

    canvas.drawShadow(
      surgePath,
      const Color(0xFF5A2706).withValues(alpha: 0.38),
      size.width * 0.035,
      false,
    );
    canvas.drawPath(
      surgePath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF9E2), Color(0xFFFFD24C), Color(0xFFF08C13)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    canvas.drawPath(
      surgePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.03
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFFA44B09),
    );

    canvas.drawLine(
      Offset(size.width * 0.50, size.height * 0.25),
      Offset(size.width * 0.50, size.height * 0.62),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..strokeWidth = size.width * 0.028
        ..strokeCap = StrokeCap.round,
    );
  }

  // Second Wind — spiral / swirl
  void _paintSecondWind(Canvas canvas, Size size) {
    _paintMedallion(
      canvas,
      size,
      fillColors: const [
        Color(0xFFE1FAFF),
        Color(0xFF7CCFE4),
        Color(0xFF2D6E96),
      ],
      edgeColor: const Color(0xFF184965),
      ringColor: const Color(0xFFCFF5FF),
      shadowColor: const Color(0xFF102E45),
    );

    final haloCenter = Offset(size.width * 0.48, size.height * 0.48);
    canvas.drawCircle(
      haloCenter,
      size.width * 0.28,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                const Color(0xFFF6FFFF).withValues(alpha: 0.58),
                const Color(0xFFB5F4FF).withValues(alpha: 0.0),
              ],
            ).createShader(
              Rect.fromCircle(center: haloCenter, radius: size.width * 0.28),
            ),
    );

    final gustShadow = Paint()
      ..color = const Color(0xFF184965).withValues(alpha: 0.18)
      ..strokeWidth = size.width * 0.12
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final gustPaint = Paint()
      ..color = const Color(0xFFF4FFFF)
      ..strokeWidth = size.width * 0.105
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final gustEdge = Paint()
      ..color = const Color(0xFF9DDEEF)
      ..strokeWidth = size.width * 0.028
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final swirlPath = Path()
      ..moveTo(size.width * 0.25, size.height * 0.63)
      ..quadraticBezierTo(
        size.width * 0.20,
        size.height * 0.36,
        size.width * 0.46,
        size.height * 0.34,
      )
      ..quadraticBezierTo(
        size.width * 0.68,
        size.height * 0.33,
        size.width * 0.66,
        size.height * 0.53,
      )
      ..quadraticBezierTo(
        size.width * 0.64,
        size.height * 0.68,
        size.width * 0.48,
        size.height * 0.65,
      );

    canvas.drawPath(
      swirlPath.shift(Offset(size.width * 0.015, size.height * 0.02)),
      gustShadow,
    );
    canvas.drawPath(swirlPath, gustPaint);
    canvas.drawPath(swirlPath, gustEdge);

    final innerRibbon = Path()
      ..moveTo(size.width * 0.39, size.height * 0.60)
      ..quadraticBezierTo(
        size.width * 0.33,
        size.height * 0.47,
        size.width * 0.43,
        size.height * 0.41,
      )
      ..quadraticBezierTo(
        size.width * 0.52,
        size.height * 0.36,
        size.width * 0.55,
        size.height * 0.27,
      )
      ..quadraticBezierTo(
        size.width * 0.60,
        size.height * 0.36,
        size.width * 0.59,
        size.height * 0.45,
      )
      ..quadraticBezierTo(
        size.width * 0.58,
        size.height * 0.58,
        size.width * 0.49,
        size.height * 0.60,
      )
      ..close();

    canvas.drawShadow(
      innerRibbon,
      const Color(0xFF184965).withValues(alpha: 0.25),
      size.width * 0.02,
      false,
    );
    canvas.drawPath(
      innerRibbon,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFBDF5FF), Color(0xFF66CDE6)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    canvas.drawPath(
      innerRibbon,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.025
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFF67B9D8),
    );

    final tailPaint = Paint()
      ..color = const Color(0xFFE6FFFF).withValues(alpha: 0.85)
      ..strokeWidth = size.width * 0.04
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final upperTail = Path()
      ..moveTo(size.width * 0.34, size.height * 0.24)
      ..quadraticBezierTo(
        size.width * 0.46,
        size.height * 0.15,
        size.width * 0.61,
        size.height * 0.18,
      );
    final lowerTail = Path()
      ..moveTo(size.width * 0.30, size.height * 0.74)
      ..quadraticBezierTo(
        size.width * 0.43,
        size.height * 0.83,
        size.width * 0.59,
        size.height * 0.76,
      );
    canvas.drawPath(upperTail, tailPaint);
    canvas.drawPath(lowerTail, tailPaint);
  }

  // Stealth Mode — eye with slash through it
  void _paintStealthMode(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF6B5030)
      ..strokeWidth = size.width * 0.08
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final cx = size.width / 2;
    final cy = size.height / 2;

    // Eye shape
    final eyePath = Path()
      ..moveTo(size.width * 0.1, cy)
      ..quadraticBezierTo(cx, cy - size.height * 0.3, size.width * 0.9, cy)
      ..quadraticBezierTo(cx, cy + size.height * 0.3, size.width * 0.1, cy);
    canvas.drawPath(eyePath, paint);

    // Pupil
    canvas.drawCircle(
      Offset(cx, cy),
      size.width * 0.08,
      paint..style = PaintingStyle.fill,
    );
    paint.style = PaintingStyle.stroke;

    // Slash
    final slashPaint = Paint()
      ..color = const Color(0xFFE05040)
      ..strokeWidth = size.width * 0.08
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.2, size.height * 0.2),
      Offset(size.width * 0.8, size.height * 0.8),
      slashPaint,
    );
  }

  // Wrong Turn — painted via Icon in the widget layer (see PowerupIcon build)
  void _paintWrongTurn(Canvas canvas, Size size) {
    // No-op: handled by Icon widget overlay in PowerupIcon.build
  }

  // Fanny Pack — small pouch/bag shape
  void _paintFannyPack(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFD4A017);

    // Pouch body
    final body = Path()
      ..moveTo(size.width * 0.15, size.height * 0.45)
      ..quadraticBezierTo(
        size.width * 0.15,
        size.height * 0.85,
        size.width * 0.5,
        size.height * 0.85,
      )
      ..quadraticBezierTo(
        size.width * 0.85,
        size.height * 0.85,
        size.width * 0.85,
        size.height * 0.45,
      )
      ..lineTo(size.width * 0.15, size.height * 0.45)
      ..close();
    canvas.drawPath(body, paint);

    // Flap/lid
    final flap = Paint()..color = const Color(0xFFB8860B);
    final flapPath = Path()
      ..moveTo(size.width * 0.1, size.height * 0.45)
      ..lineTo(size.width * 0.9, size.height * 0.45)
      ..lineTo(size.width * 0.85, size.height * 0.35)
      ..quadraticBezierTo(
        size.width * 0.5,
        size.height * 0.25,
        size.width * 0.15,
        size.height * 0.35,
      )
      ..close();
    canvas.drawPath(flapPath, flap);

    // Strap
    final strap = Paint()
      ..color = const Color(0xFF8B6914)
      ..strokeWidth = size.width * 0.06
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final strapPath = Path()
      ..moveTo(size.width * 0.15, size.height * 0.4)
      ..quadraticBezierTo(
        size.width * 0.5,
        size.height * 0.12,
        size.width * 0.85,
        size.height * 0.4,
      );
    canvas.drawPath(strapPath, strap);

    // Clasp/button
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.45),
      size.width * 0.06,
      Paint()..color = const Color(0xFFE8C850),
    );
  }

  // Trail Mix — small bag with mixed dots (nuts, raisins, etc.)
  void _paintTrailMix(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF8B6914);

    // Bag body
    final bag = Path()
      ..moveTo(size.width * 0.2, size.height * 0.35)
      ..lineTo(size.width * 0.25, size.height * 0.85)
      ..quadraticBezierTo(
        size.width * 0.5,
        size.height * 0.9,
        size.width * 0.75,
        size.height * 0.85,
      )
      ..lineTo(size.width * 0.8, size.height * 0.35)
      ..close();
    canvas.drawPath(bag, paint);

    // Bag opening (crinkled top)
    final top = Paint()..color = const Color(0xFFA0782C);
    final topPath = Path()
      ..moveTo(size.width * 0.15, size.height * 0.35)
      ..lineTo(size.width * 0.3, size.height * 0.25)
      ..lineTo(size.width * 0.5, size.height * 0.32)
      ..lineTo(size.width * 0.7, size.height * 0.25)
      ..lineTo(size.width * 0.85, size.height * 0.35)
      ..lineTo(size.width * 0.8, size.height * 0.35)
      ..lineTo(size.width * 0.2, size.height * 0.35)
      ..close();
    canvas.drawPath(topPath, top);

    // Mix dots — nuts (tan)
    canvas.drawCircle(
      Offset(size.width * 0.38, size.height * 0.52),
      size.width * 0.06,
      Paint()..color = const Color(0xFFDEB887),
    );
    canvas.drawCircle(
      Offset(size.width * 0.62, size.height * 0.65),
      size.width * 0.055,
      Paint()..color = const Color(0xFFDEB887),
    );

    // Mix dots — raisins (dark purple)
    canvas.drawCircle(
      Offset(size.width * 0.52, size.height * 0.55),
      size.width * 0.05,
      Paint()..color = const Color(0xFF4A0E4E),
    );
    canvas.drawCircle(
      Offset(size.width * 0.4, size.height * 0.7),
      size.width * 0.045,
      Paint()..color = const Color(0xFF4A0E4E),
    );

    // Mix dots — chocolate (brown)
    canvas.drawCircle(
      Offset(size.width * 0.58, size.height * 0.48),
      size.width * 0.04,
      Paint()..color = const Color(0xFF5C3317),
    );
    canvas.drawCircle(
      Offset(size.width * 0.48, size.height * 0.72),
      size.width * 0.05,
      Paint()..color = const Color(0xFF5C3317),
    );
  }

  // Detour Sign — diamond warning sign with question mark
  void _paintDetourSign(Canvas canvas, Size size) {
    // Diamond shape
    final diamond = Path()
      ..moveTo(size.width * 0.5, size.height * 0.12)
      ..lineTo(size.width * 0.88, size.height * 0.5)
      ..lineTo(size.width * 0.5, size.height * 0.88)
      ..lineTo(size.width * 0.12, size.height * 0.5)
      ..close();
    canvas.drawPath(diamond, Paint()..color = const Color(0xFFFF8C00));

    // Border
    canvas.drawPath(
      diamond,
      Paint()
        ..color = const Color(0xFF8B4500)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.05,
    );

    // Question mark
    final textPainter = TextPainter(
      text: TextSpan(
        text: '?',
        style: TextStyle(
          color: Colors.black,
          fontSize: size.width * 0.45,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        (size.height - textPainter.height) / 2,
      ),
    );
  }
}
