import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/home_race_suggestion.dart';
import 'package:step_tracker/models/loadable.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/screens/tabs/home_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';

class _FakeBackendApiService extends BackendApiService {}

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

HomeRaceSuggestion _suggestion({required bool team}) =>
    HomeRaceSuggestion.tryParse({
      'kind': 'PUBLIC_RACE',
      'id': 'race-1',
      'name': team ? 'Team Clash' : 'Solo Sprint',
      'status': 'PENDING',
      'maxDurationDays': 3,
      'endsAt': null,
      'startedAt': null,
      'participantCount': team ? 3 : 4,
      'maxParticipants': team ? 4 : 10,
      'buyInAmount': 0,
      'payoutPreset': null,
      'powerupsEnabled': true,
      'prizePool': null,
      'isTeamRace': team,
      'teamSize': team ? 2 : null,
      'teamAName': team ? 'Swift Capys' : null,
      'teamBName': team ? 'Turbo Beavers' : null,
      'teams': team
          ? {
              'teamA': {'memberCount': 2},
              'teamB': {'memberCount': 1},
            }
          : null,
      'joinAction': 'JOIN',
    })!;

Future<void> _pump(
  WidgetTester tester,
  HomeRaceSuggestion suggestion, {
  ThemeData? theme,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final authService = await _createAuthService();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
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
          suggestedRacesState: Loadable.success([suggestion]),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
  await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TR-809: team suggestion keeps compact format and slots', (
    tester,
  ) async {
    await _pump(tester, _suggestion(team: true));

    expect(find.textContaining('2v2 TEAMS'), findsOneWidget);
    expect(find.textContaining('1 SLOT'), findsOneWidget);
    expect(find.text('TEAM CLASH'), findsOneWidget);
  });

  testWidgets('TR-809: team suggestion preserves both side names in payload', (
    tester,
  ) async {
    final suggestion = _suggestion(team: true);
    await _pump(tester, suggestion);

    expect(suggestion.teamAName, 'Swift Capys');
    expect(suggestion.teamBName, 'Turbo Beavers');
    expect(find.text('PUBLIC'), findsOneWidget);
  });

  testWidgets('TR-705: individual suggestion has no team badge', (
    tester,
  ) async {
    await _pump(tester, _suggestion(team: false));

    expect(find.textContaining('TEAMS'), findsNothing);
    expect(find.textContaining('SLOT'), findsNothing);
    expect(find.text('SOLO SPRINT'), findsOneWidget);
  });

  testWidgets('public-race action stays visible in dark mode', (tester) async {
    await _pump(tester, _suggestion(team: false), theme: AppThemeData.night());

    final join = tester.widget<Text>(find.text('JOIN'));
    expect(join.style?.color, isNot(equals(Colors.transparent)));
  });
}
