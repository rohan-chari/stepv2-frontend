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
    this.height = 200,
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

  static const double _trackWidth = 28.0;
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
    final (trackPath, trackRect) = _buildOvalPath(size);

    _drawTrackOutline(canvas, trackPath);
    _drawTrackSurface(canvas, trackPath);
    _drawCenterLine(canvas, trackPath);
    _drawAvatars(canvas, trackPath, trackRect);
  }

  (Path, Rect) _buildOvalPath(Size size) {
    final w = size.width;
    final h = size.height;
    final padding = _avatarRadius + _avatarBorder + 12;
    final trackRect =
        Rect.fromLTRB(padding, padding + 4, w - padding, h - padding - 4);
    final ry = trackRect.height / 2;

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(trackRect, Radius.circular(ry)));
    return (path, trackRect);
  }

  void _drawTrackOutline(Canvas canvas, Path path) {
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.dirtMid.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _trackWidth + 6,
    );
  }

  void _drawTrackSurface(Canvas canvas, Path path) {
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.dirtLight.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _trackWidth,
    );
  }

  void _drawCenterLine(Canvas canvas, Path path) {
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.parchmentDark.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _drawAvatars(Canvas canvas, Path trackPath, Rect trackRect) {
    final metrics = trackPath.computeMetrics().first;
    final totalLength = metrics.length;

    // Find the fraction along the path closest to the bottom center of the rect.
    // This avoids guessing where addRRect starts its path.
    final bottomCenter = Offset(trackRect.center.dx, trackRect.bottom);
    double startFrac = 0.5;
    double bestDist = double.infinity;
    for (int i = 0; i < 200; i++) {
      final frac = i / 200.0;
      final tangent = metrics.getTangentForOffset(frac * totalLength);
      if (tangent != null) {
        final dist = (tangent.position - bottomCenter).distanceSquared;
        if (dist < bestDist) {
          bestDist = dist;
          startFrac = frac;
        }
      }
    }

    // Counter-clockwise: subtract position from the start fraction
    final myFrac = (startFrac - myPosition) % 1.0;
    final theirFrac = (startFrac - theirPosition) % 1.0;

    final myTangent = metrics.getTangentForOffset(myFrac * totalLength);
    final theirTangent = metrics.getTangentForOffset(theirFrac * totalLength);

    if (myTangent == null || theirTangent == null) return;

    // Draw trailing avatar first so leader renders on top
    if (myPosition >= theirPosition) {
      _drawAvatar(
          canvas, theirTangent.position, theirInitials, AppColors.pillGold);
      _drawAvatar(
          canvas, myTangent.position, myInitials, AppColors.pillGreen);
    } else {
      _drawAvatar(
          canvas, myTangent.position, myInitials, AppColors.pillGreen);
      _drawAvatar(
          canvas, theirTangent.position, theirInitials, AppColors.pillGold);
    }
  }

  void _drawAvatar(
      Canvas canvas, Offset center, String initials, Color color) {
    canvas.drawCircle(
        center, _avatarRadius + _avatarBorder, Paint()..color = Colors.white);
    canvas.drawCircle(center, _avatarRadius, Paint()..color = color);

    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.center,
      fontSize: 14,
      fontWeight: FontWeight.bold,
    ))
      ..pushStyle(ui.TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
      ))
      ..addText(initials);

    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: _avatarRadius * 2));

    canvas.drawParagraph(
      paragraph,
      Offset(center.dx - _avatarRadius, center.dy - paragraph.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _RaceTrackPainter oldDelegate) {
    return oldDelegate.myPosition != myPosition ||
        oldDelegate.theirPosition != theirPosition ||
        oldDelegate.myInitials != myInitials ||
        oldDelegate.theirInitials != theirInitials;
  }
}
