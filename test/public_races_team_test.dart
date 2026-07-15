import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/public_races_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// TR-206/TR-808: public-browser cards for team races show format + slots
// ("2v2 · 1 slot left on Blue"), and joining prompts a side pick that rides
// the join call (TR-201).

class _PublicTeamRacesApi extends BackendApiService {
  _PublicTeamRacesApi({this.races = const []});

  final List<Map<String, dynamic>> races;
  String? joinedTeam;
  String? joinedRaceId;
  bool plainJoinCalled = false;

  @override
  Future<List<Map<String, dynamic>>> fetchPublicRaces({
    required String identityToken,
  }) async {
    return races;
  }

  @override
  Future<Map<String, dynamic>> joinPublicRace({
    required String identityToken,
    required String raceId,
    bool onboarding = false,
  }) async {
    plainJoinCalled = true;
    return const {'joined': true};
  }

  @override
  Future<Map<String, dynamic>> joinPublicRaceOnTeam({
    required String identityToken,
    required String raceId,
    required String team,
    bool onboarding = false,
  }) async {
    joinedRaceId = raceId;
    joinedTeam = team;
    return const {'joined': true};
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    return const {'coins': 320, 'heldCoins': 0};
  }
}

Map<String, dynamic> _teamRace() => {
      'id': 'race-public-team',
      'name': 'Open Team Brawl',
      'status': 'PENDING',
      'isTeamRace': true,
      'teamSize': 2,
      'teamAName': 'Red',
      'teamBName': 'Blue',
      'maxDurationDays': 7,
      'participantCount': 3,
      'maxParticipants': 4,
      'buyInAmount': 0,
      'creator': {'displayName': 'RaceMaker'},
      'teams': {
        'teamA': {'memberCount': 2},
        'teamB': {'memberCount': 1},
      },
    };

Future<AuthService> _createAuthService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_coins': 320,
    'auth_held_coins': 0,
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

Future<void> _pump(WidgetTester tester, _PublicTeamRacesApi api) async {
  final authService = await _createAuthService();
  await tester.pumpWidget(
    MaterialApp(
      home: PublicRacesScreen(
        authService: authService,
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TR-206: team race card shows the format + slots line',
      (tester) async {
    await _pump(tester, _PublicTeamRacesApi(races: [_teamRace()]));
    expect(find.text('2v2 · 1 slot left on Blue'), findsOneWidget);
  });

  testWidgets('TR-201: JOIN opens the side picker and joins the tapped side',
      (tester) async {
    final api = _PublicTeamRacesApi(races: [_teamRace()]);
    await _pump(tester, api);

    await tester.tap(find.text('JOIN'));
    await tester.pumpAndSettle();

    // Side sheet shows both teams; Blue has the open peg.
    expect(find.byKey(const Key('side-pick-B')), findsOneWidget);
    await tester.tap(find.byKey(const Key('side-pick-B')));
    await tester.pump();
    await tester.pump();

    expect(api.joinedTeam, 'TEAM_B');
    expect(api.joinedRaceId, 'race-public-team');
    expect(api.plainJoinCalled, isFalse);
  });

  testWidgets('TR-202: a full side is disabled in the picker', (tester) async {
    final api = _PublicTeamRacesApi(races: [_teamRace()]);
    await _pump(tester, api);

    await tester.tap(find.text('JOIN'));
    await tester.pumpAndSettle();

    // Red (Team A) is full 2/2 — tapping it must not fire a join.
    await tester.tap(find.byKey(const Key('side-pick-A')));
    await tester.pump();
    expect(api.joinedTeam, isNull);
  });

  testWidgets('TR-705: individual public race joins directly, no picker',
      (tester) async {
    final race = _teamRace()
      ..remove('isTeamRace')
      ..remove('teams')
      ..remove('teamSize');
    final api = _PublicTeamRacesApi(races: [race]);
    await _pump(tester, api);

    await tester.tap(find.text('JOIN'));
    await tester.pump();
    await tester.pump();

    expect(api.plainJoinCalled, isTrue);
    expect(api.joinedTeam, isNull);
  });
}
