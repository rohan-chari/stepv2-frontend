import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/home_course_track.dart';
import 'package:step_tracker/widgets/retro_card.dart';

class _FakeBackendApiService extends BackendApiService {
  int respondCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async {
    return {
      'id': raceId,
      'name': 'Paid Race',
      'status': 'PENDING',
      'targetSteps': 100000,
      'maxDurationDays': 7,
      'buyInAmount': 100,
      'payoutPreset': 'WINNER_TAKES_ALL',
      'potCoins': 0,
      'heldPotCoins': 100,
      'projectedPotCoins': 100,
      'payouts': {'first': 100, 'second': 0, 'third': 0},
      'myStatus': 'INVITED',
      'isCreator': false,
      'participants': const [
        {
          'userId': 'creator-1',
          'displayName': 'RaceMaker',
          'status': 'ACCEPTED',
        },
        {
          'userId': 'user-1',
          'displayName': 'Trail Walker',
          'status': 'INVITED',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> respondToRaceInvite({
    required String identityToken,
    required String raceId,
    required bool accept,
  }) async {
    respondCalls += 1;
    return {
      'participant': {'id': 'rp-1', 'status': accept ? 'ACCEPTED' : 'DECLINED'},
    };
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    return const {'coins': 320, 'heldCoins': 100};
  }
}

class _ActivePaidRaceBackendApiService extends BackendApiService {
  _ActivePaidRaceBackendApiService({
    this.numericValuesAsDouble = false,
    this.powerupData = const {
      'enabled': false,
      'inventory': [],
      'powerupSlots': 3,
      'queuedBoxCount': 0,
      'activeEffects': [],
    },
  });

  final bool numericValuesAsDouble;
  final Map<String, dynamic> powerupData;

  num _number(int value) {
    return numericValuesAsDouble ? value.toDouble() : value;
  }

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async {
    return {
      'id': raceId,
      'name': 'Gold Sprint',
      'status': 'ACTIVE',
      'targetSteps': _number(100000),
      'maxDurationDays': _number(7),
      'buyInAmount': _number(100),
      'payoutPreset': 'TOP3_70_20_10',
      'potCoins': _number(600),
      'heldPotCoins': _number(0),
      'projectedPotCoins': _number(600),
      'payouts': {
        'first': _number(420),
        'second': _number(120),
        'third': _number(60),
      },
      'myStatus': 'ACCEPTED',
      'isCreator': false,
      'powerupsEnabled': false,
      'endsAt': '2026-04-10T12:00:00.000Z',
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
    return {
      'status': 'ACTIVE',
      'participants': const [
        {
          'userId': 'user-1',
          'displayName': 'Trail Walker',
          'totalSteps': 42000.0,
          'finishedAt': null,
        },
        {
          'userId': 'user-2',
          'displayName': 'Hill Climber',
          'totalSteps': 38000.0,
          'finishedAt': null,
        },
      ],
      'powerupData': powerupData,
    };
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

class _PendingAcceptedRaceBackendApiService extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async {
    return {
      'id': raceId,
      'name': 'Test Race Wagers',
      'status': 'PENDING',
      'targetSteps': 40000,
      'maxDurationDays': 5,
      'buyInAmount': 100,
      'payoutPreset': 'TOP3_70_20_10',
      'potCoins': 300,
      'heldPotCoins': 300,
      'projectedPotCoins': 300,
      'payouts': {'first': 210, 'second': 60, 'third': 30},
      'myStatus': 'ACCEPTED',
      'isCreator': false,
      'participants': const [
        {'userId': 'user-2', 'displayName': 'Sugaroro', 'status': 'ACCEPTED'},
        {'userId': 'user-3', 'displayName': 'emersonz', 'status': 'INVITED'},
        {
          'userId': 'user-1',
          'displayName': 'Trail Walker',
          'status': 'ACCEPTED',
        },
      ],
    };
  }
}

class _SlowProgressRaceBackendApiService
    extends _ActivePaidRaceBackendApiService {
  final Completer<Map<String, dynamic>> progressCompleter =
      Completer<Map<String, dynamic>>();

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) {
    return progressCompleter.future;
  }
}

class _FailingProgressRaceBackendApiService
    extends _ActivePaidRaceBackendApiService {
  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async {
    throw const ApiException('Connection timed out.');
  }
}

// A field-scaled preset (top half) that pays five places, so the detail card
// shows the podium inline plus a "+2 MORE" affordance backed by payoutTiers.
class _FieldScaledPayoutRaceBackendApiService
    extends _ActivePaidRaceBackendApiService {
  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async {
    final base = await super.fetchRaceDetails(
      identityToken: identityToken,
      raceId: raceId,
    );
    base['payoutPreset'] = 'TOP_HALF';
    base['payoutTiers'] = const [
      {'placement': 1, 'amount': 300},
      {'placement': 2, 'amount': 150},
      {'placement': 3, 'amount': 90},
      {'placement': 4, 'amount': 40},
      {'placement': 5, 'amount': 20},
    ];
    return base;
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

Future<AuthService> _createSignedOutAuthService() async {
  SharedPreferences.setMockInitialValues({});

  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('RaceDetailScreen stops loading without an auth token', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RaceDetailScreen(
          authService: await _createSignedOutAuthService(),
          raceId: 'race-no-token',
          backendApiService: _ActivePaidRaceBackendApiService(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Failed to load race'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
    'RaceDetailScreen shows a progress skeleton while active race progress loads',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final backendApiService = _SlowProgressRaceBackendApiService();

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-loading-progress',
            backendApiService: backendApiService,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('race-detail-progress-skeleton')),
        findsOneWidget,
      );
      expect(find.text('Powerups are disabled for this race'), findsNothing);
      expect(find.text('No powerup activity yet'), findsNothing);

      backendApiService.progressCompleter.complete({
        'status': 'ACTIVE',
        'participants': const [
          {
            'userId': 'user-1',
            'displayName': 'Trail Walker',
            'totalSteps': 42000,
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
      });
      await tester.pump();

      expect(find.byType(HomeCourseTrack), findsOneWidget);
    },
  );

  testWidgets(
    'RaceDetailScreen shows a retry state when active race progress fails',
    (WidgetTester tester) async {
      final authService = await _createAuthService();

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-failing-progress',
            backendApiService: _FailingProgressRaceBackendApiService(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('race-detail-progress-error')),
        findsOneWidget,
      );
      expect(find.text('Couldn’t load race progress'), findsOneWidget);
      expect(find.text('TRY AGAIN'), findsOneWidget);
      expect(find.text('Powerups are disabled for this race'), findsNothing);
    },
  );

  testWidgets(
    'RaceDetailScreen confirms paid invite acceptance before joining',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final backendApiService = _FakeBackendApiService();

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-1',
            backendApiService: backendApiService,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('ACCEPT'), findsOneWidget);

      await tester.tap(find.text('ACCEPT'));
      await tester.pump();

      expect(find.text('100 GOLD BUY-IN'), findsOneWidget);
      expect(
        find.text('Your 100 gold will be held until the race starts.'),
        findsOneWidget,
      );
      expect(backendApiService.respondCalls, 0);

      await tester.tap(find.text('LOCK IT IN'));
      await tester.pumpAndSettle();

      expect(backendApiService.respondCalls, 1);
    },
  );

  testWidgets(
    'RaceDetailScreen shows the prize pool near the countdown for active paid races',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final backendApiService = _ActivePaidRaceBackendApiService();

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-2',
            backendApiService: backendApiService,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('PRIZE POOL'), findsOneWidget);
      expect(find.text('600'), findsOneWidget);
      final prizePoolBoard = find.byKey(const Key('race-prize-pool-board'));
      final prizePoolSummary = find.byKey(const Key('race-prize-pool-summary'));
      expect(prizePoolBoard, findsOneWidget);
      expect(prizePoolSummary, findsOneWidget);
      expect(
        (tester.getRect(prizePoolSummary).center.dx -
                tester.getRect(prizePoolBoard).center.dx)
            .abs(),
        lessThanOrEqualTo(1),
      );
      expect(
        find.descendant(of: prizePoolSummary, matching: find.text('1ST')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: prizePoolSummary, matching: find.text('420')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: prizePoolSummary, matching: find.text('2ND')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: prizePoolSummary, matching: find.text('120')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: prizePoolSummary, matching: find.text('3RD')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: prizePoolSummary, matching: find.text('60')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('race-target-header')),
          matching: find.text('1ST'),
        ),
        findsNothing,
      );
      expect(find.byType(HomeCourseTrack), findsOneWidget);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'RaceDetailScreen collapses extra payout places behind a tap for field-scaled presets',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final backendApiService = _FieldScaledPayoutRaceBackendApiService();

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-2',
            backendApiService: backendApiService,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Podium shown inline; the remaining two places collapse behind "+2 MORE".
      final summary = find.byKey(const Key('race-prize-pool-summary'));
      expect(summary, findsOneWidget);
      expect(
        find.descendant(of: summary, matching: find.text('1ST')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: summary, matching: find.text('+2 MORE')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: summary, matching: find.text('4TH')),
        findsNothing,
      );

      // Tapping reveals every paid place in a bottom sheet.
      await tester.tap(find.text('+2 MORE'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('PAYOUTS'), findsOneWidget);
      expect(find.text('4TH'), findsOneWidget);
      expect(find.text('5TH'), findsOneWidget);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'RaceDetailScreen accepts active race numeric fields as doubles',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final backendApiService = _ActivePaidRaceBackendApiService(
        numericValuesAsDouble: true,
        powerupData: const {
          'enabled': true,
          'inventory': [],
          'powerupSlots': 3.0,
          'queuedBoxCount': 0.0,
          'activeEffects': [],
          'powerupStepInterval': 5000.0,
          'stepsUntilNextPowerup': 1240.0,
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-double-values',
            backendApiService: backendApiService,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(HomeCourseTrack), findsOneWidget);
      expect(find.text('PRIZE POOL'), findsOneWidget);
      expect(
        find.text(
          'You earn a powerup every 5,000 steps this race. 1,240 to go.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'RaceDetailScreen shows the next powerup helper near the race target copy',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final backendApiService = _ActivePaidRaceBackendApiService(
        powerupData: const {
          'enabled': true,
          'inventory': [],
          'powerupSlots': 3,
          'queuedBoxCount': 0,
          'activeEffects': [],
          'powerupStepInterval': 5000,
          'stepsUntilNextPowerup': 1240,
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-3',
            backendApiService: backendApiService,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.text(
          'You earn a powerup every 5,000 steps this race. 1,240 to go.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'RaceDetailScreen hides the next powerup helper when no next interval is available',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final backendApiService = _ActivePaidRaceBackendApiService(
        powerupData: const {
          'enabled': true,
          'inventory': [],
          'powerupSlots': 3,
          'queuedBoxCount': 0,
          'activeEffects': [],
          'powerupStepInterval': 5000,
          'stepsUntilNextPowerup': 0,
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-4',
            backendApiService: backendApiService,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.text(
          'You earn a powerup every 5,000 steps this race. 1,240 to go.',
        ),
        findsNothing,
      );
      expect(find.textContaining('You earn a powerup every'), findsNothing);
    },
  );

  testWidgets(
    'RaceDetailScreen stretches the waiting-for-creator card to the full pending board width',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final backendApiService = _PendingAcceptedRaceBackendApiService();

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-5',
            backendApiService: backendApiService,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final retroCards = find.byType(RetroCard);
      final participantCardSize = tester.getSize(retroCards.at(1));
      final waitingCardSize = tester.getSize(retroCards.at(2));

      expect(waitingCardSize.width, equals(participantCardSize.width));
    },
  );
}
