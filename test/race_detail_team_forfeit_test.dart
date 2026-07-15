import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// TR-601: mid-race forfeit is offered only inside an ACTIVE team race, and the
// confirmation dialog must state the team consequences explicitly: your steps
// freeze and STAY with the team, no refund, no rejoin.

class _ActiveTeamForfeitApi extends BackendApiService {
  _ActiveTeamForfeitApi({
    this.isTeamRace = true,
    this.status = 'ACTIVE',
    this.myForfeitedAt,
  });

  final bool isTeamRace;
  final String status;
  final String? myForfeitedAt;
  bool forfeitCalled = false;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async {
    return {
      'id': raceId,
      'name': 'Team Clash',
      'status': status,
      if (isTeamRace) ...{
        'isTeamRace': true,
        'teamSize': 2,
        'teamAName': 'Swift Capys',
        'teamBName': 'Turbo Beavers',
      },
      'maxDurationDays': 7,
      'buyInAmount': 30,
      'payoutPreset': 'WINNER_TAKES_ALL',
      'potCoins': 120,
      'myStatus': 'ACCEPTED',
      'isCreator': false,
      'powerupsEnabled': false,
      'endsAt': '2026-12-10T12:00:00.000Z',
      'participants': [
        {
          'userId': 'user-1',
          'displayName': 'Trail Walker',
          'status': 'ACCEPTED',
          if (isTeamRace) 'team': 'TEAM_A',
          'forfeitedAt': myForfeitedAt,
        },
        {
          'userId': 'u2',
          'displayName': 'Hill Climber',
          'status': 'ACCEPTED',
          if (isTeamRace) 'team': 'TEAM_B',
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
      'status': status,
      'participants': [
        {
          'userId': 'user-1',
          'displayName': 'Trail Walker',
          if (isTeamRace) 'team': 'TEAM_A',
          'totalSteps': 6200,
          'forfeitedAt': myForfeitedAt,
          'finishedAt': null,
        },
        {
          'userId': 'u2',
          'displayName': 'Hill Climber',
          if (isTeamRace) 'team': 'TEAM_B',
          'totalSteps': 5900,
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
  }) async => const {'events': []};

  @override
  Future<Map<String, dynamic>> forfeitRace({
    required String identityToken,
    required String raceId,
  }) async {
    forfeitCalled = true;
    return const {
      'participant': {'userId': 'user-1', 'forfeitedAt': '2026-07-15T12:00:00Z'},
    };
  }

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
  await tester.binding.setSurfaceSize(const Size(430, 932));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final authService = await _createAuthService();
  await tester.pumpWidget(
    MaterialApp(
      home: RaceDetailScreen(
        authService: authService,
        raceId: 'race-ff',
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// The course capys walk on an infinite loop, so pumpAndSettle never returns —
/// advance the dialog transition with timed pumps instead.
Future<void> _pumpDialog(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TR-601: ACTIVE team race offers forfeit', (tester) async {
    await _pump(tester, _ActiveTeamForfeitApi());
    expect(find.text('FORFEIT'), findsOneWidget);
  });

  testWidgets('TR-601: the dialog spells out the team consequences',
      (tester) async {
    final api = _ActiveTeamForfeitApi();
    await _pump(tester, api);

    await tester.ensureVisible(find.text('FORFEIT'));
    await tester.tap(find.text('FORFEIT'));
    await _pumpDialog(tester);

    // Steps stay with the team, no refund, no rejoin — all three stated.
    expect(find.textContaining('stay with'), findsOneWidget);
    expect(find.textContaining('No refund'), findsOneWidget);
    expect(find.textContaining("can't rejoin"), findsOneWidget);
    // Nothing happens until the user confirms.
    expect(api.forfeitCalled, isFalse);
  });

  testWidgets('TR-601: confirming calls forfeit', (tester) async {
    final api = _ActiveTeamForfeitApi();
    await _pump(tester, api);

    await tester.ensureVisible(find.text('FORFEIT'));
    await tester.tap(find.text('FORFEIT'));
    await _pumpDialog(tester);
    await tester.tap(find.text('FORFEIT ANYWAY'));
    await tester.pump();
    await tester.pump();

    expect(api.forfeitCalled, isTrue);
  });

  testWidgets('TR-601: backing out of the dialog does not forfeit',
      (tester) async {
    final api = _ActiveTeamForfeitApi();
    await _pump(tester, api);

    await tester.ensureVisible(find.text('FORFEIT'));
    await tester.tap(find.text('FORFEIT'));
    await _pumpDialog(tester);
    await tester.tap(find.text('KEEP RACING'));
    await _pumpDialog(tester);

    expect(api.forfeitCalled, isFalse);
  });

  testWidgets('TR-601: a member who already forfeited sees no forfeit action',
      (tester) async {
    await _pump(
      tester,
      _ActiveTeamForfeitApi(myForfeitedAt: '2026-07-15T10:00:00.000Z'),
    );
    expect(find.text('FORFEIT'), findsNothing);
  });

  testWidgets('TR-705: individual races have no forfeit action',
      (tester) async {
    await _pump(tester, _ActiveTeamForfeitApi(isTeamRace: false));
    expect(find.text('FORFEIT'), findsNothing);
  });
}
