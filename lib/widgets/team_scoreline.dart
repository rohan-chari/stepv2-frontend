import 'package:flutter/material.dart';

import '../styles.dart';
import '../utils/team_race.dart';
import 'team_h2h_banner.dart' show TeamTugRope;

/// TR-806 / TR-809 — the compact team scoreline for list rows and the Home
/// current-race area: "Swift Capys 12,340 — 11,900 Turbo Beavers" over a
/// miniature rope-knot that leans toward the leader.
class TeamScoreline extends StatelessWidget {
  const TeamScoreline({
    super.key,
    required this.teamAName,
    required this.teamBName,
    required this.teamATotal,
    required this.teamBTotal,
    this.showRope = true,
  });

  final String teamAName;
  final String teamBName;
  final int teamATotal;
  final int teamBTotal;
  final bool showRope;

  double get _share {
    final total = teamATotal + teamBTotal;
    if (total <= 0) return 0.5;
    return (1 - teamATotal / total).clamp(0.12, 0.88);
  }

  String _format(int n) {
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
    final colors = AppColors.of(context);
    final aColor = colors.isDark
        ? colors.feedGold
        : TeamRace.colorDark(RaceTeam.teamA);
    final bColor = colors.isDark
        ? colors.successText
        : TeamRace.colorDark(RaceTeam.teamB);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                '$teamAName ${_format(teamATotal)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PixelText.body(size: 12, color: aColor),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Text(
                '—',
                style: PixelText.body(
                  size: 12,
                  color: AppColors.of(context).textMid,
                ),
              ),
            ),
            Flexible(
              child: Text(
                '${_format(teamBTotal)} $teamBName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: PixelText.body(size: 12, color: bColor),
              ),
            ),
          ],
        ),
        if (showRope) ...[
          const SizedBox(height: 1),
          SizedBox(
            height: 16,
            child: FittedBox(
              fit: BoxFit.fill,
              child: SizedBox(
                width: 200,
                height: 24,
                child: TeamTugRope(share: _share),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// TR-806 — the little "2v2" team format chip for race rows and cards.
class TeamFormatChip extends StatelessWidget {
  const TeamFormatChip({super.key, required this.teamSize});

  final int teamSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [TeamColors.teamA, TeamColors.teamB],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.of(context).woodDark, width: 1.5),
      ),
      child: Text(
        TeamRace.formatLabel(teamSize),
        style: PixelText.title(size: 10, color: Colors.white).copyWith(
          shadows: const [
            Shadow(color: Color(0x66000000), offset: Offset(0, 1)),
          ],
        ),
      ),
    );
  }
}
