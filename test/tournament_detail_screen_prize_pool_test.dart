import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tournament_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// App-funded prize pools on the bracket screen (spec §7.5 / §9). A funded
// bracket carries the same additive `prizePool` object (§5.2, capped at 1,000)
// and `buyInAmount: 0`; an older backend sends neither and the screen keeps
// rendering today's pot-based figure.

class _FakeApi extends BackendApiService {
  _FakeApi(this.payload);

  final Map<String, dynamic> payload;
  int joinCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchTournament({
    required String identityToken,
    required String tournamentId,
  }) async => {'tournament': payload};

  @override
  Future<Map<String, dynamic>> respondToTournamentInvite({
    required String identityToken,
    required String tournamentId,
    required bool accept,
  }) async {
    joinCalls += 1;
    return {'tournament': payload};
  }
}

Map<String, dynamic> _funded({String myStatus = 'ACCEPTED'}) => {
  'id': 't1',
  'name': 'Free Bracket',
  'status': 'PENDING',
  'bracketSize': 4,
  'matchupDurationDays': 2,
  'creatorId': 'someone-else',
  'acceptedCount': 2,
  'buyInAmount': 0,
  'potCoins': 320,
  'myStatus': myStatus,
  'prizePool': const {
    'coins': 320,
    'projected': true,
    'atMax': false,
    'playerCount': 4,
    'durationDays': 4,
    'durationPoints': 4,
    'coinUnit': 20,
    'maxCoins': 1000,
    'funded': true,
  },
  'participants': const [
    {'userId': 'me', 'displayName': 'Me', 'status': 'ACCEPTED'},
    {'userId': 'u2', 'displayName': 'Bob', 'status': 'ACCEPTED'},
  ],
};

/// An older backend: no `prizePool`, a real paid pot.
Map<String, dynamic> _legacyPaid() => {
  'id': 't1',
  'name': 'Paid Bracket',
  'status': 'PENDING',
  'bracketSize': 4,
  'matchupDurationDays': 2,
  'creatorId': 'someone-else',
  'acceptedCount': 2,
  'buyInAmount': 100,
  'potCoins': 400,
  'myStatus': 'INVITED',
  'participants': const [
    {'userId': 'u2', 'displayName': 'Bob', 'status': 'ACCEPTED'},
  ],
};

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'me',
    'auth_display_name': 'Me',
    'auth_coins': 0,
    'auth_held_coins': 0,
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Future<void> _pump(WidgetTester tester, _FakeApi api) async {
  final auth = await _auth();
  await tester.pumpWidget(
    MaterialApp(
      home: TournamentDetailScreen(
        authService: auth,
        tournamentId: 't1',
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a funded bracket shows PRIZE POOL from the new object', (
    tester,
  ) async {
    await _pump(tester, _FakeApi(_funded()));

    expect(find.text('PRIZE POOL'), findsOneWidget);
    expect(find.text('320'), findsOneWidget);
    expect(find.text('CHAMPION WINS'), findsNothing);

    await _teardown(tester);
  });

  testWidgets('a rounded server champion projection is rendered unchanged', (
    tester,
  ) async {
    final tournament = _funded()
      ..['prizePool'] = const {
        'coins': 325,
        'projected': true,
        'atMax': false,
        'playerCount': 4,
        'durationDays': 4,
        'durationPoints': 4,
        'coinUnit': 20,
        'maxCoins': 1000,
        'funded': true,
      };
    await _pump(tester, _FakeApi(tournament));

    expect(find.text('PRIZE POOL'), findsOneWidget);
    expect(find.text('325'), findsOneWidget);
    expect(find.text('320'), findsNothing);

    await _teardown(tester);
  });

  testWidgets('an older backend falls back to the pot figure', (tester) async {
    await _pump(tester, _FakeApi(_legacyPaid()));

    // Exactly today's plaque.
    expect(find.text('WINNER TAKES'), findsNothing);
    expect(find.text('CHAMPION WINS'), findsOneWidget);
    expect(find.text('400'), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets('accepting a funded bracket invite is one tap', (tester) async {
    final api = _FakeApi(_funded(myStatus: 'INVITED'));
    await _pump(tester, api);

    final accept = find.text('ACCEPT');
    expect(accept, findsOneWidget);
    await tester.ensureVisible(accept);
    await tester.tap(accept);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('GOLD BUY-IN'), findsNothing);
    expect(api.joinCalls, 1);

    await _teardown(tester);
  });
}
