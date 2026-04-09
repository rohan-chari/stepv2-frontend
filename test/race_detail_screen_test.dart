import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
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
    this.powerupData = const {
      'enabled': false,
      'inventory': [],
      'powerupSlots': 3,
      'queuedBoxCount': 0,
      'activeEffects': [],
    },
  });

  final Map<String, dynamic> powerupData;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async {
    return {
      'id': raceId,
      'name': 'Gold Sprint',
      'status': 'ACTIVE',
      'targetSteps': 100000,
      'maxDurationDays': 7,
      'buyInAmount': 100,
      'payoutPreset': 'TOP3_70_20_10',
      'potCoins': 600,
      'heldPotCoins': 0,
      'projectedPotCoins': 600,
      'payouts': {'first': 420, 'second': 120, 'third': 60},
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

bool _rowContainsTexts(WidgetTester tester, List<String> texts) {
  for (final rowElement in find.byType(Row).evaluate()) {
    final rowFinder = find.byElementPredicate(
      (element) => element == rowElement,
    );
    final containsAllTexts = texts.every(
      (text) => find
          .descendant(of: rowFinder, matching: find.text(text))
          .evaluate()
          .isNotEmpty,
    );

    if (containsAllTexts) {
      return true;
    }
  }

  return false;
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
      expect(find.text('1ST'), findsOneWidget);
      expect(find.text('420'), findsOneWidget);
      expect(find.text('2ND'), findsOneWidget);
      expect(find.text('120'), findsOneWidget);
      expect(find.text('3RD'), findsOneWidget);
      expect(find.text('60'), findsOneWidget);
      expect(
        _rowContainsTexts(tester, [
          'RACE TO ',
          '100,000',
          ' STEPS',
          '1ST',
          '420',
          '2ND',
          '120',
          '3RD',
          '60',
        ]),
        isTrue,
      );

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
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
