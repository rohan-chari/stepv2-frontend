import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/pill_button.dart';
import 'package:step_tracker/widgets/team_lobby_board.dart';

// TR-802 integration: the PENDING detail of a team race is the LoL-style
// lobby — slot taps join/switch sides, the Start lever gates on even teams
// (TR-301), and leaving the lobby is free while PENDING (TR-205).

class _TeamLobbyApi extends BackendApiService {
  _TeamLobbyApi({
    this.isCreator = true,
    this.myStatus = 'ACCEPTED',
    this.teamBMembers = const ['u2'],
    this.teamAMembers = const ['u1', 'u3'],
  });

  final bool isCreator;
  final String myStatus;
  final List<String> teamAMembers;
  final List<String> teamBMembers;

  String? switchedTo;
  String? acceptedWithTeam;
  bool leaveCalled = false;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async {
    Map<String, dynamic> member(String id, String team) => {
          'userId': id,
          'displayName': 'Racer $id',
          'status': 'ACCEPTED',
          'team': team,
          'accessories': const [],
        };
    return {
      'id': raceId,
      'name': 'Team Showdown',
      'status': 'PENDING',
      'isTeamRace': true,
      'teamSize': 2,
      'teamAName': 'Swift Capys',
      'teamBName': 'Turbo Beavers',
      'maxDurationDays': 7,
      'buyInAmount': 0,
      'payoutPreset': 'WINNER_TAKES_ALL',
      'potCoins': 0,
      'myStatus': myStatus,
      'isCreator': isCreator,
      'participants': [
        for (final id in teamAMembers) member(id, 'TEAM_A'),
        for (final id in teamBMembers) member(id, 'TEAM_B'),
        if (myStatus == 'INVITED')
          {
            'userId': 'user-1',
            'displayName': 'Trail Walker',
            'status': 'INVITED',
            'team': null,
          },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> setRaceTeam({
    required String identityToken,
    required String raceId,
    required String team,
  }) async {
    switchedTo = team;
    return {
      'participant': {'userId': 'user-1', 'team': team},
    };
  }

  @override
  Future<Map<String, dynamic>> acceptTeamRaceInvite({
    required String identityToken,
    required String raceId,
    required String team,
  }) async {
    acceptedWithTeam = team;
    return {
      'participant': {'userId': 'user-1', 'status': 'ACCEPTED', 'team': team},
    };
  }

  @override
  Future<Map<String, dynamic>> leaveRace({
    required String identityToken,
    required String raceId,
  }) async {
    leaveCalled = true;
    return const {'left': true};
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    return const {'coins': 320, 'heldCoins': 0};
  }
}

class _IndividualPendingApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async {
    return {
      'id': raceId,
      'name': 'Solo Pending',
      'status': 'PENDING',
      'maxDurationDays': 7,
      'buyInAmount': 0,
      'payoutPreset': 'WINNER_TAKES_ALL',
      'potCoins': 0,
      'myStatus': 'ACCEPTED',
      'isCreator': true,
      'participants': const [
        {'userId': 'user-1', 'displayName': 'Trail Walker', 'status': 'ACCEPTED'},
        {'userId': 'u2', 'displayName': 'Hill Climber', 'status': 'ACCEPTED'},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    return const {'coins': 320, 'heldCoins': 0};
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
        raceId: 'race-lobby',
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TR-802: PENDING team race shows the lobby board',
      (tester) async {
    // user-1 is on Team A with u3; u2 on Team B; one B peg open.
    await _pump(
      tester,
      _TeamLobbyApi(teamAMembers: const ['user-1', 'u3']),
    );

    expect(find.byType(TeamLobbyBoard), findsOneWidget);
    expect(find.text('VS'), findsOneWidget);
    expect(find.byKey(const Key('lobby-empty-B-1')), findsOneWidget);
  });

  testWidgets('TR-705: individual PENDING race keeps the classic layout',
      (tester) async {
    await _pump(tester, _IndividualPendingApi());
    expect(find.byType(TeamLobbyBoard), findsNothing);
    expect(find.text('PARTICIPANTS'), findsOneWidget);
  });

  testWidgets(
      'TR-301: uneven teams disable Start with live "Teams must be even" copy',
      (tester) async {
    await _pump(
      tester,
      _TeamLobbyApi(teamAMembers: const ['user-1', 'u3']),
    ); // 2v1

    final startFinder = find.widgetWithText(PillButton, 'START RACE');
    await tester.ensureVisible(startFinder);
    final button = tester.widget<PillButton>(startFinder);
    expect(button.onPressed, isNull);
    expect(find.textContaining('Teams must be even'), findsOneWidget);
    expect(find.textContaining('2v1'), findsOneWidget);
  });

  testWidgets('TR-301: even nonzero teams arm the Start lever',
      (tester) async {
    await _pump(
      tester,
      _TeamLobbyApi(
        teamAMembers: const ['user-1', 'u3'],
        teamBMembers: const ['u2', 'u4'],
      ),
    ); // 2v2

    final startFinder = find.widgetWithText(PillButton, 'START RACE');
    await tester.ensureVisible(startFinder);
    final button = tester.widget<PillButton>(startFinder);
    expect(button.onPressed, isNotNull);
    expect(find.textContaining('Teams must be even'), findsNothing);
  });

  testWidgets('TR-203: ACCEPTED member taps the other side to switch',
      (tester) async {
    final api = _TeamLobbyApi(teamAMembers: const ['user-1', 'u3']);
    await _pump(tester, api);

    await tester.ensureVisible(find.byKey(const Key('lobby-empty-B-1')));
    await tester.tap(find.byKey(const Key('lobby-empty-B-1')));
    await tester.pump();
    await tester.pump();

    expect(api.switchedTo, 'TEAM_B');
  });

  testWidgets('TR-201: INVITED member accepts by tapping a peg',
      (tester) async {
    final api = _TeamLobbyApi(
      isCreator: false,
      myStatus: 'INVITED',
      teamAMembers: const ['u3'],
      teamBMembers: const ['u2'],
    );
    await _pump(tester, api);

    await tester.ensureVisible(find.byKey(const Key('lobby-empty-A-1')));
    await tester.tap(find.byKey(const Key('lobby-empty-A-1')));
    await tester.pump();
    await tester.pump();

    expect(api.acceptedWithTeam, 'TEAM_A');
    expect(api.switchedTo, isNull);
  });

  testWidgets('TR-205/208: non-creator can leave the lobby; creator cannot',
      (tester) async {
    final api = _TeamLobbyApi(
      isCreator: false,
      teamAMembers: const ['user-1', 'u3'],
    );
    await _pump(tester, api);

    final leaveFinder = find.text('LEAVE LOBBY');
    await tester.ensureVisible(leaveFinder);
    await tester.tap(leaveFinder);
    await tester.pump();
    // Confirm dialog -> confirm.
    await tester.tap(find.text('LEAVE'));
    await tester.pump();
    await tester.pump();
    expect(api.leaveCalled, isTrue);
  });

  testWidgets('TR-208: creator sees no leave-lobby action', (tester) async {
    await _pump(
      tester,
      _TeamLobbyApi(teamAMembers: const ['user-1', 'u3']),
    );
    expect(find.text('LEAVE LOBBY'), findsNothing);
  });
}
