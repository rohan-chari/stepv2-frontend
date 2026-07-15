import 'package:flutter/material.dart';

import '../styles.dart';
import '../utils/team_race.dart';

/// TR-201/202 — "pick your side" sheet for the join channels that aren't the
/// lobby (public browser, share link). Two team plaques around a VS; a side at
/// its `teamSize` cap is physically un-tappable rather than erroring after the
/// fact, mirroring the lobby's "no empty pegs" rule.
///
/// Returns the chosen side's wire value (`TEAM_A`/`TEAM_B`), or null if the
/// user dismissed the sheet.
Future<String?> showTeamSidePicker({
  required BuildContext context,
  required Map<String, dynamic> race,
}) {
  final teamSize = TeamRace.teamSize(race) ?? 0;
  final counts = TeamRace.sideCounts(race);

  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.parchment,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (sheetContext) {
      Widget sideButton(RaceTeam team) {
        final sideLetter = team == RaceTeam.teamA ? 'A' : 'B';
        final filled = (team == RaceTeam.teamA ? counts?.$1 : counts?.$2) ?? 0;
        final full = teamSize > 0 && filled >= teamSize;
        final color = TeamRace.color(team);
        final colorLight = TeamRace.colorLight(team);
        final colorDark = TeamRace.colorDark(team);

        return Expanded(
          child: GestureDetector(
            key: Key('side-pick-$sideLetter'),
            onTap: full
                ? null
                : () => Navigator.of(sheetContext).pop(team.wireValue),
            child: Opacity(
              opacity: full ? 0.45 : 1,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [colorLight, color],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorDark, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: colorDark,
                      offset: const Offset(0, 3),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      TeamRace.teamName(race, team).toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PixelText.title(size: 13, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      full ? 'FULL' : '$filled/$teamSize',
                      style: PixelText.number(
                        size: 12,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'PICK YOUR SIDE',
                style: PixelText.title(size: 16, color: AppColors.textDark),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  sideButton(RaceTeam.teamA),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      'VS',
                      style:
                          PixelText.title(size: 14, color: AppColors.textMid),
                    ),
                  ),
                  sideButton(RaceTeam.teamB),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
