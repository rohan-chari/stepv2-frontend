import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _LeaveActionApi extends BackendApiService {
  _LeaveActionApi({
    required this.status,
    this.leaveAction,
    this.isCreator = false,
    this.isTeamRace = false,
    this.tournamentId,
    this.leaveCompleter,
    this.mySteps = 6200,
  });

  final String status;
  final String? leaveAction;
  final bool isCreator;
  final bool isTeamRace;
  final String? tournamentId;
  final Completer<Map<String, dynamic>>? leaveCompleter;
  final int mySteps;
  int leaveCalls = 0;
  int detailCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async {
    detailCalls++;
    return {
      'id': raceId,
      'name': 'Canyon Dash',
      'status': status,
      'maxDurationDays': 7,
      'myStatus': 'ACCEPTED',
      'isCreator': isCreator,
      if (status == 'ACTIVE') 'prizePool': const {'funded': true, 'coins': 120},
      if (isTeamRace) 'isTeamRace': true,
      if (leaveAction != null) 'leaveAction': leaveAction,
      if (tournamentId != null) 'tournamentId': tournamentId,
      'participants': const [
        {
          'userId': 'user-1',
          'displayName': 'Trail Walker',
          'status': 'ACCEPTED',
        },
        {
          'userId': 'user-2',
          'displayName': 'Hill Climber',
          'status': 'ACCEPTED',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async => {
    'status': status,
    'participants': [
      {
        'userId': 'user-1',
        'displayName': 'Trail Walker',
        'totalSteps': mySteps,
      },
      {'userId': 'user-2', 'displayName': 'Hill Climber', 'totalSteps': 5900},
    ],
    'powerupData': const {'enabled': false, 'inventory': []},
  };

  @override
  Future<Map<String, dynamic>> leaveRace({
    required String identityToken,
    required String raceId,
  }) {
    leaveCalls++;
    return leaveCompleter?.future ?? Future.value(const {'success': true});
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async =>
      const {'coins': 100, 'heldCoins': 0};
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Future<void> _pump(WidgetTester tester, BackendApiService api) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RaceDetailScreen(
        authService: await _auth(),
        raceId: 'race-leave',
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _openOptions(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_vert));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'pending stamped participant exits through the vertical options menu',
    (tester) async {
      final api = _LeaveActionApi(
        status: 'PENDING',
        leaveAction: 'LEAVE',
        isTeamRace: true,
      );
      await _pump(tester, api);

      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz), findsNothing);
      await _openOptions(tester);
      expect(find.text('LEAVE RACE'), findsOneWidget);
      expect(find.text('NOTIFICATIONS ON'), findsNothing);

      await tester.tap(find.text('LEAVE RACE').last);
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('LEAVE THE RACE?'), findsOneWidget);
      await tester.tap(find.text('LEAVE RACE').last);
      await tester.pump();
      expect(api.leaveCalls, 1);
    },
  );

  testWidgets(
    'active stamped participant relocates notifications and forfeits once',
    (tester) async {
      final completer = Completer<Map<String, dynamic>>();
      final api = _LeaveActionApi(
        status: 'ACTIVE',
        leaveAction: 'FORFEIT',
        leaveCompleter: completer,
      );
      await _pump(tester, api);

      expect(find.byIcon(Icons.notifications_active), findsNothing);
      await _openOptions(tester);
      expect(find.text('NOTIFICATIONS OFF'), findsOneWidget);
      expect(find.text('FORFEIT RACE'), findsOneWidget);
      await tester.tap(find.text('FORFEIT RACE').last);
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.textContaining('score freezes'), findsOneWidget);
      expect(
        find.textContaining('stays in the final prize pool'),
        findsOneWidget,
      );
      await tester.tap(find.text('FORFEIT RACE').last);
      await tester.pump();
      expect(api.leaveCalls, 1);

      completer.complete(const {'success': true, 'action': 'FORFEITED'});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(api.detailCalls, greaterThan(1));
    },
  );

  testWidgets('active zero-step forfeit explains projected-pool removal', (
    tester,
  ) async {
    await _pump(
      tester,
      _LeaveActionApi(status: 'ACTIVE', leaveAction: 'FORFEIT', mySteps: 0),
    );
    await _openOptions(tester);
    await tester.tap(find.text('FORFEIT RACE').last);
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      find.textContaining('removed from the projected prize pool'),
      findsOneWidget,
    );
  });

  testWidgets(
    'missing pending and tournament leaveAction states expose no menu',
    (tester) async {
      for (final api in [
        _LeaveActionApi(status: 'PENDING'),
        _LeaveActionApi(
          status: 'ACTIVE',
          leaveAction: 'FORFEIT',
          tournamentId: 'tournament-1',
        ),
      ]) {
        await _pump(tester, api);
        expect(find.byIcon(Icons.more_vert), findsNothing);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets(
    'malformed active leaveAction keeps only the relocated notification control',
    (tester) async {
      await _pump(
        tester,
        _LeaveActionApi(status: 'ACTIVE', leaveAction: 'leave'),
      );
      await _openOptions(tester);
      expect(find.text('NOTIFICATIONS OFF'), findsOneWidget);
      expect(find.text('FORFEIT RACE'), findsNothing);
    },
  );

  testWidgets(
    'creator gets management options but never a stamped exit action',
    (tester) async {
      await _pump(
        tester,
        _LeaveActionApi(
          status: 'PENDING',
          leaveAction: 'LEAVE',
          isCreator: true,
        ),
      );
      await _openOptions(tester);
      final sheet = find.byType(BottomSheet);
      expect(
        find.descendant(of: sheet, matching: find.text('INVITE FRIENDS')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('CANCEL RACE')),
        findsOneWidget,
      );
      expect(find.text('LEAVE RACE'), findsNothing);
    },
  );
}
