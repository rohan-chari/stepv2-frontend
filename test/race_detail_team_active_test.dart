import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/utils/team_race.dart';
import 'package:step_tracker/widgets/home_course_track.dart';
import 'package:step_tracker/widgets/team_h2h_banner.dart';

// TR-803: ACTIVE team detail — H2H tug-of-war banner above individual planks
// grouped by team. TR-656: a stealthed member's plank reads "???" while the
// team total stays honest and includes their steps (TR-658). TR-804: course
// capys carry their team color for the glow/pennant chrome.

class _ActiveTeamRaceApi extends BackendApiService {
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
      'myStatus': 'ACCEPTED',
      'isCreator': false,
      'powerupsEnabled': false,
      'endsAt': '2026-08-10T12:00:00.000Z',
      'participants': const [
        {'userId': 'user-1', 'displayName': 'Trail Walker', 'status': 'ACCEPTED', 'team': 'TEAM_A'},
        {'userId': 'u2', 'displayName': 'Hill Climber', 'status': 'ACCEPTED', 'team': 'TEAM_A'},
        {'userId': 'u3', 'displayName': 'Sneaky Pete', 'status': 'ACCEPTED', 'team': 'TEAM_B'},
        {'userId': 'u4', 'displayName': 'Marsh Mellow', 'status': 'ACCEPTED', 'team': 'TEAM_B'},
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
      'teams': {
        'teamA': {'name': 'Swift Capys', 'totalSteps': 12340, 'memberCount': 2},
        'teamB': {'name': 'Turbo Beavers', 'totalSteps': 11900, 'memberCount': 2},
      },
      'participants': const [
        {
          'userId': 'user-1',
          'displayName': 'Trail Walker',
          'team': 'TEAM_A',
          'totalSteps': 6200,
          'finishedAt': null,
        },
        {
          'userId': 'u2',
          'displayName': 'Hill Climber',
          'team': 'TEAM_A',
          'totalSteps': 6140,
          'finishedAt': null,
        },
        {
          // Stealthed enemy: plank shows ??? but the 11,900 team total above
          // already includes their hidden steps.
          'userId': 'u3',
          'displayName': '???',
          'stealthed': true,
          'team': 'TEAM_B',
          'totalSteps': 0,
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

class _IndividualActiveApi extends _ActiveTeamRaceApi {
  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async {
    final base = await super.fetchRaceDetails(
      identityToken: identityToken,
      raceId: raceId,
    );
    return {
      ...base,
      'isTeamRace': false,
      'teamSize': null,
      'teamAName': null,
      'teamBName': null,
    };
  }
}

Future<AuthService> _createAuthService() async {
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
  return authService;
}

Future<void> _pump(WidgetTester tester, BackendApiService api) async {
  final authService = await _createAuthService();
  await tester.pumpWidget(
    MaterialApp(
      home: RaceDetailScreen(
        authService: authService,
        raceId: 'race-h2h',
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TR-803: ACTIVE team race shows the H2H banner with honest '
      'backend totals', (tester) async {
    await _pump(tester, _ActiveTeamRaceApi());

    expect(find.byType(TeamH2HBanner), findsOneWidget);
    // Backend team block totals (not the sum of visible planks — TR-658).
    expect(find.text('12,340'), findsOneWidget);
    expect(find.text('11,900'), findsOneWidget);
  });

  testWidgets('TR-803: planks are grouped under team headers', (tester) async {
    await _pump(tester, _ActiveTeamRaceApi());

    expect(find.byKey(const Key('team-group-A')), findsOneWidget);
    expect(find.byKey(const Key('team-group-B')), findsOneWidget);
    expect(find.textContaining('Trail Walker'), findsWidgets);
    expect(find.textContaining('Marsh Mellow'), findsWidgets);
  });

  testWidgets('TR-656: stealthed member planks read ??? while totals stay '
      'honest', (tester) async {
    await _pump(tester, _ActiveTeamRaceApi());

    // The stealthed plank hides identity and steps...
    expect(find.textContaining('???'), findsWidgets);
    // ...but Team B's banner total still counts them (11,900 > visible 5,000).
    expect(find.text('11,900'), findsOneWidget);
  });

  testWidgets('TR-804: course runners carry team colors for the glow chrome',
      (tester) async {
    await _pump(tester, _ActiveTeamRaceApi());

    final track = tester.widget<HomeCourseTrack>(find.byType(HomeCourseTrack));
    final colors = track.runners.map((r) => r.teamColor).toList();
    expect(colors.where((c) => c == TeamRace.color(RaceTeam.teamA)).length, 2);
    expect(colors.where((c) => c == TeamRace.color(RaceTeam.teamB)).length, 2);
  });

  testWidgets('TR-705: individual ACTIVE race shows no H2H banner and no '
      'team groups', (tester) async {
    await _pump(tester, _IndividualActiveApi());

    expect(find.byType(TeamH2HBanner), findsNothing);
    expect(find.byKey(const Key('team-group-A')), findsNothing);
    final track = tester.widget<HomeCourseTrack>(find.byType(HomeCourseTrack));
    expect(track.runners.every((r) => r.teamColor == null), isTrue);
  });
}
