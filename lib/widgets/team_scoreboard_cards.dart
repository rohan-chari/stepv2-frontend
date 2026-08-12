import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/animals.dart';
import '../styles.dart';
import '../utils/at_name.dart';
import '../utils/team_race.dart';
import 'home_course_track.dart';
import 'home_hero_scene.dart';

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
      final rawSteps = p['totalSteps'];
      final steps = rawSteps is num ? rawSteps.toInt() : 0;
      if (steps > bestSteps) {
        bestSteps = steps;
        best = p;
      }
    }
    if (best == null) return null;
    final rawAccessories = best['accessories'];
    return TeamCardMember(
      displayName: best['displayName'] is String
          ? best['displayName'] as String
          : '???',
      accessories: rawAccessories is List
          ? [
              for (final item in rawAccessories)
                if (item is Map<String, dynamic>) item,
            ]
          : const [],
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

enum TeamLaneState { leading, trailing, neutral }

({TeamLaneState teamA, TeamLaneState teamB}) teamLaneStatesForTotals(
  int? teamATotal,
  int? teamBTotal,
) {
  if (teamATotal == null || teamBTotal == null || teamATotal == teamBTotal) {
    return (teamA: TeamLaneState.neutral, teamB: TeamLaneState.neutral);
  }
  return teamATotal > teamBTotal
      ? (teamA: TeamLaneState.leading, teamB: TeamLaneState.trailing)
      : (teamA: TeamLaneState.trailing, teamB: TeamLaneState.leading);
}

/// The two independent team hero cards. Roster cards deliberately live below
/// this pair rather than inside a full-height team wrapper: the scoreboard
/// needs a clear team-summary → momentum → individual-racers hierarchy.
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

  @override
  Widget build(BuildContext context) {
    final states = teamLaneStatesForTotals(teamATotal, teamBTotal);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _card(
            context,
            RaceTeam.teamA,
            teamAName,
            teamATotal,
            teamALeader,
            states.teamA,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _card(
            context,
            RaceTeam.teamB,
            teamBName,
            teamBTotal,
            teamBLeader,
            states.teamB,
          ),
        ),
      ],
    );
  }

  Widget _card(
    BuildContext context,
    RaceTeam team,
    String name,
    int? total,
    TeamCardMember? leader,
    TeamLaneState state,
  ) {
    final colors = AppColors.of(context);
    final teamLight = TeamRace.colorLight(team, context);
    final teamDark = TeamRace.colorDark(team, context);
    final onText = TeamRace.textColorOn(team, context);
    final fill = team == RaceTeam.teamB
        ? Color.lerp(
            colors.parchmentLight,
            colors.roofRidge,
            state == TeamLaneState.leading ? 0.16 : 0.08,
          )!
        : Color.lerp(teamLight, colors.parchmentLight, switch (state) {
            TeamLaneState.leading => 0.10,
            TeamLaneState.neutral => 0.42,
            TeamLaneState.trailing => 0.72,
          })!;
    final border = switch (state) {
      TeamLaneState.leading => colors.medalGold,
      TeamLaneState.neutral => Color.lerp(
        team == RaceTeam.teamB ? colors.roofRidge : teamDark,
        colors.parchmentBorder,
        team == RaceTeam.teamB ? 0.72 : 0.42,
      )!,
      TeamLaneState.trailing => colors.parchmentBorder,
    };

    final card = Container(
      key: ValueKey('team-card-${team.wireValue}'),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: border, width: 2.5),
        boxShadow: state == TeamLaneState.leading
            ? [
                BoxShadow(
                  color: colors.medalGold.withValues(alpha: 0.30),
                  blurRadius: 9,
                  spreadRadius: 1,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10.5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 148,
              child: _TeamHeroScene(
                team: team,
                leader: leader,
                laneState: state,
                palette: colors,
              ),
            ),
            SizedBox(
              height: 88,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Column(
                  children: [
                    SizedBox(
                      height: 34,
                      child: Center(
                        child: Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: PixelText.title(size: 13, color: onText),
                        ),
                      ),
                    ),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          total == null ? '—' : formatTeamSteps(total),
                          maxLines: 1,
                          style: PixelText.number(size: 30, color: onText),
                        ),
                      ),
                    ),
                    Text(
                      'TEAM STEPS',
                      textAlign: TextAlign.center,
                      style: PixelText.body(
                        size: 9.5,
                        color: colors.textMid,
                      ).copyWith(letterSpacing: 0.7),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Semantics(
      label: state == TeamLaneState.leading ? '$name leading' : null,
      child: Stack(
        children: [
          card,
          if (state == TeamLaneState.leading)
            Positioned.fill(
              child: IgnorePointer(
                child: SizedBox(
                  key: ValueKey('team-leading-${team.wireValue}'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A compact window onto the same living pixel world as the Home hero.
class _TeamHeroScene extends StatelessWidget {
  const _TeamHeroScene({
    required this.team,
    required this.leader,
    required this.laneState,
    required this.palette,
  });

  final RaceTeam team;
  final TeamCardMember? leader;

  // Kept with the scene input even though leadership is expressed by the
  // unchanged card outline. The course wash must never grow stronger when a
  // lane leads, which would compete with that gold treatment.
  final TeamLaneState laneState;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final member = leader;
    final alignment = team == RaceTeam.teamA
        ? const Alignment(-0.45, 1)
        : const Alignment(0.45, 1);
    final teamLight = TeamRace.colorLight(team, context);
    final parchmentWashOpacity = palette.isDark ? 0.14 : 0.24;
    final teamWashOpacity = palette.isDark ? 0.08 : 0.10;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return RepaintBoundary(
      key: ValueKey('team-hero-scene-${team.wireValue}'),
      child: ClipRect(
        child: HomeHeroScene(
          key: ValueKey('team-home-hero-${team.wireValue}'),
          groundHeight: 34,
          groundScrollSpeed: reduceMotion ? 0 : 26,
          skyAlignment: alignment,
          excludeBackgroundSemantics: true,
          child: Stack(
            key: ValueKey('team-hero-lane-${laneState.name}'),
            fit: StackFit.expand,
            children: [
              ExcludeSemantics(
                child: ColoredBox(
                  key: ValueKey('team-hero-parchment-wash-${team.wireValue}'),
                  color: palette.parchmentLight.withValues(
                    alpha: parchmentWashOpacity,
                  ),
                ),
              ),
              ExcludeSemantics(
                child: ColoredBox(
                  key: ValueKey('team-hero-team-wash-${team.wireValue}'),
                  color: teamLight.withValues(alpha: teamWashOpacity),
                ),
              ),
              if (member == null)
                Center(
                  child: Text(
                    'No one yet',
                    style: PixelText.body(size: 12, color: palette.textMid),
                  ),
                )
              else ...[
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final geometry = _containedSpriteGeometry(
                        member,
                        constraints.maxWidth,
                      );
                      return Stack(
                        children: [
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: geometry.bottom,
                            child: Center(
                              child: AnimatedCapybaraWithAccessories(
                                accessories: geometry.accessories,
                                size: geometry.size,
                                stepDuration: const Duration(milliseconds: 720),
                                animate: !reduceMotion,
                                animal: member.animal,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Positioned(
                  top: 6,
                  left: 6,
                  right: 6,
                  child: Center(
                    child: Container(
                      key: const ValueKey('team-hero-caption-scrim'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: palette.parchment.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Semantics(
                        label: atName(member.displayName),
                        excludeSemantics: true,
                        child: Text(
                          atName(member.displayName),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PixelText.body(
                            size: 11.5,
                            color: palette.textDark,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Keeps the Home baseline fixed while shrinking only when transformed
  /// behind-body art would leave this half-card. Cosmetics that cannot fit at
  /// the 48px compatibility floor are omitted from this scene only.
  ({double size, double bottom, List<Map<String, dynamic>> accessories})
  _containedSpriteGeometry(TeamCardMember member, double sceneWidth) {
    const sceneHeight = 148.0;
    const groundHeight = 34.0;
    const groundSink = 4.0;
    const horizontalMargin = 0.0;
    const artTop = 30.0;
    const minSize = 48.0;
    const maxSize = 108.0;
    final normalized = normalizedAccessoriesForAnimal(
      member.accessories,
      member.animal,
    );

    bool isBehind(Map<String, dynamic> accessory) {
      final metadata = accessory['renderMetadata'];
      return metadata is Map<String, dynamic> &&
          metadata['renderLayer'] == 'behind';
    }

    bool accessoryFits(Map<String, dynamic> accessory, double size) {
      final metadata = accessory['renderMetadata'] as Map<String, dynamic>;
      final bounds = _behindAccessoryBounds(
        metadata: metadata,
        animal: member.animal,
        size: size,
        sceneWidth: sceneWidth,
      );
      return bounds != null &&
          bounds.left >= horizontalMargin &&
          bounds.right <= sceneWidth - horizontalMargin &&
          bounds.top >= artTop &&
          bounds.bottom <= sceneHeight;
    }

    final retained = <Map<String, dynamic>>[
      for (final accessory in normalized)
        if (!isBehind(accessory) || accessoryFits(accessory, minSize))
          accessory,
    ];

    bool fits(double size) {
      if (!size.isFinite || size < minSize || size > maxSize) return false;
      if (size > sceneWidth - horizontalMargin * 2) return false;
      final bottom = groundHeight - groundSink - size * 0.22;
      final hostTop = sceneHeight - bottom - size;
      if (!bottom.isFinite || !hostTop.isFinite || hostTop < artTop) {
        return false;
      }
      for (final accessory in retained) {
        if (isBehind(accessory) && !accessoryFits(accessory, size)) {
          return false;
        }
      }
      return true;
    }

    var low = minSize;
    var high = maxSize;
    if (fits(maxSize)) {
      low = maxSize;
    } else {
      for (var iteration = 0; iteration < 24; iteration++) {
        final candidate = (low + high) / 2;
        if (fits(candidate)) {
          low = candidate;
        } else {
          high = candidate;
        }
      }
    }
    return (
      size: low,
      bottom: groundHeight - groundSink - low * 0.22,
      accessories: retained,
    );
  }

  Rect? _behindAccessoryBounds({
    required Map<String, dynamic> metadata,
    required String? animal,
    required double size,
    required double sceneWidth,
  }) {
    final offsetX = _metadataOffset(metadata['offsetX'], size);
    final offsetY = _metadataOffset(metadata['offsetY'], size);
    final scale = _metadataDouble(metadata['scale']) ?? 1;
    final rotation = _metadataDouble(metadata['rotation']) ?? 0;
    if (offsetX == null ||
        offsetY == null ||
        !scale.isFinite ||
        scale <= 0 ||
        !rotation.isFinite) {
      return null;
    }
    final baseline = animalSpriteFor(animal).baselineOffset * size;
    final center = Offset(
      sceneWidth / 2 + offsetX,
      148 - (34 - 4 - size * 0.22) - size / 2 + offsetY + baseline,
    );
    final cosine = math.cos(rotation);
    final sine = math.sin(rotation);
    final half = size * scale / 2;
    final corners =
        <Offset>[
          const Offset(-1, -1),
          const Offset(1, -1),
          const Offset(1, 1),
          const Offset(-1, 1),
        ].map((unit) {
          final x = unit.dx * half;
          final y = unit.dy * half;
          return center + Offset(x * cosine - y * sine, x * sine + y * cosine);
        });
    var left = double.infinity;
    var top = double.infinity;
    var right = double.negativeInfinity;
    var bottom = double.negativeInfinity;
    for (final corner in corners) {
      if (!corner.dx.isFinite || !corner.dy.isFinite) return null;
      left = math.min(left, corner.dx);
      top = math.min(top, corner.dy);
      right = math.max(right, corner.dx);
      bottom = math.max(bottom, corner.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  double? _metadataOffset(dynamic value, double size) {
    final parsed = _metadataDouble(value) ?? 0;
    if (!parsed.isFinite) return null;
    final result = parsed.abs() <= 1 ? parsed * size : parsed;
    return result.isFinite ? result : null;
  }

  double? _metadataDouble(dynamic value) {
    if (value is num) {
      final parsed = value.toDouble();
      return parsed.isFinite ? parsed : null;
    }
    if (value is String) {
      final parsed = double.tryParse(value);
      return parsed != null && parsed.isFinite ? parsed : null;
    }
    return null;
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
        TextSpan(text: 'Dead even. ', style: body),
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
