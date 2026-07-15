import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// TR-402/403/404 + TR-807 on the race-detail COMPLETED view: a settled team
// race crowns the winning TEAM (winnerUserId stays null), groups the final
// standings by team, and a tie shows the refund copy instead of a winner.

class _CompletedTeamRaceApi extends BackendApiService {
  _CompletedTeamRaceApi({this.winnerTeam = 'TEAM_A'});

  final String? winnerTeam;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async {
    return {
      'id': raceId,
      'name': 'Team Clash',
      'status': 'COMPLETED',
      'isTeamRace': true,
      'teamSize': 2,
      'teamAName': 'Swift Capys',
      'teamBName': 'Turbo Beavers',
      // TR-402: team races record winnerTeam; winnerUserId/winner stays null.
      'winnerTeam': winnerTeam,
      'winner': null,
      'maxDurationDays': 7,
      'buyInAmount': 30,
      'payoutPreset': 'WINNER_TAKES_ALL',
      'potCoins': 120,
      'myStatus': 'ACCEPTED',
      'isCreator': false,
      'participants': const [
        {
          'userId': 'user-1',
          'displayName': 'Trail Walker',
          'status': 'ACCEPTED',
          'team': 'TEAM_A',
          'totalSteps': 6200,
          'placement': 1,
        },
        {
          'userId': 'u2',
          'displayName': 'Hill Climber',
          'status': 'ACCEPTED',
          'team': 'TEAM_A',
          'totalSteps': 6140,
          'placement': 1,
        },
        {
          'userId': 'u3',
          'displayName': 'Sneaky Pete',
          'status': 'ACCEPTED',
          'team': 'TEAM_B',
          'totalSteps': 5900,
          'placement': 2,
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
      'status': 'COMPLETED',
      'teams': {
        'teamA': {'name': 'Swift Capys', 'totalSteps': 12340, 'memberCount': 2},
        'teamB': {'name': 'Turbo Beavers', 'totalSteps': 5900, 'memberCount': 1},
      },
      'participants': const [
        {
          'userId': 'user-1',
          'displayName': 'Trail Walker',
          'team': 'TEAM_A',
          'totalSteps': 6200,
        },
        {
          'userId': 'u2',
          'displayName': 'Hill Climber',
          'team': 'TEAM_A',
          'totalSteps': 6140,
        },
        {
          'userId': 'u3',
          'displayName': 'Sneaky Pete',
          'team': 'TEAM_B',
          'totalSteps': 5900,
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
  }) async => const {'events': []};

  @override
  Future<Map<String, dynamic>> fetchMe({
    required String identityToken,
  }) async => const {'coins': 320, 'heldCoins': 0};
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
        raceId: 'race-done',
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TR-402/403: completed team race crowns the winning team',
      (tester) async {
    await _pump(tester, _CompletedTeamRaceApi());

    expect(find.text('WINNING TEAM'), findsOneWidget);
    expect(find.text('SWIFT CAPYS'), findsWidgets);
    // Never falls back to the individual "No winner" empty state just
    // because winnerUserId is null on a team race (TR-402).
    expect(find.text('No winner'), findsNothing);
  });

  testWidgets('TR-404: a tie shows the refund copy, not a winner',
      (tester) async {
    await _pump(tester, _CompletedTeamRaceApi(winnerTeam: null));

    expect(find.textContaining('It’s a tie — buy-ins refunded'), findsOneWidget);
    expect(find.text('No winner'), findsNothing);
  });

  testWidgets('TR-803: final standings stay grouped by team', (tester) async {
    await _pump(tester, _CompletedTeamRaceApi());

    expect(find.byKey(const Key('team-group-A')), findsOneWidget);
    expect(find.byKey(const Key('team-group-B')), findsOneWidget);
  });
}
