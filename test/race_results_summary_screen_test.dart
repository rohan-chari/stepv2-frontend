import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_results_summary_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _RematchApi extends BackendApiService {
  _RematchApi({this.failFirst = false});

  final bool failFirst;
  int calls = 0;
  String? sourceRaceId;
  final List<String> keys = <String>[];

  @override
  Future<Map<String, dynamic>> rematchRace({
    required String identityToken,
    required String raceId,
    required String idempotencyKey,
  }) async {
    calls++;
    sourceRaceId = raceId;
    keys.add(idempotencyKey);
    if (failFirst && calls == 1) {
      throw const ApiException('Connection interrupted.');
    }
    return const {
      'race': {'id': 'new-race', 'status': 'PENDING'},
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async => {
    'id': raceId,
    'name': 'Rematch',
    'status': 'PENDING',
    'myStatus': 'ACCEPTED',
    'participants': const <Map<String, dynamic>>[],
  };
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues(const {
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Widget _wrap(List<Map<String, dynamic>> races) {
  return MaterialApp(home: RaceResultsSummaryScreen(races: races));
}

void main() {
  testWidgets('single race shows place, winner, and payout', (tester) async {
    await tester.pumpWidget(
      _wrap([
        {
          'id': 'r1',
          'name': 'Weekend Sprint',
          'participantCount': 4,
          'myPlacement': 2,
          'myPayoutCoins': 120,
          'myStatus': 'ACCEPTED',
          'winner': {'displayName': 'Alex'},
        },
      ]),
    );
    await tester.pump();

    expect(find.text('RACE FINISHED'), findsOneWidget);
    expect(find.text('Weekend Sprint'), findsOneWidget);
    expect(find.text('2ND OF 4'), findsOneWidget);
    expect(find.text('+120'), findsOneWidget);
    expect(find.textContaining('Alex'), findsOneWidget);
  });

  testWidgets('null placement renders Did not finish', (tester) async {
    await tester.pumpWidget(
      _wrap([
        {
          'id': 'r1',
          'name': 'DNF Race',
          'participantCount': 3,
          'myPlacement': null,
          'myPayoutCoins': 0,
          'myStatus': 'ACCEPTED',
        },
      ]),
    );
    await tester.pump();

    expect(find.text('DID NOT FINISH'), findsOneWidget);
  });

  testWidgets('multiple races render a card each with plural header', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap([
        {
          'id': 'r1',
          'name': 'Race One',
          'participantCount': 2,
          'myPlacement': 1,
          'myPayoutCoins': 50,
          'winner': {'displayName': 'Me'},
        },
        {
          'id': 'r2',
          'name': 'Race Two',
          'participantCount': 5,
          'myPlacement': 4,
          'myPayoutCoins': 0,
          'winner': {'displayName': 'Sam'},
        },
      ]),
    );
    await tester.pump();

    expect(find.text('RACES FINISHED'), findsOneWidget);
    expect(find.text('Race One'), findsOneWidget);
    expect(find.text('Race Two'), findsOneWidget);
  });

  testWidgets('missing fields default safely (no crash)', (tester) async {
    await tester.pumpWidget(_wrap([<String, dynamic>{}]));
    await tester.pump();

    expect(find.text('Race'), findsOneWidget);
    expect(find.text('DID NOT FINISH'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('only literal eligibility binds rematch to its result card', (
    tester,
  ) async {
    final auth = await _auth();
    final api = _RematchApi();
    await tester.pumpWidget(
      MaterialApp(
        home: RaceResultsSummaryScreen(
          authService: auth,
          backendApiService: api,
          races: const [
            {
              'id': 'eligible',
              'name': 'Eligible Race',
              'rematchEligible': true,
            },
            {
              'id': 'string-true',
              'name': 'Old Race',
              'rematchEligible': 'true',
            },
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('results-rematch-eligible')), findsOneWidget);
    expect(find.byKey(const Key('results-rematch-string-true')), findsNothing);
    await tester.tap(find.byKey(const Key('results-rematch-eligible')));
    await tester.pump();
    await tester.pump();

    expect(api.calls, 1);
    expect(api.sourceRaceId, 'eligible');
    expect(find.text('Rematch'), findsWidgets);
  });

  testWidgets('rematch retry reuses the source-bound idempotency key', (
    tester,
  ) async {
    final auth = await _auth();
    final api = _RematchApi(failFirst: true);
    await tester.pumpWidget(
      MaterialApp(
        home: RaceResultsSummaryScreen(
          authService: auth,
          backendApiService: api,
          races: const [
            {'id': 'retry-race', 'name': 'Retry Race', 'rematchEligible': true},
          ],
        ),
      ),
    );
    await tester.pump();

    final button = find.byKey(const Key('results-rematch-retry-race'));
    await tester.tap(button);
    await tester.pump();
    expect(api.calls, 1);
    await tester.tap(button);
    await tester.pump();
    await tester.pump();

    expect(api.calls, 2);
    expect(api.keys, hasLength(2));
    expect(api.keys[1], api.keys[0]);
  });
}
