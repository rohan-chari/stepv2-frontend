import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/screens/tabs/home_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/utils/team_race.dart';
import 'package:step_tracker/widgets/race_ui.dart';
import 'package:step_tracker/widgets/team_scoreline.dart';

class _FakeBackendApiService extends BackendApiService {}

// TR-809: the Home current-race area is team-aware — team format chip, capys
// ringed in their team color (matching the TR-804 glow), and the compact
// rope-knot scoreline where individual race info shows today. Individual
// races render exactly as before (TR-705).

Future<AuthService> _createAuthService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_coins': 125,
    'auth_held_coins': 0,
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

Map<String, dynamic> _raceCard({required bool team}) => {
      'state': 'ACTIVE_RACES',
      'data': {
        'races': [
          {
            'raceId': 'race-1',
            'name': team ? 'Team Clash' : 'Solo Sprint',
            'endsAt': DateTime.now()
                .add(const Duration(days: 2))
                .toUtc()
                .toIso8601String(),
            'userPlacement': 2,
            'participantCount': 4,
            if (team) ...{
              'isTeamRace': true,
              'teamSize': 2,
              'teamAName': 'Swift Capys',
              'teamBName': 'Turbo Beavers',
              'teams': {
                'teamA': {'totalSteps': 12340, 'memberCount': 2},
                'teamB': {'totalSteps': 11900, 'memberCount': 2},
              },
            },
            'top3': [
              {
                'rank': 1,
                'displayName': 'Trail Walker',
                'totalSteps': 6200,
                if (team) 'team': 'TEAM_A',
              },
              {
                'rank': 2,
                'displayName': 'Sneaky Pete',
                'totalSteps': 6000,
                if (team) 'team': 'TEAM_B',
              },
            ],
          },
        ],
      },
    };

Future<void> _pump(WidgetTester tester, Map<String, dynamic> raceCard) async {
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final authService = await _createAuthService();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: HomeTab(
          stepData: StepData(steps: 2400, date: DateTime(2026, 6, 5)),
          isLoading: false,
          error: null,
          healthAuthorized: true,
          notificationsState: true,
          displayName: 'Trail Walker',
          authService: authService,
          backendApiService: _FakeBackendApiService(),
          onRefresh: () async {},
          onEnableHealth: () {},
          onEnableNotifications: () {},
          onDisplayNameChanged: () {},
          friendsSteps: const [],
          raceCard: raceCard,
        ),
      ),
    ),
  );
  await tester.pump();

  // The race rail sits below the hero — bring it on screen.
  await tester.dragUntilVisible(
    find.byType(RacerAvatar).first,
    find.byType(Scrollable).first,
    const Offset(0, -200),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TR-809: team race ticket shows the compact scoreline',
      (tester) async {
    await _pump(tester, _raceCard(team: true));

    expect(find.byType(TeamScoreline), findsOneWidget);
    expect(find.textContaining('12,340'), findsOneWidget);
    expect(find.textContaining('11,900'), findsOneWidget);
    expect(find.text('2v2'), findsOneWidget);
  });

  testWidgets('TR-809: ticket capys are ringed in their team color',
      (tester) async {
    await _pump(tester, _raceCard(team: true));

    final avatars =
        tester.widgetList<RacerAvatar>(find.byType(RacerAvatar)).toList();
    expect(
      avatars.map((a) => a.ringColor),
      containsAll([
        TeamRace.color(RaceTeam.teamA),
        TeamRace.color(RaceTeam.teamB),
      ]),
    );
  });

  testWidgets('TR-705: individual ticket renders as before', (tester) async {
    await _pump(tester, _raceCard(team: false));

    expect(find.byType(TeamScoreline), findsNothing);
    expect(find.text('2v2'), findsNothing);
    final avatars =
        tester.widgetList<RacerAvatar>(find.byType(RacerAvatar)).toList();
    expect(avatars.every((a) => a.ringColor == null), isTrue);
  });
}
