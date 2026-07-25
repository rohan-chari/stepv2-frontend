import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tournament_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// Spec §4 / test 12 — the bracket countdown told three lies:
//   * under a minute it rendered "0m",
//   * at zero it flipped to "ROUND ENDS IN soon" and sat there for the whole
//     5-minute raceExpiry settlement window,
//   * and it ticked every second to repaint minute granularity.
// It must now show seconds under a minute, swap the WHOLE bar to a settling
// state once endsAt has passed, and stop the per-second timer there.

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

Map<String, dynamic> _activeTournament(DateTime endsAt) => {
      'id': 't1',
      'name': 'Lobby Bracket',
      'status': 'ACTIVE',
      'bracketSize': 4,
      'matchupDurationDays': 1,
      'creatorId': 'someone-else',
      'acceptedCount': 4,
      'myStatus': 'ACCEPTED',
      'currentRound': 1,
      'participants': [
        {'userId': 'me', 'displayName': 'Me', 'status': 'ACCEPTED'},
        {'userId': 'u2', 'displayName': 'Bob', 'status': 'ACCEPTED'},
        {'userId': 'u3', 'displayName': 'Cal', 'status': 'ACCEPTED'},
        {'userId': 'u4', 'displayName': 'Dee', 'status': 'ACCEPTED'},
      ],
      'rounds': [
        {
          'round': 1,
          'matchups': [
            {
              'matchupId': 'm1',
              'raceId': 'r1',
              'endsAt': endsAt.toUtc().toIso8601String(),
              'participants': [
                {'userId': 'me', 'displayName': 'Me'},
                {'userId': 'u2', 'displayName': 'Bob'},
              ],
            },
            {
              'matchupId': 'm2',
              'raceId': 'r2',
              'endsAt': endsAt.toUtc().toIso8601String(),
              'participants': [
                {'userId': 'u3', 'displayName': 'Cal'},
                {'userId': 'u4', 'displayName': 'Dee'},
              ],
            },
          ],
        },
      ],
    };

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
  await tester.pump();
  await tester.pump();
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => TournamentDetailScreen.debugCountdownTicks = 0);

  testWidgets('under a minute the countdown renders seconds, never 0m',
      (tester) async {
    await _pump(
      tester,
      _activeTournament(DateTime.now().add(const Duration(seconds: 45))),
    );

    expect(find.text('ROUND ENDS IN'), findsOneWidget);
    expect(find.text('0m'), findsNothing);
    // A one-second render lag between building the payload and pumping is
    // possible, so accept the adjacent second.
    final seconds = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data)
        .whereType<String>()
        .where((s) => RegExp(r'^\d+s$').hasMatch(s))
        .toList();
    expect(seconds, isNotEmpty,
        reason: 'expected a seconds-granularity countdown value');
    expect(['45s', '44s'], contains(seconds.first));

    await _teardown(tester);
  });

  testWidgets('minutes granularity is kept above a minute', (tester) async {
    await _pump(
      tester,
      _activeTournament(DateTime.now().add(const Duration(minutes: 7))),
    );
    expect(find.text('ROUND ENDS IN'), findsOneWidget);
    expect(find.text('6m'), findsOneWidget);
    await _teardown(tester);
  });

  testWidgets('past endsAt the bar swaps to the settling state',
      (tester) async {
    await _pump(
      tester,
      _activeTournament(DateTime.now().subtract(const Duration(seconds: 5))),
    );

    expect(find.text('ROUND ENDS IN'), findsNothing);
    expect(find.text('soon'), findsNothing);
    expect(find.text('SETTLING'), findsOneWidget);
    expect(find.text('Results in a few minutes'), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets('the per-second timer stops once the round has ended',
      (tester) async {
    await _pump(
      tester,
      _activeTournament(DateTime.now().subtract(const Duration(seconds: 5))),
    );

    // Let the tick that notices the pass-over run, then confirm it stops.
    await tester.pump(const Duration(seconds: 1));
    final settled = TournamentDetailScreen.debugCountdownTicks;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(TournamentDetailScreen.debugCountdownTicks, settled,
        reason: 'countdown timer must be cancelled in the settling state');

    await _teardown(tester);
  });

  testWidgets('a live round keeps ticking every second', (tester) async {
    await _pump(
      tester,
      _activeTournament(DateTime.now().add(const Duration(minutes: 30))),
    );
    final before = TournamentDetailScreen.debugCountdownTicks;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(TournamentDetailScreen.debugCountdownTicks, greaterThan(before));
    await _teardown(tester);
  });
}
