import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

/// Shop-bought powerups in YOUR STASH must confirm before they're spent — the
/// same name + description sheet a box-earned powerup shows. Tapping USE on the
/// stash row opens the sheet; only the sheet's USE actually redeems.
class _StashApi extends BackendApiService {
  _StashApi({
    this.stashType = 'TRAIL_MIX',
    this.rejectUse = false,
  }) : _stashQuantity = 2;

  final String stashType;
  final bool rejectUse;
  int redeemCalls = 0;
  int? lastUpgradeLevel;
  int _stashQuantity;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async => {
    'id': raceId,
    'name': 'Stash Alley',
    'status': 'ACTIVE',
    'maxDurationDays': 7,
    'buyInAmount': 0,
    'myStatus': 'ACCEPTED',
    'powerupsEnabled': true,
    'endsAt': '2027-12-10T12:00:00.000Z',
    'participants': [
      {'userId': 'me', 'displayName': 'Bara', 'status': 'ACCEPTED'},
      {'userId': 'u1', 'displayName': 'Otter42', 'status': 'ACCEPTED'},
    ],
  };

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async => {
    'status': 'ACTIVE',
    'participants': [
      {'userId': 'me', 'displayName': 'Bara', 'totalSteps': 5000},
      {'userId': 'u1', 'displayName': 'Otter42', 'totalSteps': 4000},
    ],
    'powerupData': {
      'enabled': true,
      'inventory': const [],
      'powerupSlots': 3,
      'queuedBoxCount': 0,
      // One live timed self-buff, so Pocket Watch's "MY BUFFS" mode has
      // something to extend and its tier buttons are enabled.
      'activeEffects': const [
        {
          'type': 'CAMPFIRE_REST',
          'onSelf': true,
          'sourceUserId': 'me',
          'targetUserId': 'me',
          'expiresAt': '2027-12-01T00:00:00.000Z',
        },
      ],
      'powerupStepInterval': 5000,
      'stepsUntilNextPowerup': 1000,
    },
  };

  @override
  Future<Map<String, dynamic>> fetchRaceFeed({
    String? cursor,
    required String identityToken,
    required String raceId,
  }) async => const {'events': []};

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async =>
      const {'coins': 300, 'heldCoins': 0};

  @override
  Future<Map<String, dynamic>> fetchPowerupInventory({
    required String identityToken,
  }) async => {
    'items': [
      {'powerupType': stashType, 'quantity': _stashQuantity},
    ],
  };

  @override
  Future<Map<String, dynamic>> redeemPowerupToRace({
    required String identityToken,
    required String raceId,
    required String powerupType,
  }) async {
    redeemCalls++;
    _stashQuantity--;
    return {
      'result': {
        'powerup': {
          'id': 'pw-1',
          'type': powerupType,
          // Store redemption deliberately has no rarity or earnedAtSteps.
          'rarity': null,
          'status': 'HELD',
        },
      },
    };
  }

  @override
  Future<Map<String, dynamic>> usePowerup({
    required String identityToken,
    required String raceId,
    required String powerupId,
    String? targetUserId,
    String? targetDirection,
    String? targetEffectId,
    int upgradeLevel = 0,
  }) async {
    if (rejectUse) {
      // Mirrors the current backend's rejected-redeemed-item refund.
      _stashQuantity++;
      throw const ApiException('Quick Rinse is on cooldown', statusCode: 409);
    }
    lastUpgradeLevel = upgradeLevel;
    return const {'result': {}};
  }
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'token',
    'auth_user_identifier': 'user',
    'auth_session_token': 'session',
    'auth_backend_user_id': 'me',
    'auth_display_name': 'Bara',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Future<void> _pump(WidgetTester tester, _StashApi api) async {
  await tester.binding.setSurfaceSize(const Size(430, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: RaceDetailScreen(
        authService: await _auth(),
        raceId: 'race-stash',
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('stash USE opens a confirmation sheet instead of spending', (
    tester,
  ) async {
    final api = _StashApi();
    await _pump(tester, api);

    expect(find.text('YOUR STASH'), findsOneWidget);
    expect(find.text('Trail Mix x2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('stash-use-TRAIL_MIX')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The sheet carries the same copy the box-powerup sheet shows.
    expect(find.byKey(const Key('stash-confirm-sheet')), findsOneWidget);
    expect(find.text('Trail Mix'), findsOneWidget);
    expect(
      find.text('+100 steps per unique powerup type used'),
      findsOneWidget,
    );
    // Nothing is spent by merely opening the sheet.
    expect(api.redeemCalls, 0);
  });

  testWidgets('cancelling the stash sheet leaves the powerup unspent', (
    tester,
  ) async {
    final api = _StashApi();
    await _pump(tester, api);

    await tester.tap(find.byKey(const Key('stash-use-TRAIL_MIX')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('stash-confirm-cancel')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('stash-confirm-sheet')), findsNothing);
    expect(api.redeemCalls, 0);
    expect(find.text('Trail Mix x2'), findsOneWidget);
  });

  testWidgets('confirming the stash sheet redeems and uses the powerup', (
    tester,
  ) async {
    final api = _StashApi();
    await _pump(tester, api);

    await tester.tap(find.byKey(const Key('stash-use-TRAIL_MIX')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('stash-confirm-use')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(api.redeemCalls, 1);
    // The optimistic stash decrement still runs after the confirm.
    expect(find.text('Trail Mix x1'), findsOneWidget);
  });

  testWidgets('a rejected stash use reconciles the item back into YOUR STASH', (
    tester,
  ) async {
    final api = _StashApi(rejectUse: true);
    await _pump(tester, api);

    await tester.tap(find.byKey(const Key('stash-use-TRAIL_MIX')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('stash-confirm-use')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(api.redeemCalls, 1);
    // The authoritative follow-up read restores a server-refunded redeemed
    // item to the account-wide stash rather than leaving it in a race slot.
    expect(find.text('Trail Mix x2'), findsOneWidget);
  });

  // Pocket Watch is shop-only, so the stash is its main entry point: it must
  // get its own two-mode sheet, not the generic one, and nothing may be spent
  // until a tier is picked.
  testWidgets('stash Pocket Watch opens the two-mode sheet, spends nothing', (
    tester,
  ) async {
    final api = _StashApi(stashType: 'POCKET_WATCH');
    await _pump(tester, api);

    await tester.tap(find.byKey(const Key('stash-use-POCKET_WATCH')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('pocket-watch-tier-0')), findsOneWidget);
    // The generic stash sheet must NOT be the one that opened.
    expect(find.byKey(const Key('stash-confirm-sheet')), findsNothing);
    // No DISCARD: nothing has been redeemed yet.
    expect(find.byKey(const Key('pocket-watch-discard')), findsNothing);
    expect(api.redeemCalls, 0);
  });

  testWidgets('stash Pocket Watch forwards the chosen tier to the use call', (
    tester,
  ) async {
    final api = _StashApi(stashType: 'POCKET_WATCH');
    await _pump(tester, api);

    await tester.tap(find.byKey(const Key('stash-use-POCKET_WATCH')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('pocket-watch-tier-0')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(api.redeemCalls, 1);
    expect(api.lastUpgradeLevel, 0);
  });
}
