import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tournament_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// Batch 2026-08-15 item 4: leaving/forfeiting a tournament moved from inline
// PillButtons in the action bar into a kebab (`Icons.more_vert`) bottom sheet
// on the hand-built header, matching `race_detail_screen.dart`. Presentation
// only — the same `_leave()`/`_forfeit()` paths, the same forfeit confirmation
// copy, and the same `NO_LIVE_MATCHUP` error mapping as before.

class _FakeApi extends BackendApiService {
  _FakeApi(this.payload, {this.forfeitError});

  final Map<String, dynamic> payload;
  final ApiException? forfeitError;

  int leaveCalls = 0;
  int forfeitCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchTournament({
    required String identityToken,
    required String tournamentId,
  }) async {
    return {'tournament': payload};
  }

  @override
  Future<Map<String, dynamic>> leaveTournament({
    required String identityToken,
    required String tournamentId,
  }) async {
    leaveCalls += 1;
    return const {
      'contract': 'tournament-action-v1',
      'wallet': {'coins': 500, 'heldCoins': 0},
    };
  }

  @override
  Future<Map<String, dynamic>> forfeitTournament({
    required String identityToken,
    required String tournamentId,
  }) async {
    forfeitCalls += 1;
    final err = forfeitError;
    if (err != null) throw err;
    return const {'contract': 'tournament-action-v1'};
  }
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'me',
    'auth_display_name': 'Me',
    'auth_coins': 500,
    'auth_held_coins': 0,
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

/// Pushes the screen onto a route below it so the `_leave()` success path can
/// `pop()` back the way it does in the app (the action bar lives on a pushed
/// route in every real entry point).
Future<_FakeApi> _pump(
  WidgetTester tester,
  Map<String, dynamic> payload, {
  ApiException? forfeitError,
}) async {
  final auth = await _auth();
  final api = _FakeApi(payload, forfeitError: forfeitError);
  final navKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navKey,
      home: const Scaffold(body: SizedBox.shrink()),
    ),
  );
  navKey.currentState!.push(
    MaterialPageRoute(
      builder: (_) => TournamentDetailScreen(
        authService: auth,
        tournamentId: 't1',
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400)); // route transition
  await tester.pump(); // fetch future
  return api;
}

/// Disposes the screen so its poll/countdown timers are cancelled before the
/// binding asserts no pending timers.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
}

Future<void> _openKebab(WidgetTester tester) async {
  expect(find.byIcon(Icons.more_vert), findsOneWidget);
  await tester.tap(find.byIcon(Icons.more_vert));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400)); // sheet animation
}

Map<String, dynamic> _pendingPayload({required String creatorId}) => {
  'id': 't1',
  'name': 'Lobby Bracket',
  'status': 'PENDING',
  'bracketSize': 4,
  'matchupDurationDays': 1,
  'creatorId': creatorId,
  'acceptedCount': 4,
  'myStatus': 'ACCEPTED',
  'participants': const [
    {'userId': 'me', 'displayName': 'Me', 'status': 'ACCEPTED'},
    {'userId': 'u2', 'displayName': 'Bob', 'status': 'ACCEPTED'},
    {'userId': 'u3', 'displayName': 'Cal', 'status': 'ACCEPTED'},
    {'userId': 'u4', 'displayName': 'Dee', 'status': 'ACCEPTED'},
  ],
  'rounds': const [],
};

Map<String, dynamic> _activePayload({required bool liveMatchup}) => {
  'id': 't1',
  'name': 'Gauntlet',
  'status': 'ACTIVE',
  'bracketSize': 4,
  'matchupDurationDays': 1,
  'currentRound': 1,
  'totalRounds': 2,
  'creatorId': 'someone-else',
  'myStatus': 'ACCEPTED',
  'participants': [
    {
      'userId': 'me',
      'displayName': 'Me',
      'status': 'ACCEPTED',
      if (!liveMatchup) 'eliminatedInRound': 1,
    },
    {'userId': 'u2', 'displayName': 'Bob', 'status': 'ACCEPTED'},
  ],
  'rounds': [
    {
      'round': 1,
      'label': 'SEMIFINALS',
      'matchups': [
        {
          'matchIndex': 0,
          'raceId': 'r1',
          'status': liveMatchup ? 'ACTIVE' : 'COMPLETED',
          'players': [
            {'userId': 'me', 'totalSteps': 100, 'forfeited': false},
            {'userId': 'u2', 'totalSteps': 90, 'forfeited': false},
          ],
          'winnerUserId': liveMatchup ? null : 'u2',
        },
      ],
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('participant PENDING: kebab LEAVE calls leaveTournament', (
    tester,
  ) async {
    final api = await _pump(tester, _pendingPayload(creatorId: 'someone-else'));

    // The inline action-bar LEAVE button is gone; SHARE LINK stays.
    expect(find.text('LEAVE'), findsNothing);
    expect(find.text('SHARE LINK'), findsOneWidget);

    await _openKebab(tester);
    expect(find.text('TOURNAMENT OPTIONS'), findsOneWidget);
    expect(find.text('LEAVE TOURNAMENT'), findsOneWidget);
    expect(find.text('FORFEIT MATCHUP'), findsNothing);

    await tester.tap(find.text('LEAVE TOURNAMENT'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // sheet + dialog

    // LEAVE now confirms first, matching FORFEIT/CANCEL/JOIN on this screen.
    expect(find.text('LEAVE THE TOURNAMENT?'), findsOneWidget);
    expect(find.textContaining('Your buy-in is refunded'), findsOneWidget);
    expect(api.leaveCalls, 0);

    await tester.tap(find.text('LEAVE'));
    await tester.pump();
    await tester.pump();

    expect(api.leaveCalls, 1);
    await _teardown(tester);
  });

  testWidgets(
    'ACTIVE with a live matchup: kebab FORFEIT confirms, then forfeits',
    (tester) async {
      final api = await _pump(tester, _activePayload(liveMatchup: true));

      // GO TO MY MATCHUP survives as the only action-bar button.
      expect(find.text('GO TO MY MATCHUP'), findsOneWidget);
      expect(find.text('FORFEIT'), findsNothing);

      await _openKebab(tester);
      expect(find.text('FORFEIT MATCHUP'), findsOneWidget);
      expect(find.text('LEAVE TOURNAMENT'), findsNothing);

      await tester.tap(find.text('FORFEIT MATCHUP'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400)); // sheet + dialog

      // The pre-existing confirmation copy, unchanged by the relocation.
      expect(find.text('FORFEIT YOUR MATCHUP?'), findsOneWidget);
      expect(find.textContaining('No refunds.'), findsOneWidget);
      expect(api.forfeitCalls, 0);

      await tester.tap(find.text('FORFEIT'));
      await tester.pump();
      await tester.pump();

      expect(api.forfeitCalls, 1);
      await _teardown(tester);
    },
  );

  testWidgets('a 409 NO_LIVE_MATCHUP forfeit surfaces friendly copy', (
    tester,
  ) async {
    // The matchup can complete between render and tap. The relocated trigger
    // must still route the coded error through `tournamentErrorCopy`.
    final api = await _pump(
      tester,
      _activePayload(liveMatchup: true),
      forfeitError: const ApiException(
        'Conflict',
        statusCode: 409,
        code: 'NO_LIVE_MATCHUP',
      ),
    );

    await _openKebab(tester);
    await tester.tap(find.text('FORFEIT MATCHUP'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('FORFEIT'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // toast animation

    expect(api.forfeitCalls, 1);
    expect(
      find.textContaining("don't have a live matchup"),
      findsOneWidget,
      reason: 'raw 409 must not reach the user',
    );
    await _teardown(tester);
  });

  testWidgets('creator PENDING gets no kebab (server blocks creator leave)', (
    tester,
  ) async {
    await _pump(tester, _pendingPayload(creatorId: 'me'));

    expect(find.text('START TOURNAMENT'), findsOneWidget);
    expect(find.text('CANCEL'), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsNothing);
    expect(find.text('LEAVE TOURNAMENT'), findsNothing);
    await _teardown(tester);
  });

  testWidgets('ACTIVE eliminated viewer has no forfeit action', (tester) async {
    await _pump(tester, _activePayload(liveMatchup: false));

    expect(find.byIcon(Icons.more_vert), findsNothing);
    expect(find.text('FORFEIT'), findsNothing);
    expect(find.text('FORFEIT MATCHUP'), findsNothing);
    expect(find.textContaining("You're out."), findsOneWidget);
    await _teardown(tester);
  });

  testWidgets('invited PENDING viewer is untouched: no kebab, DECLINE/ACCEPT', (
    tester,
  ) async {
    final payload = _pendingPayload(creatorId: 'someone-else');
    payload['myStatus'] = 'INVITED';
    await _pump(tester, payload);

    expect(find.text('DECLINE'), findsOneWidget);
    expect(find.text('ACCEPT'), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsNothing);
    await _teardown(tester);
  });
}
