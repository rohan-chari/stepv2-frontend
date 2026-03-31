import 'package:flutter/material.dart';

/// Pixel-art style icons for powerups, drawn with CustomPainter.
/// No emoji — just clean vector shapes in the app's trail palette.
class PowerupIcon extends StatelessWidget {
  final String type;
  final double size;

  const PowerupIcon({super.key, required this.type, this.size = 22});

  @override
  Widget build(BuildContext context) {
    if (type.toUpperCase() == 'WRONG_TURN') {
      return Icon(Icons.undo, size: size, color: const Color(0xFFE05040));
    }
    return CustomPaint(
      size: Size(size, size),
      painter: _PowerupPainter(type),
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
    }
  }

  @override
  bool shouldRepaint(covariant _PowerupPainter old) => old.type != type;

  // Leg Cramp — snowflake / freeze symbol
  void _paintLegCramp(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF5BC0EB)
      ..strokeWidth = size.width * 0.1
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.35;

    // Cross lines
    canvas.drawLine(Offset(cx, cy - r), Offset(cx, cy + r), paint);
    canvas.drawLine(Offset(cx - r, cy), Offset(cx + r, cy), paint);
    canvas.drawLine(Offset(cx - r * 0.7, cy - r * 0.7), Offset(cx + r * 0.7, cy + r * 0.7), paint);
    canvas.drawLine(Offset(cx + r * 0.7, cy - r * 0.7), Offset(cx - r * 0.7, cy + r * 0.7), paint);

    // Center dot
    canvas.drawCircle(Offset(cx, cy), size.width * 0.06, paint..style = PaintingStyle.fill);
  }

  // Red Card — rectangular card shape
  void _paintRedCard(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFE05040);
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(size.width / 2, size.height / 2), width: size.width * 0.5, height: size.height * 0.65),
      Radius.circular(size.width * 0.05),
    );
    canvas.drawRRect(rect, paint);

    // Exclamation mark
    final textPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = size.width * 0.08
      ..strokeCap = StrokeCap.round;
    final cx = size.width / 2;
    final cy = size.height / 2;
    canvas.drawLine(Offset(cx, cy - size.height * 0.15), Offset(cx, cy + size.height * 0.05), textPaint);
    canvas.drawCircle(Offset(cx, cy + size.height * 0.15), size.width * 0.04, textPaint);
  }

  // Shortcut — diagonal arrow cutting across
  void _paintShortcut(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFD4691E)
      ..strokeWidth = size.width * 0.1
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final p1 = Offset(size.width * 0.2, size.height * 0.8);
    final p2 = Offset(size.width * 0.8, size.height * 0.2);
    canvas.drawLine(p1, p2, paint);

    // Arrowhead
    canvas.drawLine(p2, Offset(size.width * 0.55, size.height * 0.2), paint);
    canvas.drawLine(p2, Offset(size.width * 0.8, size.height * 0.45), paint);

    // Dashed path it cuts through
    final pathPaint = Paint()
      ..color = const Color(0xFF8B8B8B)
      ..strokeWidth = size.width * 0.04
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(size.width * 0.15, size.height * 0.3), Offset(size.width * 0.35, size.height * 0.3), pathPaint);
    canvas.drawLine(Offset(size.width * 0.65, size.height * 0.7), Offset(size.width * 0.85, size.height * 0.7), pathPaint);
  }

  // Compression Socks — shield shape
  void _paintCompressionSocks(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF4A90D9);
    final path = Path()
      ..moveTo(size.width * 0.5, size.height * 0.1)
      ..lineTo(size.width * 0.85, size.height * 0.25)
      ..lineTo(size.width * 0.85, size.height * 0.55)
      ..quadraticBezierTo(size.width * 0.85, size.height * 0.85, size.width * 0.5, size.height * 0.95)
      ..quadraticBezierTo(size.width * 0.15, size.height * 0.85, size.width * 0.15, size.height * 0.55)
      ..lineTo(size.width * 0.15, size.height * 0.25)
      ..close();
    canvas.drawPath(path, paint);

    // Inner highlight
    final highlight = Paint()
      ..color = const Color(0xFF6FB5E8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.06;
    final innerPath = Path()
      ..moveTo(size.width * 0.5, size.height * 0.2)
      ..lineTo(size.width * 0.75, size.height * 0.32)
      ..lineTo(size.width * 0.75, size.height * 0.55)
      ..quadraticBezierTo(size.width * 0.75, size.height * 0.78, size.width * 0.5, size.height * 0.85)
      ..quadraticBezierTo(size.width * 0.25, size.height * 0.78, size.width * 0.25, size.height * 0.55)
      ..lineTo(size.width * 0.25, size.height * 0.32)
      ..close();
    canvas.drawPath(innerPath, highlight);
  }

  // Protein Shake — bottle/cup with plus sign
  void _paintProteinShake(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF58CC02);

    // Cup body
    final cup = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.25, size.height * 0.3, size.width * 0.5, size.height * 0.55),
      Radius.circular(size.width * 0.08),
    );
    canvas.drawRRect(cup, paint);

    // Cup lid
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.2, size.height * 0.22, size.width * 0.6, size.height * 0.1),
      paint,
    );

    // Plus sign
    final plusPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = size.width * 0.08
      ..strokeCap = StrokeCap.round;
    final cx = size.width / 2;
    final cy = size.height * 0.58;
    final pr = size.width * 0.12;
    canvas.drawLine(Offset(cx - pr, cy), Offset(cx + pr, cy), plusPaint);
    canvas.drawLine(Offset(cx, cy - pr), Offset(cx, cy + pr), plusPaint);
  }

  // Runner's High — double up arrows (speed boost)
  void _paintRunnersHigh(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFB830)
      ..strokeWidth = size.width * 0.1
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // First arrow
    final ax = size.width * 0.35;
    canvas.drawLine(Offset(ax - size.width * 0.15, size.height * 0.5), Offset(ax, size.height * 0.2), paint);
    canvas.drawLine(Offset(ax + size.width * 0.15, size.height * 0.5), Offset(ax, size.height * 0.2), paint);
    canvas.drawLine(Offset(ax, size.height * 0.2), Offset(ax, size.height * 0.85), paint);

    // Second arrow
    final bx = size.width * 0.65;
    canvas.drawLine(Offset(bx - size.width * 0.15, size.height * 0.5), Offset(bx, size.height * 0.2), paint);
    canvas.drawLine(Offset(bx + size.width * 0.15, size.height * 0.5), Offset(bx, size.height * 0.2), paint);
    canvas.drawLine(Offset(bx, size.height * 0.2), Offset(bx, size.height * 0.85), paint);
  }

  // Second Wind — spiral / swirl
  void _paintSecondWind(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF82B8DE)
      ..strokeWidth = size.width * 0.08
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final cx = size.width / 2;
    final cy = size.height / 2;

    // Three curved lines suggesting wind
    for (var i = 0; i < 3; i++) {
      final y = cy - size.height * 0.2 + i * size.height * 0.2;
      final startX = size.width * 0.15;
      final endX = size.width * 0.85;
      final path = Path()
        ..moveTo(startX, y)
        ..quadraticBezierTo(cx, y - size.height * 0.12, endX, y);
      canvas.drawPath(path, paint);
    }
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
    canvas.drawCircle(Offset(cx, cy), size.width * 0.08, paint..style = PaintingStyle.fill);
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
      ..quadraticBezierTo(size.width * 0.15, size.height * 0.85, size.width * 0.5, size.height * 0.85)
      ..quadraticBezierTo(size.width * 0.85, size.height * 0.85, size.width * 0.85, size.height * 0.45)
      ..lineTo(size.width * 0.15, size.height * 0.45)
      ..close();
    canvas.drawPath(body, paint);

    // Flap/lid
    final flap = Paint()..color = const Color(0xFFB8860B);
    final flapPath = Path()
      ..moveTo(size.width * 0.1, size.height * 0.45)
      ..lineTo(size.width * 0.9, size.height * 0.45)
      ..lineTo(size.width * 0.85, size.height * 0.35)
      ..quadraticBezierTo(size.width * 0.5, size.height * 0.25, size.width * 0.15, size.height * 0.35)
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
      ..quadraticBezierTo(size.width * 0.5, size.height * 0.12, size.width * 0.85, size.height * 0.4);
    canvas.drawPath(strapPath, strap);

    // Clasp/button
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.45),
      size.width * 0.06,
      Paint()..color = const Color(0xFFE8C850),
    );
  }
}
