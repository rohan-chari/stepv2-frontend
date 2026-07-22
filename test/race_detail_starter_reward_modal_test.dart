import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _StarterRewardApi extends BackendApiService {
  int fetchCalls = 0;
  int claimCalls = 0;

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
      'buyInAmount': 0,
      'potCoins': 0,
      'heldPotCoins': 0,
      'projectedPotCoins': 0,
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
          'totalSteps': 4200.0,
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
  }

  @override
  Future<Map<String, dynamic>> fetchRaceFeed({
    String? cursor,
    required String identityToken,
    required String raceId,
  }) async {
    return const {'events': []};
  }

  @override
  Future<Map<String, dynamic>> fetchStarterReward({
    required String identityToken,
  }) async {
    fetchCalls += 1;
    return const {
      'eligible': true,
      'claimed': false,
      'amount': 100,
      'raceId': null,
    };
  }

  @override
  Future<Map<String, dynamic>> claimStarterReward({
    required String identityToken,
  }) async {
    claimCalls += 1;
    return const {'granted': true, 'coins': 520};
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    return const {'coins': 520, 'heldCoins': 0};
  }
}

Future<AuthService> _createAuthService({bool onboardingV2 = true}) async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_coins': 420,
    'auth_held_coins': 0,
    'auth_onboarding_v2_enabled': onboardingV2,
  });

  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

/// pumpAndSettle is unusable on this screen: an ACTIVE race runs a 1s
/// countdown ticker and a poll timer, so pump discrete frames instead.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _pump(
  WidgetTester tester,
  _StarterRewardApi api, {
  bool onboardingV2 = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RaceDetailScreen(
        authService: await _createAuthService(onboardingV2: onboardingV2),
        raceId: 'race-starter',
        backendApiService: api,
      ),
    ),
  );
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('opening an onboarding race does not load a starter reward', (
    WidgetTester tester,
  ) async {
    final api = _StarterRewardApi();
    await _pump(tester, api);

    expect(api.fetchCalls, 0);
    expect(api.claimCalls, 0);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('FIRST RACE BONUS'), findsNothing);
    expect(find.byKey(const Key('claim-starter-reward')), findsNothing);
  });
}
