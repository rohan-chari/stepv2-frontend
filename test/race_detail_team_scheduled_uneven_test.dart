import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// TR-304: when a scheduled team race's start time passes with uneven teams the
// cron skips it and the race stays PENDING (retrying each tick). The lobby has
// to explain that rather than sit there looking broken behind a countdown that
// already hit zero.

class _ScheduledTeamApi extends BackendApiService {
  _ScheduledTeamApi({
    required this.scheduledStartAt,
    this.teamBMembers = const ['b1'],
  });

  final String? scheduledStartAt;
  final List<String> teamBMembers;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async {
    return {
      'id': raceId,
      'name': 'Scheduled Team Race',
      'status': 'PENDING',
      'isTeamRace': true,
      'teamSize': 2,
      'teamAName': 'Swift Capys',
      'teamBName': 'Turbo Beavers',
      'maxDurationDays': 7,
      'buyInAmount': 0,
      'payoutPreset': 'WINNER_TAKES_ALL',
      'potCoins': 0,
      'myStatus': 'ACCEPTED',
      'isCreator': true,
      if (scheduledStartAt != null) 'scheduledStartAt': scheduledStartAt,
      'participants': [
        {
          'userId': 'user-1',
          'displayName': 'Trail Walker',
          'status': 'ACCEPTED',
          'team': 'TEAM_A',
        },
        {
          'userId': 'a2',
          'displayName': 'Ally Two',
          'status': 'ACCEPTED',
          'team': 'TEAM_A',
        },
        for (final id in teamBMembers)
          {
            'userId': id,
            'displayName': 'Rival $id',
            'status': 'ACCEPTED',
            'team': 'TEAM_B',
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
        raceId: 'race-sched-team',
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TR-304: a passed scheduled start with uneven teams explains '
      'the skip', (tester) async {
    // Start time already elapsed, teams 2v1 -> cron skipped it.
    await _pump(
      tester,
      _ScheduledTeamApi(
        scheduledStartAt: DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 30))
            .toIso8601String(),
      ),
    );

    expect(find.byKey(const Key('team-scheduled-uneven-banner')), findsOneWidget);
    expect(
      find.textContaining('WAITING FOR EVEN TEAMS'),
      findsOneWidget,
    );
    // Names the live imbalance so the creator knows what to fix.
    expect(find.textContaining('2v1'), findsWidgets);
  });

  testWidgets('TR-304: even teams past the start time show no skip banner',
      (tester) async {
    await _pump(
      tester,
      _ScheduledTeamApi(
        scheduledStartAt: DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 30))
            .toIso8601String(),
        teamBMembers: const ['b1', 'b2'],
      ),
    );

    expect(find.byKey(const Key('team-scheduled-uneven-banner')), findsNothing);
  });

  testWidgets('TR-304: a future scheduled start shows no skip banner',
      (tester) async {
    await _pump(
      tester,
      _ScheduledTeamApi(
        scheduledStartAt: DateTime.now()
            .toUtc()
            .add(const Duration(days: 2))
            .toIso8601String(),
      ),
    );

    expect(find.byKey(const Key('team-scheduled-uneven-banner')), findsNothing);
  });

  testWidgets('TR-304: an unscheduled uneven team race shows no skip banner',
      (tester) async {
    await _pump(tester, _ScheduledTeamApi(scheduledStartAt: null));
    expect(find.byKey(const Key('team-scheduled-uneven-banner')), findsNothing);
  });
}
