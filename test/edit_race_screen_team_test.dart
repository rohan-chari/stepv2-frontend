import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/edit_race_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// TR-105: while PENDING, a team race's names and team size are editable.
// Shrinking below a filled side is rejected client-side (the server also
// answers TEAM_SIZE_TOO_SMALL). isTeamRace itself is immutable — there is no
// control for it.

class _RecordingApi extends BackendApiService {
  Map<String, dynamic>? lastUpdate;

  @override
  Future<Map<String, dynamic>> updateRace({
    required String identityToken,
    required String raceId,
    String? name,
    int? maxDurationDays,
    bool? isPublic,
    bool? powerupsEnabled,
    int? powerupStepInterval,
    int? buyInAmount,
    String? payoutPreset,
    int? maxParticipants,
    bool setMaxParticipantsUnlimited = false,
    String? teamAName,
    String? teamBName,
    int? teamSize,
  }) async {
    lastUpdate = {
      'name': name,
      'teamAName': teamAName,
      'teamBName': teamBName,
      'teamSize': teamSize,
    };
    return {
      'race': {'id': raceId},
    };
  }
}

Map<String, dynamic> _teamRace({int teamSize = 3}) => {
      'id': 'race-1',
      'name': 'Team Clash',
      'status': 'PENDING',
      'isTeamRace': true,
      'teamSize': teamSize,
      'teamAName': 'Swift Capys',
      'teamBName': 'Turbo Beavers',
      'maxDurationDays': 7,
      'buyInAmount': 0,
      'payoutPreset': 'WINNER_TAKES_ALL',
      'isPublic': false,
      'maxParticipants': teamSize * 2,
      'participants': const [
        {'userId': 'u1', 'status': 'ACCEPTED', 'team': 'TEAM_A'},
        {'userId': 'u2', 'status': 'ACCEPTED', 'team': 'TEAM_A'},
        {'userId': 'u3', 'status': 'ACCEPTED', 'team': 'TEAM_B'},
      ],
    };

Future<AuthService> _authService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

Future<void> _pump(
  WidgetTester tester,
  _RecordingApi api, {
  Map<String, dynamic>? race,
}) async {
  final authService = await _authService();
  await tester.pumpWidget(
    MaterialApp(
      home: EditRaceScreen(
        authService: authService,
        backendApiService: api,
        raceId: 'race-1',
        race: race ?? _teamRace(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TR-105: team plaques and size stepper show for a team race',
      (tester) async {
    await _pump(tester, _RecordingApi());

    expect(find.byKey(const Key('edit-team-plaque-a')), findsOneWidget);
    expect(find.byKey(const Key('edit-team-plaque-b')), findsOneWidget);
    expect(find.byKey(const Key('edit-team-size-stepper')), findsOneWidget);
    expect(find.text('3v3'), findsOneWidget);
    // MAX RUNNERS is derived for team races — not editable.
    expect(find.text('MAX RUNNERS'), findsNothing);
  });

  testWidgets('TR-705: individual race edit is unchanged', (tester) async {
    final race = _teamRace()
      ..remove('isTeamRace')
      ..remove('teamSize');
    await _pump(tester, _RecordingApi(), race: race);

    expect(find.byKey(const Key('edit-team-plaque-a')), findsNothing);
    expect(find.byKey(const Key('edit-team-size-stepper')), findsNothing);
    expect(find.text('MAX RUNNERS'), findsOneWidget);
  });

  testWidgets('TR-105: renaming a team PATCHes the new names', (tester) async {
    final api = _RecordingApi();
    await _pump(tester, api);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('edit-team-plaque-a')),
        matching: find.byType(TextField),
      ),
      'Mossy Rockets',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('SAVE CHANGES'));
    await tester.tap(find.text('SAVE CHANGES'));
    await tester.pump();
    await tester.pump();

    expect(api.lastUpdate, isNotNull);
    expect(api.lastUpdate!['teamAName'], 'Mossy Rockets');
    expect(api.lastUpdate!['teamBName'], isNull); // unchanged -> omitted
  });

  testWidgets('TR-105: shrinking below a filled side is rejected client-side',
      (tester) async {
    final api = _RecordingApi();
    await _pump(tester, api); // Team A has 2 members, size 3

    // 3 -> 1, below Team A's 2 accepted members.
    await tester.tap(find.byKey(const Key('edit-team-size-minus')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('edit-team-size-minus')));
    await tester.pump();
    expect(find.text('1v1'), findsOneWidget);

    await tester.ensureVisible(find.text('SAVE CHANGES'));
    await tester.tap(find.text('SAVE CHANGES'));
    await tester.pump();

    expect(api.lastUpdate, isNull);
    expect(
      find.text("Can't shrink below a side that's already filled."),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('TR-105: growing the team size PATCHes it', (tester) async {
    final api = _RecordingApi();
    await _pump(tester, api);

    await tester.tap(find.byKey(const Key('edit-team-size-plus')));
    await tester.pump();
    expect(find.text('4v4'), findsOneWidget);

    await tester.ensureVisible(find.text('SAVE CHANGES'));
    await tester.tap(find.text('SAVE CHANGES'));
    await tester.pump();

    expect(api.lastUpdate!['teamSize'], 4);
  });
}
