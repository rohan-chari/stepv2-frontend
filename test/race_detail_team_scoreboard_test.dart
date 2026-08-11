import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/utils/team_race.dart';
import 'package:step_tracker/widgets/team_scoreboard_cards.dart';

// Integration cover for the redesigned ACTIVE team SCOREBOARD, pumped through
// the REAL screen (CLAUDE.md: integration over unit). The leaf widgets have
// their own tests in team_scoreboard_cards_test.dart; what can only be checked
// here is the SCREEN's plumbing — which totals feed the ribbon, which member
// gets the portrait, and which side the viewer is judged to be on.
//
// The stealth case is the one that matters: the cards render the backend's
// honest `teams` block while the portrait/roster read the participants list,
// and those two disagree exactly when a member is hidden.

class _ScoreboardApi extends BackendApiService {
  _ScoreboardApi({
    this.teamATotal = 12340,
    this.teamBTotal = 11900,
    this.stealthTeamB = false,
    this.omitTeamsBlock = false,
    this.myTeam = 'TEAM_A',
  });

  final int teamATotal;
  final int teamBTotal;
  final bool stealthTeamB;

  /// Drops the honest `teams` block so totals fall back to summing planks —
  /// the path where a stealthed member makes a side genuinely unknowable.
  final bool omitTeamsBlock;

  /// The side `user-1` (the viewer) sits on; null makes them a spectator.
  final String? myTeam;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async {
    return {
      'id': raceId,
      'name': 'Team Clash',
      'status': 'ACTIVE',
      'isTeamRace': true,
      'teamSize': 2,
      'teamAName': 'Swift Capys',
      'teamBName': 'Turbo Beavers',
      'maxDurationDays': 7,
      'buyInAmount': 0,
      'payoutPreset': 'WINNER_TAKES_ALL',
      'potCoins': 0,
      'myStatus': myTeam == null ? 'NONE' : 'ACCEPTED',
      'isCreator': false,
      'powerupsEnabled': false,
      'endsAt': '2026-08-10T12:00:00.000Z',
      'participants': [
        if (myTeam != null)
          {
            'userId': 'user-1',
            'displayName': 'Trail Walker',
            'status': 'ACCEPTED',
            'team': myTeam,
          },
        {
          'userId': 'u2',
          'displayName': 'Hill Climber',
          'status': 'ACCEPTED',
          'team': 'TEAM_A',
        },
        {
          'userId': 'u3',
          'displayName': 'Sneaky Pete',
          'status': 'ACCEPTED',
          'team': 'TEAM_B',
        },
        {
          'userId': 'u4',
          'displayName': 'Marsh Mellow',
          'status': 'ACCEPTED',
          'team': 'TEAM_B',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async {
    return {
      'status': 'ACTIVE',
      if (!omitTeamsBlock)
        'teams': {
          'teamA': {'name': 'Swift Capys', 'totalSteps': teamATotal},
          'teamB': {'name': 'Turbo Beavers', 'totalSteps': teamBTotal},
        },
      'participants': [
        if (myTeam != null)
          {
            'userId': 'user-1',
            'displayName': 'Trail Walker',
            'team': myTeam,
            'totalSteps': 6200,
            'finishedAt': null,
          },
        {
          'userId': 'u2',
          'displayName': 'Hill Climber',
          'team': 'TEAM_A',
          // Deliberately the biggest number on Team A, so the portrait has a
          // clear winner that is NOT the viewer.
          'totalSteps': 9000,
          'finishedAt': null,
        },
        {
          'userId': 'u3',
          'displayName': stealthTeamB ? '???' : 'Sneaky Pete',
          if (stealthTeamB) 'stealthed': true,
          'team': 'TEAM_B',
          // null (not 0) is what the backend sends for a hidden member.
          'totalSteps': stealthTeamB ? null : 7000,
          'finishedAt': null,
        },
        {
          'userId': 'u4',
          'displayName': 'Marsh Mellow',
          'team': 'TEAM_B',
          'totalSteps': 5000,
          'finishedAt': null,
        },
      ],
      'powerupData': const {
        'enabled': false,
        'inventory': [],
        'powerupSlots': 3,
        'queuedBoxCount': 0,
        'activeEffects': [],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaceFeed({
    String? cursor,
    required String identityToken,
    required String raceId,
  }) async {
    return const {'events': []};
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    return const {'coins': 320, 'heldCoins': 0};
  }
}

Future<void> _pump(WidgetTester tester, BackendApiService api) async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_coins': 420,
    'auth_held_coins': 0,
  });
  final authService = AuthService();
  await authService.restoreSession();
  await tester.pumpWidget(
    MaterialApp(
      home: RaceDetailScreen(
        authService: authService,
        raceId: 'race-scoreboard',
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

// The LEADING ribbon became an outline on the card itself; this key marks the
// crowned card so "which side is leading?" stays assertable.
final _leadingA = find.byKey(const ValueKey('team-leading-TEAM_A'));
final _leadingB = find.byKey(const ValueKey('team-leading-TEAM_B'));
final _banner = find.byKey(const Key('team-lead-banner'));

/// Scopes a finder to one team CARD. The `@name` caption also appears in the
/// roster cell below, so an unscoped find.text matches twice.
Finder _inCard(RaceTeam team, Finder matching) => find.descendant(
  of: find.byKey(ValueKey('team-card-${team.wireValue}')),
  matching: matching,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the scoreboard renders cards, chips and the lead banner', (
    tester,
  ) async {
    await _pump(tester, _ScoreboardApi());

    expect(find.byType(TeamVsChips), findsOneWidget);
    expect(find.byType(TeamScoreboardCards), findsOneWidget);
    expect(_banner, findsOneWidget);
    expect(find.text('12,340'), findsOneWidget);
    expect(find.text('11,900'), findsOneWidget);
  });

  testWidgets('the leading outline follows the higher BACKEND total', (
    tester,
  ) async {
    // Team B leads on the honest team block (20,000) even though the visible
    // planks sum higher for A — the ribbon must follow the rendered totals.
    await _pump(tester, _ScoreboardApi(teamATotal: 9000, teamBTotal: 20000));

    expect(_leadingB, findsOneWidget);
    expect(_leadingA, findsNothing);
  });

  testWidgets('the portrait pictures that side\'s top scorer', (tester) async {
    await _pump(tester, _ScoreboardApi());

    // Hill Climber (9,000) outscores the viewer (6,200) on Team A, so the
    // card portrait is captioned with them, not with the viewer.
    expect(_inCard(RaceTeam.teamA, find.text('@Hill Climber')), findsOneWidget);
    expect(_inCard(RaceTeam.teamA, find.text('@Trail Walker')), findsNothing);
    // Team B's card is captioned with its own top scorer.
    expect(_inCard(RaceTeam.teamB, find.text('@Sneaky Pete')), findsOneWidget);
  });

  testWidgets('the banner cheers a viewer on the leading side', (tester) async {
    // Viewer on Team A, which leads 12,340 - 11,900.
    await _pump(tester, _ScoreboardApi());

    expect(find.textContaining('Keep it up!'), findsOneWidget);
    expect(find.textContaining('440'), findsOneWidget);
    expect(find.textContaining('Push!'), findsNothing);
  });

  testWidgets('the banner pushes a viewer on the trailing side', (
    tester,
  ) async {
    // Same scoreline, viewer moved to the trailing side. Deliberately a
    // separate test: re-pumping RaceDetailScreen in one body reuses the State
    // (didUpdateWidget, not initState), so the second scenario never refetches.
    await _pump(tester, _ScoreboardApi(myTeam: 'TEAM_B'));

    expect(find.textContaining('Push!'), findsOneWidget);
    expect(find.textContaining('440'), findsOneWidget);
    expect(find.textContaining('Keep it up!'), findsNothing);
  });

  testWidgets('a spectator gets neutral third-person copy', (tester) async {
    await _pump(tester, _ScoreboardApi(myTeam: null));

    expect(find.textContaining('leads by'), findsOneWidget);
    expect(find.textContaining('Keep it up!'), findsNothing);
    expect(find.textContaining('Push!'), findsNothing);
  });

  testWidgets('a tie crowns neither side', (tester) async {
    await _pump(tester, _ScoreboardApi(teamATotal: 9000, teamBTotal: 9000));

    expect(_leadingA, findsNothing);
    expect(_leadingB, findsNothing);
    expect(find.textContaining('Dead even'), findsOneWidget);
  });

  testWidgets('an unknowable total dashes out, crowns no one, hides the '
      'banner', (tester) async {
    // No `teams` block + a stealthed member on B => B's total is genuinely
    // unknown. Rendering 5,000 (the visible plank sum) would be a confident
    // undercount, and crowning A off it would compound the lie.
    await _pump(tester, _ScoreboardApi(stealthTeamB: true, omitTeamsBlock: true));

    expect(find.text('—'), findsOneWidget);
    expect(_leadingA, findsNothing);
    expect(_leadingB, findsNothing);
    expect(_banner, findsNothing);
    expect(find.textContaining('ahead'), findsNothing);
  });

  testWidgets('a stealthed member keeps the honest total but leaves the '
      'portrait alone', (tester) async {
    // WITH the teams block the totals stay honest (11,900 includes the hidden
    // steps), but the portrait must still skip the stealthed racer rather than
    // leaking their name and cosmetics.
    await _pump(tester, _ScoreboardApi(stealthTeamB: true));

    expect(find.text('11,900'), findsOneWidget);
    expect(_inCard(RaceTeam.teamB, find.text('@Marsh Mellow')), findsOneWidget);
    expect(find.text('@Sneaky Pete'), findsNothing);
  });
}
