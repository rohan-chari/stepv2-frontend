import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../styles.dart';
import '../utils/race_positions.dart';

class RaceTrack extends StatefulWidget {
  final int mySteps;
  final int theirSteps;
  final String myName;
  final String theirName;
  final double height;

  const RaceTrack({
    super.key,
    required this.mySteps,
    required this.theirSteps,
    required this.myName,
    required this.theirName,
    this.height = 240,
  });

  @override
  State<RaceTrack> createState() => _RaceTrackState();

  static String _initials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '??';
    return trimmed.substring(0, trimmed.length.clamp(0, 2)).toUpperCase();
  }
}

class _RaceTrackState extends State<RaceTrack>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (myTarget, theirTarget, _) = computeRacePositions(
      mySteps: widget.mySteps,
      theirSteps: widget.theirSteps,
    );

    return SizedBox(
      width: double.infinity,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          final t = _animation.value;
          return CustomPaint(
            painter: _RaceTrackPainter(
              myPosition: myTarget * t,
              theirPosition: theirTarget * t,
              myInitials: RaceTrack._initials(widget.myName),
              theirInitials: RaceTrack._initials(widget.theirName),
            ),
          );
        },
      ),
    );
  }
}

class _RaceTrackPainter extends CustomPainter {
  final double myPosition;
  final double theirPosition;
  final String myInitials;
  final String theirInitials;

  static const double _trackWidth = 32.0;
  static const double _avatarRadius = 18.0;
  static const double _avatarBorder = 2.5;

  _RaceTrackPainter({
    required this.myPosition,
    required this.theirPosition,
    required this.myInitials,
    required this.theirInitials,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final trackPath = _buildWindingPath(size);

    _drawGrass(canvas, size);
    _drawTrees(canvas, size);
    _drawCurbs(canvas, trackPath);
    _drawTrackSurface(canvas, trackPath);
    _drawDashedCenterLine(canvas, trackPath);
    _drawFinishLine(canvas, trackPath);
    _drawAvatars(canvas, trackPath);
  }

  Path _buildWindingPath(Size size) {
    final w = size.width;
    final h = size.height;
    final m = _trackWidth + 20;

    final path = Path();
    path.moveTo(w / 2, h - m);
    path.cubicTo(w - m, h - m, w - m, h * 0.6, w - m, h * 0.55);
    path.cubicTo(w - m, h * 0.4, m, h * 0.45, m, h * 0.35);
    path.cubicTo(m, h * 0.2, w - m, h * 0.15, w * 0.6, m);

    return path;
  }

  void _drawGrass(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(12),
      ),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF8BC34A), Color(0xFF7CB342), Color(0xFF689F38)],
        ).createShader(Offset.zero & size),
    );
  }

  void _drawTrees(Canvas canvas, Size size) {
    final rng = math.Random(42);
    final paint = Paint()..color = AppColors.grassDark.withValues(alpha: 0.5);
    for (int i = 0; i < 8; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final r = 10.0 + rng.nextDouble() * 14;
      canvas.drawCircle(Offset(x, y - r * 0.3), r * 0.6, paint);
      canvas.drawCircle(Offset(x - r * 0.4, y + r * 0.2), r * 0.5, paint);
      canvas.drawCircle(Offset(x + r * 0.4, y + r * 0.2), r * 0.5, paint);
    }
  }

  void _drawCurbs(Canvas canvas, Path trackPath) {
    final metrics = trackPath.computeMetrics().first;
    final totalLength = metrics.length;
    const stripeLen = 12.0;
    final redPaint = Paint()
      ..color = AppColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = _trackWidth + 10
      ..strokeCap = StrokeCap.round;
    final whitePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = _trackWidth + 10
      ..strokeCap = StrokeCap.round;

    for (double d = 0; d < totalLength; d += stripeLen * 2) {
      final end = (d + stripeLen).clamp(0.0, totalLength);
      canvas.drawPath(metrics.extractPath(d, end), redPaint);
      final start2 = end;
      final end2 = (end + stripeLen).clamp(0.0, totalLength);
      if (start2 < totalLength) {
        canvas.drawPath(metrics.extractPath(start2, end2), whitePaint);
      }
    }
  }

  void _drawTrackSurface(Canvas canvas, Path trackPath) {
    canvas.drawPath(
      trackPath,
      Paint()
        ..color = const Color(0xFF9E9E9E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _trackWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _drawDashedCenterLine(Canvas canvas, Path trackPath) {
    final metrics = trackPath.computeMetrics().first;
    final totalLength = metrics.length;
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    for (double d = 0; d < totalLength; d += 18) {
      final end = (d + 10).clamp(0.0, totalLength);
      canvas.drawPath(metrics.extractPath(d, end), paint);
    }
  }

  void _drawFinishLine(Canvas canvas, Path trackPath) {
    final metrics = trackPath.computeMetrics().first;
    final tangent = metrics.getTangentForOffset(metrics.length);
    if (tangent == null) return;

    canvas.save();
    canvas.translate(tangent.position.dx, tangent.position.dy);
    canvas.rotate(tangent.angle);

    const cs = 3.0;
    const rows = 3;
    final totalSpan = _trackWidth + 16;
    final cols = (totalSpan / cs).floor();
    final sx = -rows * cs / 2;
    final sy = -totalSpan / 2;

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        canvas.drawRect(
          Rect.fromLTWH(sx + r * cs, sy + c * cs, cs, cs),
          Paint()..color = (r + c) % 2 == 0 ? Colors.black : Colors.white,
        );
      }
    }
    canvas.restore();
  }

  void _drawAvatars(Canvas canvas, Path trackPath) {
    final metrics = trackPath.computeMetrics().first;
    final totalLength = metrics.length;

    final myFrac = myPosition.clamp(0.0, 0.999);
    final theirFrac = theirPosition.clamp(0.0, 0.999);

    final myTangent = metrics.getTangentForOffset(myFrac * totalLength);
    final theirTangent = metrics.getTangentForOffset(theirFrac * totalLength);

    if (myTangent == null || theirTangent == null) return;

    if (myPosition >= theirPosition) {
      _drawAvatar(canvas, theirTangent.position, theirInitials, AppColors.pillGold);
      _drawAvatar(canvas, myTangent.position, myInitials, AppColors.pillGreen);
    } else {
      _drawAvatar(canvas, myTangent.position, myInitials, AppColors.pillGreen);
      _drawAvatar(canvas, theirTangent.position, theirInitials, AppColors.pillGold);
    }
  }

  void _drawAvatar(Canvas canvas, Offset center, String initials, Color color) {
    canvas.drawCircle(center, _avatarRadius + _avatarBorder, Paint()..color = Colors.white);
    canvas.drawCircle(center, _avatarRadius, Paint()..color = color);

    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.center, fontSize: 14, fontWeight: FontWeight.bold,
    ))
      ..pushStyle(ui.TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
      ..addText(initials);

    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: _avatarRadius * 2));

    canvas.drawParagraph(paragraph,
      Offset(center.dx - _avatarRadius, center.dy - paragraph.height / 2));
  }

  @override
  bool shouldRepaint(covariant _RaceTrackPainter oldDelegate) {
    return oldDelegate.myPosition != myPosition ||
        oldDelegate.theirPosition != theirPosition;
  }
}
