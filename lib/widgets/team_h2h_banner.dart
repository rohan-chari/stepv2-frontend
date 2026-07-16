import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../styles.dart';
import '../utils/team_race.dart';

/// TR-803 — the head-to-head SCOREBOARD for team races: each side's plaque with
/// its combined total side by side, and a pill calling out the current lead.
/// Sits at the top of the team standings section (the two rosters render as
/// color-matched columns directly beneath these plaques).
///
/// Totals are ALWAYS honest; stealth/imposter illusions touch individual planks
/// only (TR-658). Rendered as board content (the caller wraps it in a card).
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _endPost(
            team: RaceTeam.teamA,
            name: teamAName,
            total: teamATotal,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _endPost(
            team: RaceTeam.teamB,
            name: teamBName,
            total: teamBTotal,
          ),
        ),
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
    // Light plaques (e.g. the gold team) can't carry white text — flip the
    // title to the team's dark tone and drop the dark drop-shadow.
    final lightPlaque = color.computeLuminance() > 0.55;
    final onPlaque = lightPlaque ? colorDark : Colors.white;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [colorLight, color],
            ),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: colorDark, width: 3),
            boxShadow: [
              BoxShadow(
                color: colorDark,
                offset: const Offset(0, 4),
                blurRadius: 0,
              ),
            ],
          ),
          child: Text(
            name.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: PixelText.title(size: 16, color: onPlaque).copyWith(
              shadows: lightPlaque
                  ? null
                  : const [
                      Shadow(
                        color: Color(0x66000000),
                        offset: Offset(0, 1.5),
                        blurRadius: 0,
                      ),
                    ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _formatSteps(total),
          style: PixelText.number(size: 30, color: colorDark),
        ),
        Text(
          'STEPS',
          style: PixelText.body(size: 11, color: AppColors.textMid),
        ),
      ],
    );
  }

}

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
      ..color = AppColors.textMid.withValues(alpha: 0.5)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(size.width / 2, midY - 9),
      Offset(size.width / 2, midY + 9),
      stake,
    );

    final knotCenter = Offset(knotX, midY);
    canvas.drawCircle(knotCenter, 8, Paint()..color = AppColors.dirtDark);
    canvas.drawCircle(knotCenter, 6.2, Paint()..color = AppColors.dirtMid);
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
