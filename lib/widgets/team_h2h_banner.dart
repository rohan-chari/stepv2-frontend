import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../styles.dart';
import '../utils/team_race.dart';

/// TR-803 — the head-to-head tug-of-war banner for ACTIVE team races.
///
/// Team plaques anchor each end, combined totals sit beneath them, and a rope
/// with a knot marker slides toward whichever side is winning. Rendered as
/// board content (the race-detail screen wraps it in its section card — one
/// parchment board, never a floating card). Totals are ALWAYS honest: stealth
/// and imposter illusions touch individual planks only (TR-658).
class TeamH2HBanner extends StatelessWidget {
  const TeamH2HBanner({
    super.key,
    required this.teamAName,
    required this.teamBName,
    required this.teamATotal,
    required this.teamBTotal,
  });

  final String teamAName;
  final String teamBName;
  final int teamATotal;
  final int teamBTotal;

  /// 0.0 = knot fully at Team A's end, 1.0 = fully at Team B's end.
  /// The knot moves AWAY from the leader (they're reeling it in): Team A
  /// leading pulls the knot toward A, i.e. share < 0.5.
  double get _share {
    final total = teamATotal + teamBTotal;
    if (total <= 0) return 0.5;
    // Map A's fraction of steps [0..1] onto knot travel [1..0], softened so
    // the knot never sits flush against a plaque.
    final aFraction = teamATotal / total;
    return (1 - aFraction).clamp(0.12, 0.88);
  }

  String _formatSteps(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final lead = teamATotal - teamBTotal;

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _endPost(
                team: RaceTeam.teamA,
                name: teamAName,
                total: teamATotal,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _endPost(
                team: RaceTeam.teamB,
                name: teamBName,
                total: teamBTotal,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TeamTugRope(share: _share),
        const SizedBox(height: 8),
        _leadPill(lead),
      ],
    );
  }

  Widget _endPost({
    required RaceTeam team,
    required String name,
    required int total,
  }) {
    final color = TeamRace.color(team);
    final colorLight = TeamRace.colorLight(team);
    final colorDark = TeamRace.colorDark(team);

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [colorLight, color],
            ),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: colorDark, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: colorDark,
                offset: const Offset(0, 3),
                blurRadius: 0,
              ),
            ],
          ),
          child: Text(
            name.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: PixelText.title(size: 12, color: Colors.white).copyWith(
              shadows: const [
                Shadow(
                  color: Color(0x66000000),
                  offset: Offset(0, 1),
                  blurRadius: 0,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _formatSteps(total),
          style: PixelText.number(size: 20, color: colorDark),
        ),
        Text(
          'STEPS',
          style: PixelText.body(size: 9, color: AppColors.textMid),
        ),
      ],
    );
  }

  Widget _leadPill(int lead) {
    if (lead == 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.parchmentDark,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.parchmentBorder, width: 1.5),
        ),
        child: Text(
          'ALL TIED',
          style: PixelText.title(size: 10.5, color: AppColors.textMid),
        ),
      );
    }
    final leadingTeam = lead > 0 ? RaceTeam.teamA : RaceTeam.teamB;
    final name = (lead > 0 ? teamAName : teamBName).toUpperCase();
    final color = TeamRace.color(leadingTeam);
    final colorDark = TeamRace.colorDark(leadingTeam);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorDark, width: 1.5),
        boxShadow: [
          BoxShadow(color: colorDark, offset: const Offset(0, 2), blurRadius: 0),
        ],
      ),
      child: Text(
        '$name LEAD +${_formatSteps(lead.abs())}',
        style: PixelText.title(size: 10.5, color: Colors.white),
      ),
    );
  }
}

/// The tug-of-war rope: a sagging line with a wrapped knot that slides to
/// [share] (0 = Team A end, 1 = Team B end). Knot movement animates so lead
/// changes are impossible to miss. Pure chrome — lines and circles only.
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
          height: 30,
          width: double.infinity,
          child: CustomPaint(
            painter: _TugRopePainter(
              share: animatedShare,
              teamAColor: TeamRace.color(RaceTeam.teamA),
              teamBColor: TeamRace.color(RaceTeam.teamB),
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
  });

  final double share;
  final Color teamAColor;
  final Color teamBColor;

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final knotX = size.width * share;

    // Rope halves, tinted per side so the pull direction reads at a glance.
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

    // Slight sag on each half (quadratic droop toward the knot).
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

    // Center stake: the line to beat.
    final stake = Paint()
      ..color = AppColors.textMid.withValues(alpha: 0.5)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(size.width / 2, midY - 9),
      Offset(size.width / 2, midY + 9),
      stake,
    );

    // The knot: wooden ball with rope wraps.
    final knotCenter = Offset(knotX, midY);
    canvas.drawCircle(
      knotCenter,
      8,
      Paint()..color = AppColors.dirtDark,
    );
    canvas.drawCircle(
      knotCenter,
      6.2,
      Paint()..color = AppColors.dirtMid,
    );
    final wrap = Paint()
      ..color = AppColors.dirtDark
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
      oldDelegate.share != share;
}
