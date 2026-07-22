import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

/// The first-race bonus is presented as a modal (it used to be an inline card
/// in the race body), so these pump the real screen and assert on the dialog.
class _StarterRewardApi extends BackendApiService {
  _StarterRewardApi({
    this.eligible = true,
    this.claimed = false,
    this.granted = true,
    this.claimError,
  });

  final bool eligible;
  final bool claimed;
  final bool granted;
  final ApiException? claimError;
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
    return {
      'eligible': eligible,
      'claimed': claimed,
      'amount': 100,
      'raceId': null,
    };
  }

  @override
  Future<Map<String, dynamic>> claimStarterReward({
    required String identityToken,
  }) async {
    claimCalls += 1;
    final error = claimError;
    if (error != null) throw error;
    return {'granted': granted, 'coins': 520};
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
/// countdown ticker and a poll timer, and SpinningCoin animates forever, so
/// the tree never reaches a steady state. Pump discrete frames instead — one
/// to flush the async loads, then past the dialog's route transition.
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

  testWidgets('first race bonus opens as a modal on an active race', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _StarterRewardApi());

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('FIRST RACE BONUS'), findsOneWidget);
    expect(find.text('CLAIM 100 COINS'), findsOneWidget);
  });

  testWidgets('claiming grants once and closes the modal (owner decision '
      '2026-07-22: one appearance, no swapped-in claimed face)', (
    WidgetTester tester,
  ) async {
    final api = _StarterRewardApi();
    await _pump(tester, api);

    await tester.tap(find.byKey(const Key('claim-starter-reward')));
    await _settle(tester);

    expect(api.claimCalls, 1);
    // The dialog closes on claim — never a second face that reads as another
    // 100-coin offer. A toast confirms the grant instead.
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('+100 COINS'), findsNothing);
    expect(find.text('Starter reward claimed.'), findsNothing);
    expect(find.textContaining('+100 coins added'), findsOneWidget);
  });

  testWidgets('no modal when the reward is not eligible', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _StarterRewardApi(eligible: false));

    expect(find.byType(Dialog), findsNothing);
    expect(find.text('FIRST RACE BONUS'), findsNothing);
  });

  testWidgets('no modal when the reward was already claimed', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _StarterRewardApi(claimed: true));

    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('an older backend without the endpoint shows no modal', (
    WidgetTester tester,
  ) async {
    // 404 => the screen hides this optional surface entirely rather than
    // rendering a bonus the backend cannot grant.
    await _pump(
      tester,
      _StarterRewardApi(
        claimError: const ApiException('Not found', statusCode: 404),
      ),
    );
    expect(find.byType(Dialog), findsOneWidget);

    await tester.tap(find.byKey(const Key('claim-starter-reward')));
    await _settle(tester);

    // Claim refused: the modal closes rather than stranding the user on it.
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('a refused grant closes the modal instead of celebrating', (
    WidgetTester tester,
  ) async {
    // granted:false means the server had already paid this out (e.g. a double
    // tap racing a reinstall) — there is nothing to reveal, so close quietly.
    final api = _StarterRewardApi(granted: false);
    await _pump(tester, api);
    expect(find.text('FIRST RACE BONUS'), findsOneWidget);

    await tester.tap(find.byKey(const Key('claim-starter-reward')));
    await _settle(tester);

    expect(api.claimCalls, 1);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('+100 COINS'), findsNothing);
  });

  testWidgets('no modal when onboarding v2 is off', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _StarterRewardApi(), onboardingV2: false);

    expect(find.byType(Dialog), findsNothing);
  });
}
