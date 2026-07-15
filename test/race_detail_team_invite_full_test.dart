import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// TR-207: over-inviting is allowed — the first to accept get in. A surplus
// invitee (both sides at cap) keeps their invite visible in a "race full"
// state; it becomes acceptable again the moment a slot frees (TR-205).

class _FullTeamInviteApi extends BackendApiService {
  _FullTeamInviteApi({this.teamBFull = true});

  final bool teamBFull;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async {
    return {
      'id': raceId,
      'name': 'Team Clash',
      'status': 'PENDING',
      'isTeamRace': true,
      'teamSize': 1,
      'teamAName': 'Swift Capys',
      'teamBName': 'Turbo Beavers',
      'maxDurationDays': 7,
      'buyInAmount': 0,
      'payoutPreset': 'WINNER_TAKES_ALL',
      'potCoins': 0,
      // I'm a surplus invitee — I haven't picked a side.
      'myStatus': 'INVITED',
      'isCreator': false,
      'participants': [
        {
          'userId': 'a1',
          'displayName': 'Alpha',
          'status': 'ACCEPTED',
          'team': 'TEAM_A',
        },
        if (teamBFull)
          {
            'userId': 'b1',
            'displayName': 'Bravo',
            'status': 'ACCEPTED',
            'team': 'TEAM_B',
          },
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
        raceId: 'race-full',
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TR-207: a surplus invitee sees a race-full state, not an '
      'accept prompt', (tester) async {
    await _pump(tester, _FullTeamInviteApi());

    // Both sides at cap -> no empty pegs at all, and the join hint is
    // replaced by the race-full explainer. The invite stays visible.
    expect(find.byKey(const Key('lobby-empty-A-0')), findsNothing);
    expect(find.byKey(const Key('lobby-empty-B-0')), findsNothing);
    expect(find.byKey(const Key('team-lobby-race-full')), findsOneWidget);
    expect(
      find.textContaining('Both teams are full'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Tap an empty peg to pick your side'),
      findsNothing,
    );
    // Declining is still possible — the invite is not silently dropped.
    expect(find.text('DECLINE INVITE'), findsOneWidget);
  });

  testWidgets('TR-207/205: the invite becomes acceptable again once a slot '
      'frees', (tester) async {
    await _pump(tester, _FullTeamInviteApi(teamBFull: false));

    expect(find.byKey(const Key('team-lobby-race-full')), findsNothing);
    expect(find.byKey(const Key('lobby-empty-B-0')), findsOneWidget);
    expect(
      find.textContaining('Tap an empty peg to pick your side'),
      findsOneWidget,
    );
  });
}
