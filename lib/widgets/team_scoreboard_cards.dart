import 'package:flutter/material.dart';

import '../config/animals.dart';
import '../styles.dart';
import '../utils/at_name.dart';
import '../utils/team_race.dart';
import 'home_course_track.dart';

/// The member pictured on a team card — that side's current top scorer.
@immutable
class TeamCardMember {
  const TeamCardMember({
    required this.displayName,
    required this.accessories,
    this.animal,
  });

  final String displayName;
  final List<Map<String, dynamic>> accessories;

  /// Base character assetKey (e.g. 'corgi_puppy'); null/unknown = capybara.
  final String? animal;

  /// The top scorer on [team], or null when the side is empty. A stealthed
  /// member is skipped for the PORTRAIT only (their sprite and name are hidden
  /// on their own plank, so picturing them here would leak both) — the team
  /// TOTAL that sits under the portrait stays honest either way.
  static TeamCardMember? topScorerOf(
    List<Map<String, dynamic>> participants,
    RaceTeam team,
  ) {
    Map<String, dynamic>? best;
    var bestSteps = -1;
    for (final p in participants) {
      if (TeamRace.participantTeam(p) != team) continue;
      if (p['stealthed'] == true) continue;
      final steps = (p['totalSteps'] as num?)?.toInt() ?? 0;
      if (steps > bestSteps) {
        bestSteps = steps;
        best = p;
      }
    }
    if (best == null) return null;
    return TeamCardMember(
      displayName: best['displayName'] as String? ?? '???',
      accessories:
          (best['accessories'] as List?)?.cast<Map<String, dynamic>>() ??
          const [],
      animal: animalFromJson(best['animal']),
    );
  }
}

/// Thousands-separated step count.
String formatTeamSteps(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// The color-legend row above the cards: `● Team A   vs   ● Team B`. Without
/// it the two card colors are unlabelled, and the roster columns below key off
/// the same colors.
class TeamVsChips extends StatelessWidget {
  const TeamVsChips({
    super.key,
    required this.teamAName,
    required this.teamBName,
  });

  final String teamAName;
  final String teamBName;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(child: _chip(context, RaceTeam.teamA, teamAName)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'vs',
            style: PixelText.body(size: 12, color: colors.textMid),
          ),
        ),
        Flexible(child: _chip(context, RaceTeam.teamB, teamBName)),
      ],
    );
  }

  Widget _chip(BuildContext context, RaceTeam team, String name) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.parchmentLight,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: TeamRace.colorDark(team, context),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: TeamRace.color(team, context),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // Team colour AS TEXT must go through textColorOn — `colorDark`
              // is a chrome token and renders at 1.09:1 on the night board.
              style: PixelText.title(
                size: 12,
                color: TeamRace.textColorOn(team, context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TeamScoreboardCards extends StatelessWidget {
  const TeamScoreboardCards({
    super.key,
    required this.teamAName,
    required this.teamBName,
    required this.teamATotal,
    required this.teamBTotal,
    this.teamALeader,
    this.teamBLeader,
  });

  final String teamAName;
  final String teamBName;
  final int? teamATotal;
  final int? teamBTotal;
  final TeamCardMember? teamALeader;
  final TeamCardMember? teamBLeader;

  /// The side ahead, or null on a tie OR whenever either total is unknown —
  /// a ribbon crowned off a half-known scoreline would be a confident lie.
  RaceTeam? get leadingTeam {
    final a = teamATotal;
    final b = teamBTotal;
    if (a == null || b == null || a == b) return null;
    return a > b ? RaceTeam.teamA : RaceTeam.teamB;
  }

  @override
  Widget build(BuildContext context) {
    final leader = leadingTeam;
    // IntrinsicHeight so a wrapping team name on one side can't leave the two
    // cards at different heights.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _card(
              context: context,
              team: RaceTeam.teamA,
              name: teamAName,
              total: teamATotal,
              member: teamALeader,
              isLeading: leader == RaceTeam.teamA,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _card(
              context: context,
              team: RaceTeam.teamB,
              name: teamBName,
              total: teamBTotal,
              member: teamBLeader,
              isLeading: leader == RaceTeam.teamB,
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({
    required BuildContext context,
    required RaceTeam team,
    required String name,
    required int? total,
    required TeamCardMember? member,
    required bool isLeading,
  }) {
    final colors = AppColors.of(context);
    final color = TeamRace.color(team, context);
    final colorLight = TeamRace.colorLight(team, context);
    final colorDark = TeamRace.colorDark(team, context);
    final onText = TeamRace.textColorOn(team, context);

    final card = Container(
      key: ValueKey('team-card-${team.wireValue}'),
      decoration: BoxDecoration(
        // The team colour is the card's whole ground, not a band behind the
        // portrait — the card IS the team. The leader sits a little stronger.
        color: colorLight.withValues(alpha: isLeading ? 0.30 : 0.18),
        borderRadius: BorderRadius.circular(12),
        // Same WIDTH on both cards, always. A thicker border on the leader
        // insets its content by the difference, which knocks the two 30pt
        // totals off a shared baseline. The leader is distinguished by border
        // COLOUR and the outer ring below — neither of which moves a pixel.
        border: Border.all(
          color: isLeading ? colorDark : colors.parchmentBorder,
          width: 2.5,
        ),
        // The crown, replacing the old LEADING ribbon: a halo drawn OUTSIDE the
        // card's box (spread, no blur, no offset). The ribbon was a strip in
        // the layout, so it had to be reserved on the trailing card too, which
        // left an empty band above the loser's portrait. An outline costs no
        // layout at all, so nothing needs reserving and nothing can misalign.
        boxShadow: isLeading
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.55),
                  spreadRadius: 3,
                ),
              ]
            : null,
      ),
      // Outer radius 12 minus the 2.5pt border = 9.5, so the ribbon and
      // portrait corners sit flush inside the border instead of 0.5px proud.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9.5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _portrait(context, team, member),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: PixelText.title(size: 15, color: onText),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    total == null ? '—' : formatTeamSteps(total),
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: PixelText.number(size: 30, color: onText),
                  ),
                  Text(
                    'TEAM STEPS',
                    textAlign: TextAlign.center,
                    style: PixelText.body(
                      size: 10,
                      color: colors.textMid,
                    ).copyWith(letterSpacing: 0.8),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (!isLeading) return card;
    // The outline carries "leading" visually, but it says nothing to a screen
    // reader and gives tests nothing to find — both of which the LEADING
    // ribbon's text used to provide. This restores them without occupying any
    // layout, so the trailing card still needs no reserved counterpart.
    return Semantics(
      label: '$name leading',
      child: KeyedSubtree(
        key: ValueKey('team-leading-${team.wireValue}'),
        child: card,
      ),
    );
  }

  Widget _portrait(BuildContext context, RaceTeam team, TeamCardMember? m) {
    final colors = AppColors.of(context);
    // No fill of its own: the card behind it already carries the team tint, so
    // a second wash here would band the card in two shades.
    return SizedBox(
      height: 148,
      child: m == null
          ? Center(
              child: Text(
                'No one yet',
                style: PixelText.body(size: 12, color: colors.textMid),
              ),
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CapybaraSpriteWithAccessories(
                  accessories: m.accessories,
                  capybaraSize: 108,
                  frameIndex: 0,
                  animal: m.animal,
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    atName(m.displayName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PixelText.body(size: 11.5, color: colors.textMid),
                  ),
                ),
              ],
            ),
    );
  }

}

/// The momentum strip under the cards: "Keep it up! 11,354 steps ahead!".
///
/// Hidden entirely when either total is unknown (stealth) — there is no honest
/// gap to quote. [myTeam] is null for a spectator, who gets neutral phrasing.
class TeamLeadBanner extends StatelessWidget {
  const TeamLeadBanner({
    super.key,
    required this.teamAName,
    required this.teamBName,
    required this.teamATotal,
    required this.teamBTotal,
    required this.myTeam,
  });

  final String teamAName;
  final String teamBName;
  final int? teamATotal;
  final int? teamBTotal;
  final RaceTeam? myTeam;

  @override
  Widget build(BuildContext context) {
    final a = teamATotal;
    final b = teamBTotal;
    if (a == null || b == null) return const SizedBox.shrink();

    final colors = AppColors.of(context);
    final leader = a == b ? null : (a > b ? RaceTeam.teamA : RaceTeam.teamB);
    final diff = (a - b).abs();

    // Tint follows the LEADING side (neutral parchment on a tie), so the strip
    // colour and the raised card always agree.
    final tintTeam = leader;
    final fill = tintTeam == null
        ? colors.parchmentLight
        : TeamRace.colorLight(tintTeam, context).withValues(alpha: 0.22);
    final border = tintTeam == null
        ? colors.parchmentBorder
        : TeamRace.colorDark(tintTeam, context);
    final numberColor = tintTeam == null
        ? colors.textDark
        : TeamRace.textColorOn(tintTeam, context);

    final body = PixelText.body(size: 12.5, color: colors.textDark);
    final number = PixelText.number(size: 15, color: numberColor);

    final List<InlineSpan> spans;
    if (leader == null) {
      spans = [
        TextSpan(text: 'Dead even — ', style: body),
        TextSpan(text: formatTeamSteps(a), style: number),
        TextSpan(text: ' steps each.', style: body),
      ];
    } else if (myTeam == null) {
      spans = [
        TextSpan(
          text: leader == RaceTeam.teamA ? teamAName : teamBName,
          style: body,
        ),
        TextSpan(text: ' leads by ', style: body),
        TextSpan(text: formatTeamSteps(diff), style: number),
        TextSpan(text: '.', style: body),
      ];
    } else if (myTeam == leader) {
      spans = [
        TextSpan(text: 'Keep it up! ', style: body),
        TextSpan(text: formatTeamSteps(diff), style: number),
        TextSpan(text: ' steps ahead!', style: body),
      ];
    } else {
      spans = [
        TextSpan(text: 'Push! ', style: body),
        TextSpan(text: formatTeamSteps(diff), style: number),
        TextSpan(text: ' steps behind.', style: body),
      ];
    }

    return Container(
      key: const Key('team-lead-banner'),
      width: double.infinity,
      // The gap below belongs to the banner, not the caller — when the banner
      // hides itself on unknown totals a caller-owned spacer would survive as a
      // stray 14px hole between the cards and the rosters.
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: border, width: 1.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('📣', style: TextStyle(fontSize: 15)),
          const SizedBox(width: 8),
          Flexible(
            child: Text.rich(
              TextSpan(children: spans),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
