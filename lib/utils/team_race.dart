import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The two sides of a team race. Team races always have exactly two teams
/// (TR summary); an individual race has none.
enum RaceTeam { teamA, teamB }

extension RaceTeamX on RaceTeam {
  /// Wire value sent to / received from the backend (`RaceTeam` enum).
  String get wireValue => this == RaceTeam.teamA ? 'TEAM_A' : 'TEAM_B';

  /// The opposite side — used for enemy-only powerup targeting and switching.
  RaceTeam get other => this == RaceTeam.teamA ? RaceTeam.teamB : RaceTeam.teamA;
}

/// Parses a wire team string (`TEAM_A` / `TEAM_B`) into a [RaceTeam].
///
/// Returns null for anything else — a null/absent/unknown value must never
/// crash an older-or-newer backend response (TR-705).
RaceTeam? parseRaceTeam(dynamic value) {
  if (value is String) {
    if (value == 'TEAM_A') return RaceTeam.teamA;
    if (value == 'TEAM_B') return RaceTeam.teamB;
  }
  return null;
}

/// Team colors for chrome (plaques, glow, pennants, rope). Locked palette from
/// TR-802/803: Team A warm red, Team B lake blue. Chosen to sit inside the
/// app's wood/parchment world without clashing.
abstract final class TeamColors {
  // Team A — warm terracotta red.
  static const teamA = Color(0xFFC15A46);
  static const teamALight = Color(0xFFDB8272);
  static const teamADark = Color(0xFF8E3A2B);

  // Team B — lake blue.
  static const teamB = Color(0xFF3E7CB1);
  static const teamBLight = Color(0xFF6BA3D0);
  static const teamBDark = Color(0xFF285A85);
}

/// Defensive read/format helpers over the race/participant JSON maps that flow
/// through the app. Everything here treats team fields as optional/nullable so
/// a race without `isTeamRace` renders cleanly as an individual race (TR-705).
abstract final class TeamRace {
  /// True only when the backend explicitly flags this as a team race.
  static bool isTeamRace(Map<String, dynamic> race) => race['isTeamRace'] == true;

  /// Configured per-side cap (1–5), or null if absent/individual.
  static int? teamSize(Map<String, dynamic> race) =>
      (race['teamSize'] as num?)?.toInt();

  /// The recorded winner side, or null (individual race, tie, or not settled).
  static RaceTeam? winnerTeam(Map<String, dynamic> race) =>
      parseRaceTeam(race['winnerTeam']);

  /// The side a participant is on, or null on an individual race.
  static RaceTeam? participantTeam(Map<String, dynamic> participant) =>
      parseRaceTeam(participant['team']);

  /// The display name for a side, with a plain "Team A/B" fallback when the
  /// backend omitted it or sent blank.
  static String teamName(Map<String, dynamic> race, RaceTeam team) {
    final raw = (team == RaceTeam.teamA ? race['teamAName'] : race['teamBName']);
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    return team == RaceTeam.teamA ? 'Team A' : 'Team B';
  }

  /// Chrome color for a side.
  static Color color(RaceTeam team) =>
      team == RaceTeam.teamA ? TeamColors.teamA : TeamColors.teamB;

  static Color colorLight(RaceTeam team) =>
      team == RaceTeam.teamA ? TeamColors.teamALight : TeamColors.teamBLight;

  static Color colorDark(RaceTeam team) =>
      team == RaceTeam.teamA ? TeamColors.teamADark : TeamColors.teamBDark;

  /// "2v2" style format label from a per-side size.
  static String formatLabel(int teamSize) => '${teamSize}v$teamSize';

  /// Participants on a given side (excludes null-team entries).
  static List<Map<String, dynamic>> membersOf(
    List<Map<String, dynamic>> participants,
    RaceTeam team,
  ) {
    return participants
        .where((p) => participantTeam(p) == team)
        .toList(growable: false);
  }

  /// Combined effective steps for a side (sum of member `totalSteps`). The
  /// team total is always honest — never masked by stealth/imposter (TR-658).
  static int teamTotal(
    List<Map<String, dynamic>> participants,
    RaceTeam team,
  ) {
    var total = 0;
    for (final p in participants) {
      if (participantTeam(p) == team) {
        total += (p['totalSteps'] as num?)?.toInt() ?? 0;
      }
    }
    return total;
  }

  /// The side currently ahead, or null on an exact tie.
  static RaceTeam? leadingTeam(List<Map<String, dynamic>> participants) {
    final a = teamTotal(participants, RaceTeam.teamA);
    final b = teamTotal(participants, RaceTeam.teamB);
    if (a == b) return null;
    return a > b ? RaceTeam.teamA : RaceTeam.teamB;
  }

  static int? _blockInt(Map<String, dynamic> race, String side, String field) {
    final teams = race['teams'];
    if (teams is! Map) return null;
    final block = teams[side];
    if (block is! Map) return null;
    final value = block[field];
    return value is num ? value.toInt() : null;
  }

  /// Combined totals from a list/detail payload's `teams` block (same shape
  /// as the progress payload, contract §7). Null when absent/malformed —
  /// callers hide the scoreline rather than showing zeros (TR-806).
  static (int, int)? listTeamTotals(Map<String, dynamic> race) {
    final a = _blockInt(race, 'teamA', 'totalSteps');
    final b = _blockInt(race, 'teamB', 'totalSteps');
    if (a == null || b == null) return null;
    return (a, b);
  }

  /// Accepted member counts per side: prefers the `teams` block's
  /// memberCount, falls back to counting ACCEPTED participants, else null.
  static (int, int)? sideCounts(Map<String, dynamic> race) {
    final a = _blockInt(race, 'teamA', 'memberCount');
    final b = _blockInt(race, 'teamB', 'memberCount');
    if (a != null && b != null) return (a, b);

    final participants =
        (race['participants'] as List?)?.whereType<Map>().toList();
    if (participants == null || participants.isEmpty) return null;
    var countA = 0;
    var countB = 0;
    for (final p in participants) {
      if (p['status'] != 'ACCEPTED') continue;
      final team = parseRaceTeam(p['team']);
      if (team == RaceTeam.teamA) countA++;
      if (team == RaceTeam.teamB) countB++;
    }
    return (countA, countB);
  }

  /// TR-206 public-browser line: "2v2 · 1 slot left on Blue". Names the side
  /// with more room; degrades to just the format when side data is missing.
  static String publicSlotsLabel(Map<String, dynamic> race) {
    final size = teamSize(race) ?? 0;
    final format = size > 0 ? formatLabel(size) : 'Teams';
    final counts = sideCounts(race);
    if (size <= 0 || counts == null) return format;
    final openA = (size - counts.$1).clamp(0, size);
    final openB = (size - counts.$2).clamp(0, size);
    if (openA == 0 && openB == 0) return '$format · full';
    final side = openA >= openB ? RaceTeam.teamA : RaceTeam.teamB;
    final open = math.max(openA, openB);
    return '$format · $open slot${open == 1 ? '' : 's'} left on '
        '${teamName(race, side)}';
  }

  /// True once a participant has forfeited (frozen, out of play). Read
  /// defensively: `forfeitedAt` is additive and absent on older payloads.
  static bool hasForfeited(Map<String, dynamic> participant) {
    final raw = participant['forfeitedAt'];
    return raw is String && raw.isNotEmpty;
  }

  /// TR-651/657 — the pool an OFFENSIVE single-target powerup may aim at.
  ///
  /// Always drops the caster and stealthed racers (existing rules). In a team
  /// race it additionally drops teammates (no friendly fire — the server
  /// answers `INVALID_TARGET`) and forfeited members (excluded from every
  /// targeting pool). Invalid targets are never presented rather than shown
  /// grayed out.
  ///
  /// Defensive: if the viewer has no resolvable team on a supposedly-team
  /// race, fall back to "every rival" rather than leaving them unable to act.
  static List<Map<String, dynamic>> offensiveTargets({
    required List<Map<String, dynamic>> participants,
    required String? myUserId,
    required Map<String, dynamic> race,
  }) {
    RaceTeam? myTeam;
    if (isTeamRace(race)) {
      for (final p in participants) {
        if (p['userId'] == myUserId) {
          myTeam = participantTeam(p);
          break;
        }
      }
    }

    return participants.where((p) {
      if ((p['userId'] as String?) == myUserId) return false;
      if (p['stealthed'] == true) return false;
      if (hasForfeited(p)) return false;
      if (myTeam != null && participantTeam(p) == myTeam) return false;
      return true;
    }).toList(growable: false);
  }

  /// "1 slot left on Turbo Beavers" / "Red is full" copy for list + browser
  /// cards (TR-206, TR-806) and the lobby.
  static String slotsLeftLabel({
    required int teamSize,
    required int filledCount,
    required String teamName,
  }) {
    final left = (teamSize - filledCount).clamp(0, teamSize);
    if (left <= 0) return '$teamName is full';
    return '$left slot${left == 1 ? '' : 's'} left on $teamName';
  }
}

/// OFFLINE FALLBACK ONLY for the create-screen team-name plaques (TR-103,
/// TR-801). The authoritative ≥50-name pool lives backend-side and is served
/// by `GET /races/team-names/suggest` (contract §3b) — the create screen
/// prefers it for both the initial plaques and every dice-reroll. This pool is
/// used only to seed the plaques synchronously (so they're never blank) and
/// when the endpoint is unavailable (older backend / offline), because a
/// cosmetic suggestion must never block race creation.
///
/// Deliberately NOT a mirror of the backend pool — don't grow it to match.
/// Whatever is displayed is sent at creation via the creator-override path,
/// so the plaques always match the race that gets created either way.
const List<String> kTeamNamePool = [
  'Swift Capys',
  'Turbo Beavers',
  'Mossy Rockets',
  'Puddle Jumpers',
  'Thunder Otters',
  'Snack Stealers',
  'Marsh Marchers',
  'Cozy Comets',
  'Pebble Kickers',
  'Waddle Squad',
  'Sunny Sprinters',
  'Fern Flyers',
  'Brave Bogtrotters',
  'Zoomy Zebras',
  'Maple Mavericks',
  'Dandy Dashers',
  'River Rascals',
  'Acorn Avengers',
  'Twilight Trotters',
  'Bumble Stompers',
  'Clover Chargers',
  'Misty Mudlarks',
  'Peppy Pacers',
  'Willow Wanderers',
];

/// A fresh pair of distinct team names from [kTeamNamePool].
(String, String) randomTeamNamePair([math.Random? random]) {
  final rng = random ?? math.Random();
  final first = kTeamNamePool[rng.nextInt(kTeamNamePool.length)];
  String second;
  do {
    second = kTeamNamePool[rng.nextInt(kTeamNamePool.length)];
  } while (second == first);
  return (first, second);
}

/// TR-807 — does this completed race count as a review-prompt "happy moment"
/// (top-3-equivalent)?
///
/// Individual races: top-3 placement (existing rule). Team races: strictly
/// `winnerTeam == your team` — ties never qualify, and forfeited members
/// never see the prompt. Also drives the results-modal celebration, so a tie
/// or a loss never confettis.
bool raceCountsAsReviewHappyMoment(Map<String, dynamic> race) {
  if (TeamRace.isTeamRace(race)) {
    final winner = TeamRace.winnerTeam(race);
    if (winner == null) return false; // running, or a tie (TR-404)
    if (race['myForfeited'] == true) return false;
    final myTeam = parseRaceTeam(race['myTeam']);
    return myTeam != null && myTeam == winner;
  }
  final placement = (race['myPlacement'] as num?)?.toInt();
  return placement != null && placement >= 1 && placement <= 3;
}

/// Maps backend team-race error codes to copy in the app's playful voice.
/// Codes are defined in the requirements (§1–2, §9). Unknown codes fall back to
/// a safe generic message so a newer backend never shows a raw code.
String teamRaceErrorCopy(String? code, {String? friendName}) {
  switch (code) {
    case 'TEAM_FULL':
      return "That side's full — hop on the other team!";
    case 'TEAMS_UNEVEN':
      return 'Teams have to be even to start. Even them up!';
    case 'TEAM_SIZE_TOO_SMALL':
      return "Can't shrink below a side that's already filled.";
    case 'RACE_ALREADY_STARTED':
      return "This race already started — you can't hop in now.";
    case 'UPDATE_REQUIRED':
      return 'Update the app to join team races.';
    case 'INVITEE_NEEDS_UPDATE':
      final who = (friendName != null && friendName.trim().isNotEmpty)
          ? friendName.trim()
          : 'Your friend';
      return '$who needs to update the app to join team races.';
    case 'FEATURE_DISABLED':
      return 'Team races are taking a quick nap. Try again later!';
    case 'TEAM_NAMES_IDENTICAL':
      return 'Give the two teams different names.';
    case 'IMMUTABLE_FIELD':
      return "That can't be changed once the race is set up.";
    case 'INVALID_TARGET':
      return 'You can only target the enemy team.';
    default:
      return 'Something went sideways. Give it another try!';
  }
}
