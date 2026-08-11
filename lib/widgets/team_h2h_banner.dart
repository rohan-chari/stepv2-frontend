import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../styles.dart';
import '../utils/team_race.dart';

/// The tug-of-war rope: a sagging line with a wrapped knot that slides to
/// [share] (0 = Team A end, 1 = Team B end). Used by the compact race-card
/// scoreline ([TeamScoreline]); the detail scoreboard no longer draws it.
class TeamTugRope extends StatelessWidget {
  const TeamTugRope({super.key, required this.share});

  final double share;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.5, end: share),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutBack,
      builder: (context, animatedShare, _) {
        return SizedBox(
          height: 36,
          width: double.infinity,
          child: CustomPaint(
            painter: _TugRopePainter(
              share: animatedShare,
              teamAColor: TeamRace.color(RaceTeam.teamA, context),
              teamBColor: TeamRace.color(RaceTeam.teamB, context),
              markerColor: AppColors.of(context).textMid,
              ropeDark: AppColors.of(context).dirtDark,
              ropeMid: AppColors.of(context).dirtMid,
            ),
          ),
        );
      },
    );
  }
}

class _TugRopePainter extends CustomPainter {
  _TugRopePainter({
    required this.share,
    required this.teamAColor,
    required this.teamBColor,
    required this.markerColor,
    required this.ropeDark,
    required this.ropeMid,
  });

  final double share;
  final Color teamAColor;
  final Color teamBColor;
  final Color markerColor;
  final Color ropeDark;
  final Color ropeMid;

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final knotX = size.width * share;

    final ropeA = Paint()
      ..color = teamAColor
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final ropeB = Paint()
      ..color = teamBColor
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final pathA = Path()
      ..moveTo(0, midY - 3)
      ..quadraticBezierTo(knotX * 0.5, midY + 5, knotX, midY);
    final pathB = Path()
      ..moveTo(size.width, midY - 3)
      ..quadraticBezierTo(
        knotX + (size.width - knotX) * 0.5,
        midY + 5,
        knotX,
        midY,
      );
    canvas.drawPath(pathA, ropeA);
    canvas.drawPath(pathB, ropeB);

    final stake = Paint()
      ..color = markerColor.withValues(alpha: 0.5)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(size.width / 2, midY - 9),
      Offset(size.width / 2, midY + 9),
      stake,
    );

    final knotCenter = Offset(knotX, midY);
    canvas.drawCircle(knotCenter, 8, Paint()..color = ropeDark);
    canvas.drawCircle(knotCenter, 6.2, Paint()..color = ropeMid);
    final wrap = Paint()
      ..color = ropeDark
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    for (final angle in [-0.5, 0.0, 0.5]) {
      canvas.drawArc(
        Rect.fromCircle(center: knotCenter, radius: 5),
        angle + math.pi / 2 - 0.7,
        1.4,
        false,
        wrap,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TugRopePainter oldDelegate) =>
      oldDelegate.share != share ||
      oldDelegate.markerColor != markerColor ||
      oldDelegate.ropeDark != ropeDark ||
      oldDelegate.ropeMid != ropeMid;
}
