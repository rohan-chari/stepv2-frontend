import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// ---------------------------------------------------------------------------
// Global step-multiplier event banner on the race detail page.
//
// When getRaceProgress returns an active `globalEvent`
// ({ active: true, multiplier, endsAt }), the race page shows a "2x RACE STEPS"
// banner with a countdown to endsAt. When the field is absent, no banner.
// Read defensively — old responses simply omit the field.
// ---------------------------------------------------------------------------

class _GlobalEventBackendApiService extends BackendApiService {
  _GlobalEventBackendApiService({
    this.globalEvent,
    this.includeGlobalEvent = true,
  });

  final Object? globalEvent;
  final bool includeGlobalEvent;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async {
    return {
      'id': raceId,
      'name': 'Gold Sprint',
      'status': 'ACTIVE',
      'targetSteps': 100000,
      'maxDurationDays': 7,
      'buyInAmount': 0,
      'payoutPreset': 'WINNER_TAKES_ALL',
      'potCoins': 0,
      'heldPotCoins': 0,
      'projectedPotCoins': 0,
      'payouts': {'first': 0, 'second': 0, 'third': 0},
      'myStatus': 'ACCEPTED',
      'isCreator': false,
      'powerupsEnabled': false,
      'endsAt': '2026-06-10T12:00:00.000Z',
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
  }) async {
    final progress = <String, dynamic>{
      'status': 'ACTIVE',
      'participants': const [
        {
          'userId': 'user-1',
          'displayName': 'Trail Walker',
          'totalSteps': 42000,
          'finishedAt': null,
        },
        {
          'userId': 'user-2',
          'displayName': 'Hill Climber',
          'totalSteps': 38000,
          'finishedAt': null,
        },
      ],
      'powerupData': const {
        'enabled': false,
        'inventory': [],
        'powerupSlots': 3,
        'queuedBoxCount': 0,
        'activeEffects': [],
      },
    };
    if (includeGlobalEvent) {
      progress['globalEvent'] = globalEvent;
    }
    return progress;
  }

  @override
  Future<Map<String, dynamic>> fetchRaceFeed({
    String? cursor,
    required String identityToken,
    required String raceId,
  }) async {
    return const {'events': []};
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'shows the 2x event banner when progress includes an active globalEvent',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      // endsAt far in the future so the countdown is positive and the banner
      // is unambiguously "active".
      final endsAt = DateTime.now().toUtc().add(
        const Duration(minutes: 10, seconds: 30),
      );
      final backendApiService = _GlobalEventBackendApiService(
        globalEvent: {
          'active': true,
          'multiplier': 2,
          'endsAt': endsAt.toIso8601String(),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-event-on',
            backendApiService: backendApiService,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('race-global-event-banner')), findsOneWidget);
      expect(find.textContaining('2x RACE STEPS'), findsOneWidget);
      expect(
        find.textContaining('ends in 10:'),
        findsOneWidget,
        reason: 'race detail must use this viewer response endsAt',
      );

      // Tear down the periodic countdown timer.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('does NOT show the banner when progress omits globalEvent', (
    WidgetTester tester,
  ) async {
    final authService = await _createAuthService();
    final backendApiService = _GlobalEventBackendApiService(
      globalEvent: null,
      includeGlobalEvent: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RaceDetailScreen(
          authService: authService,
          raceId: 'race-event-off',
          backendApiService: backendApiService,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('race-global-event-banner')), findsNothing);
    expect(find.textContaining('2x RACE STEPS'), findsNothing);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'race detail fails soft for null, malformed, or expired globalEvent data',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final validEnd = DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 20))
          .toIso8601String();
      final malformedEvents = <Object?>[
        null,
        'not-an-object',
        {'active': false, 'multiplier': 2, 'endsAt': validEnd},
        {'multiplier': 2, 'endsAt': validEnd},
        {'active': null, 'multiplier': 2, 'endsAt': validEnd},
        {'active': 'true', 'multiplier': 2, 'endsAt': validEnd},
        {'active': true, 'endsAt': validEnd},
        {'active': true, 'multiplier': null, 'endsAt': validEnd},
        {'active': true, 'multiplier': '2', 'endsAt': validEnd},
        {'active': true, 'multiplier': double.nan, 'endsAt': validEnd},
        {'active': true, 'multiplier': double.infinity, 'endsAt': validEnd},
        {'active': true, 'multiplier': 2, 'endsAt': null},
        {'active': true, 'multiplier': 2, 'endsAt': 'not-a-date'},
        {
          'active': true,
          'multiplier': 2,
          'endsAt': DateTime.now()
              .toUtc()
              .subtract(const Duration(seconds: 1))
              .toIso8601String(),
        },
      ];

      for (var index = 0; index < malformedEvents.length; index++) {
        final globalEvent = malformedEvents[index];
        await tester.pumpWidget(
          MaterialApp(
            home: RaceDetailScreen(
              key: ValueKey('race-event-malformed-$index'),
              authService: authService,
              raceId: 'race-event-malformed-$index',
              backendApiService: _GlobalEventBackendApiService(
                globalEvent: globalEvent,
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(
          find.byKey(const Key('race-global-event-banner')),
          findsNothing,
          reason: 'malformed globalEvent must be ignored: $globalEvent',
        );
        expect(tester.takeException(), isNull);
      }

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'race detail ignores unknown map keys without losing valid event fields',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final endsAt = DateTime.now().toUtc().add(const Duration(minutes: 20));

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-event-extra-key',
            backendApiService: _GlobalEventBackendApiService(
              globalEvent: {
                1: 'malformed unknown key',
                'active': true,
                'multiplier': 2,
                'endsAt': endsAt.toIso8601String(),
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('race-global-event-banner')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
    },
  );
}
