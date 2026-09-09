import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/team_lobby_board.dart';

import 'package:package_info_plus/package_info_plus.dart';
import 'support/large_team_fixture.dart';

class _PrivateLargeTeamApi extends LargeTeamFixtureApi {
  _PrivateLargeTeamApi() : super(status: 'ACTIVE');
  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async {
    final progress = await super.fetchRaceProgress(
      identityToken: identityToken,
      raceId: raceId,
    );
    return {
      ...progress,
      'participants': [
        for (final member in roster)
          member['userId'] == 'B9'
              ? {
                  ...member,
                  'displayName': '???',
                  'stealthed': true,
                  'totalSteps': null,
                  'accessories': null,
                }
              : member,
      ],
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
        raceId: 'race-lobby',
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'test',
      version: '2.3.13',
      buildNumber: '1',
      buildSignature: '',
    );
  });
  testWidgets(
    'pending uses complete accepted roster independently of the 15-row page',
    (tester) async {
      await _pump(tester, LargeTeamFixtureApi());
      final board = tester.widget<TeamLobbyBoard>(find.byType(TeamLobbyBoard));
      expect(board.participants.length, 20);
      expect(board.participants.last['userId'], 'B9');
      expect(find.text('10/10'), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('old-server pending fallback requests full team progress', (
    tester,
  ) async {
    await _pump(tester, LargeTeamFixtureApi(complete: false));
    await tester.pump();
    final board = tester.widget<TeamLobbyBoard>(find.byType(TeamLobbyBoard));
    expect(board.participants.length, 20);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'missing completeness never turns a partial page into empty lobby slots',
    (tester) async {
      await _pump(
        tester,
        LargeTeamFixtureApi(complete: false, partialProgress: true),
      );
      expect(find.byKey(const Key('team-roster-unavailable')), findsOneWidget);
      expect(find.byType(TeamLobbyBoard), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final status in ['ACTIVE', 'COMPLETED']) {
    testWidgets('$status has a five-row viewport with all twenty members', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pump(tester, LargeTeamFixtureApi(status: status));
      await tester.pump(const Duration(milliseconds: 100));
      final side = find.byKey(
        Key(
          status == 'ACTIVE'
              ? 'team-roster-scroll-TEAM_B'
              : 'team-final-scroll-TEAM_B',
        ),
      );
      final last = find.byKey(
        Key(status == 'ACTIVE' ? 'team-cell-B9' : 'team-final-B9'),
      );
      await tester.ensureVisible(side);
      await tester.pump();
      expect(last.hitTestable(), findsNothing);
      await tester.drag(side, const Offset(0, -650));
      await tester.pump(const Duration(seconds: 1));
      expect(last.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'failed active progress never reveals details identities or cosmetics',
    (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pump(
        tester,
        LargeTeamFixtureApi(status: 'ACTIVE', partialProgress: true),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final board = tester.widget<TeamLobbyBoard>(find.byType(TeamLobbyBoard));
      expect(board.participants.length, 20);
      expect(
        board.participants.every((row) => row['displayName'] == '???'),
        isTrue,
      );
      expect(find.textContaining('A racer'), findsNothing);
      expect(find.textContaining('B racer'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'full progress privacy masks remain authoritative over accepted roster',
    (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pump(tester, _PrivateLargeTeamApi());
      await tester.pump(const Duration(milliseconds: 100));
      final side = find.byKey(const Key('team-roster-scroll-TEAM_B'));
      await tester.ensureVisible(side);
      await tester.drag(side, const Offset(0, -650));
      await tester.pump(const Duration(seconds: 1));
      await tester.ensureVisible(find.byKey(const Key('team-cell-B9')));
      await tester.pump();
      expect(find.textContaining('B racer 9'), findsNothing);
      expect(find.byKey(const Key('team-standings-profile-B9')), findsNothing);
      expect(
        find.byKey(const Key('team-cell-B9')).hitTestable(),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'partial progress keeps all accepted members accessible without invented scores',
    (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pump(
        tester,
        LargeTeamFixtureApi(status: 'ACTIVE', partialProgress: true),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final board = tester.widget<TeamLobbyBoard>(find.byType(TeamLobbyBoard));
      expect(board.participants.length, 20);
      expect(
        find.byKey(const Key('race-detail-progress-error')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
