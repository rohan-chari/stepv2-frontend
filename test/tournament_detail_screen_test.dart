import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tournament_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/celebration_confetti.dart';
import 'package:step_tracker/widgets/tournament_bracket_board.dart';

// The tournament view is a draggable March-Madness bracket on the checkered
// grid ([TournamentBracketBoard]): PENDING shows the skeleton with a join-order
// preview (OPEN leaf slots), ACTIVE draws round labels + TBD placeholders for
// undrawn rounds with MY matchup tappable, COMPLETED crowns the champion —
// CelebrationConfetti ONLY when the viewer is the champion.

class _FakeApi extends BackendApiService {
  _FakeApi(this.payload);
  final Map<String, dynamic> payload;

  @override
  Future<Map<String, dynamic>> fetchTournament({
    required String identityToken,
    required String tournamentId,
  }) async =>
      {'tournament': payload};
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

Future<void> _pump(WidgetTester tester, Map<String, dynamic> payload) async {
  final auth = await _auth();
  await tester.pumpWidget(
    MaterialApp(
      home: TournamentDetailScreen(
        authService: auth,
        tournamentId: 't1',
        backendApiService: _FakeApi(payload),
      ),
    ),
  );
  await tester.pump(); // fetch future
  await tester.pump();
}

/// Disposes the screen so its poll/countdown/confetti timers are cancelled
/// before the test binding asserts no pending timers.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PENDING renders the bracket board with OPEN leaf slots',
      (tester) async {
    await _pump(tester, {
      'id': 't1',
      'name': 'Lobby Bracket',
      'status': 'PENDING',
      'bracketSize': 4,
      'matchupDurationDays': 1,
      'creatorId': 'someone-else',
      'acceptedCount': 2,
      'myStatus': 'ACCEPTED',
      'participants': [
        {'userId': 'me', 'displayName': 'Me', 'status': 'ACCEPTED'},
        {'userId': 'u2', 'displayName': 'Bob', 'status': 'ACCEPTED'},
      ],
    });
    expect(find.byType(TournamentBracketBoard), findsOneWidget);
    // 4-bracket, 2 accepted → 2 filled + 2 OPEN leaf slots in the preview.
    expect(find.text('OPEN'), findsNWidgets(2));
    // The HUD carries the fill count in a game tile (the "N/M" conveys the
    // fill state; the verbose status line was removed).
    expect(find.text('FILLED'), findsOneWidget);
    expect(find.text('2/4'), findsOneWidget);
    await _teardown(tester);
  });

  testWidgets('featured PENDING shows prize tile, no creator START',
      (tester) async {
    await _pump(tester, {
      'id': 't1',
      'name': 'Daily Dash',
      'status': 'PENDING',
      'seedId': 'seed-tournament-daily-dash',
      'seedKind': 'DAILY_DASH',
      'bracketSize': 4,
      'championPrizeCoins': 150,
      'acceptedCount': 3,
      'myStatus': 'ACCEPTED',
      'participants': const [],
    });
    // The prize HUD tile shows the minted champion prize in gold.
    expect(find.text('CHAMPION WINS'), findsOneWidget);
    expect(find.text('150'), findsOneWidget);
    // Featured lobby has no creator controls.
    expect(find.text('START TOURNAMENT'), findsNothing);
    expect(find.text('NEED 1 MORE'), findsNothing);
    await _teardown(tester);
  });

  testWidgets('ACTIVE bracket draws round labels, TBD, and my-matchup CTA',
      (tester) async {
    await _pump(tester, {
      'id': 't1',
      'name': 'Gauntlet',
      'status': 'ACTIVE',
      'bracketSize': 4,
      'matchupDurationDays': 1,
      'currentRound': 1,
      'totalRounds': 2,
      'myStatus': 'ACCEPTED',
      'participants': [
        {'userId': 'me', 'displayName': 'Me', 'status': 'ACCEPTED'},
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
              'status': 'ACTIVE',
              'players': [
                {'userId': 'me', 'totalSteps': 100, 'forfeited': false},
                {'userId': 'u2', 'totalSteps': 90, 'forfeited': false},
              ],
              'winnerUserId': null,
            },
          ],
        },
        {
          'round': 2,
          'label': 'FINAL',
          'matchups': [
            {'matchIndex': 0, 'raceId': null, 'players': const []},
          ],
        },
      ],
    });
    expect(find.byType(TournamentBracketBoard), findsOneWidget);
    expect(find.text('SEMIFINALS'), findsWidgets);
    expect(find.text('FINAL'), findsWidgets);
    // The undrawn final shows a TBD placeholder (both of its slots).
    expect(find.text('TBD'), findsWidgets);
    // My live matchup CTA (on the box) + the action-bar shortcut.
    expect(find.text('TAP TO RACE'), findsOneWidget);
    expect(find.text('GO TO MY MATCHUP'), findsOneWidget);
    // The HUD ROUND tile.
    expect(find.text('ROUND'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
    await _teardown(tester);
  });

  testWidgets('COMPLETED: confetti ONLY when the viewer is the champion',
      (tester) async {
    await _pump(tester, {
      'id': 't1',
      'name': 'Gauntlet',
      'status': 'COMPLETED',
      'bracketSize': 4,
      'championUserId': 'me',
      'potCoins': 400,
      'participants': [
        {'userId': 'me', 'displayName': 'Me', 'status': 'ACCEPTED'},
      ],
      'rounds': const [],
    });
    expect(find.byType(CelebrationConfetti), findsOneWidget);
    // Champion column label + crown node render.
    expect(find.text('CHAMPION'), findsWidgets);
    // Winnings surface in the info strip.
    expect(find.textContaining('400'), findsWidgets);
    // Let CelebrationConfetti's one-shot delayed haptic fire before teardown so
    // no confetti timer is left pending when the binding checks.
    await tester.pump(const Duration(milliseconds: 300));
    await _teardown(tester);
  });

  testWidgets('COMPLETED: no confetti for a non-champion viewer',
      (tester) async {
    await _pump(tester, {
      'id': 't1',
      'name': 'Gauntlet',
      'status': 'COMPLETED',
      'bracketSize': 4,
      'championUserId': 'someone-else',
      'potCoins': 400,
      'participants': [
        {'userId': 'someone-else', 'displayName': 'Ann', 'status': 'ACCEPTED'},
        {'userId': 'me', 'displayName': 'Me', 'status': 'ACCEPTED'},
      ],
      'rounds': const [],
    });
    expect(find.byType(CelebrationConfetti), findsNothing);
    expect(find.text('CHAMPION'), findsWidgets);
    await _teardown(tester);
  });
}
