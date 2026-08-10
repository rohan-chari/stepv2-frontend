// Feature batch 2026-08-08 — Item 1 (discard for coins + confirm dialog) and
// Item 12 (per-action loading indicators).
//
// Pumps the REAL race detail screen against a stubbed HTTP layer so the
// assertions are about what a user sees, not about a mocked collaborator.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/item_slot.dart';
import 'package:step_tracker/widgets/pill_button.dart';

const _heldPowerup = {
  'id': 'pu-1',
  'type': 'PROTEIN_SHAKE',
  'rarity': 'RARE',
  'status': 'HELD',
  'upgradeLevel': 0,
};

Map<String, dynamic> _race() => {
  'id': 'race-1',
  'name': 'Trail Blazers',
  'status': 'ACTIVE',
  'maxDurationDays': 3,
  'buyInAmount': 0,
  'potCoins': 0,
  'heldPotCoins': 0,
  'projectedPotCoins': 0,
  'myStatus': 'ACCEPTED',
  'isCreator': false,
  'powerupsEnabled': true,
  'endsAt': '2126-04-10T12:00:00.000Z',
  'participants': [
    {'userId': 'user-1', 'displayName': 'Runner 1', 'status': 'ACCEPTED'},
    {'userId': 'user-2', 'displayName': 'Runner 2', 'status': 'ACCEPTED'},
  ],
};

class _StubApi extends BackendApiService {
  _StubApi({
    this.discardResponse = const {'ok': true},
    this.discardDelay,
    this.serverDiscardPrices,
  });

  /// `powerupData.discardPrices` from the backend. Null = an older backend
  /// that doesn't send them, which must fall back to the bundled table.
  final Map<String, dynamic>? serverDiscardPrices;

  /// What POST .../discard returns. Defaults to the OLD shape (no new fields)
  /// so the degradation path is the default, not the exception.
  final Map<String, dynamic> discardResponse;
  final Completer<void>? discardDelay;

  int discardCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async => _race();

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async => {
    'status': 'ACTIVE',
    'participants': [
      {
        'userId': 'user-1',
        'displayName': 'Runner 1',
        'totalSteps': 9000,
        'finishedAt': null,
      },
      {
        'userId': 'user-2',
        'displayName': 'Runner 2',
        'totalSteps': 8000,
        'finishedAt': null,
      },
    ],
    'powerupData': {
      'enabled': true,
      'inventory': const [_heldPowerup],
      'powerupSlots': 3,
      'queuedBoxCount': 0,
      'activeEffects': const [],
      if (serverDiscardPrices != null) 'discardPrices': serverDiscardPrices,
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
      const {'coins': 100, 'heldCoins': 0};

  @override
  Future<Map<String, dynamic>> fetchPowerupInventory({
    required String identityToken,
  }) async => const {
    'items': [
      {'powerupType': 'POCKET_WATCH', 'quantity': 2},
    ],
  };

  @override
  Future<Map<String, dynamic>> discardPowerup({
    required String identityToken,
    required String raceId,
    required String powerupId,
  }) async {
    discardCalls++;
    final gate = discardDelay;
    if (gate != null) await gate.future;
    return discardResponse;
  }
}

Future<AuthService> _authService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Runner',
    'auth_coins': 100,
    'auth_held_coins': 0,
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

Future<AuthService> _pump(WidgetTester tester, _StubApi api) async {
  // A real phone, not the 800x600 default: the powerup action sheet with a
  // full tier ladder plus DISCARD is taller than the default test viewport.
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final authService = await _authService();
  await tester.pumpWidget(
    MaterialApp(
      home: RaceDetailScreen(
        authService: authService,
        raceId: 'race-1',
        backendApiService: api,
      ),
    ),
  );
  // Bounded pumps — the hero's spinning coin animates forever.
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return authService;
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  await tester.pump(const Duration(milliseconds: 50));
}

/// Opens the powerup action sheet for the single held powerup by tapping its
/// tray slot — the same tap a user makes.
Future<void> _openPowerupSheet(WidgetTester tester) async {
  final heldSlot = find.byWidgetPredicate(
    (w) => w is ItemSlot && w.state == ItemSlotState.held,
  );
  expect(heldSlot, findsOneWidget);
  // The powerup tray sits below the fold on a test-sized viewport.
  await tester.ensureVisible(heldSlot);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(heldSlot);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.bara.steps',
      version: '2.2.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('Item 1 — discard confirm dialog', () {
    testWidgets('DISCARD opens a confirm dialog naming the rarity price', (
      tester,
    ) async {
      final api = _StubApi();
      await _pump(tester, api);
      await _openPowerupSheet(tester);

      expect(find.text('DISCARD'), findsOneWidget);
      // The DISCARD pill itself advertises the payout: "+10" and a coin glyph
      // as its trailing tag (RARE = 10), same shape as the tier-price tags.
      final discardPill = find.ancestor(
        of: find.text('DISCARD'),
        matching: find.byType(PillButton),
      );
      expect(
        find.descendant(of: discardPill, matching: find.text('+10')),
        findsOneWidget,
      );
      await tester.tap(find.text('DISCARD'));
      await tester.pump(const Duration(milliseconds: 300));

      // RARE = 10 coins.
      expect(find.byKey(const Key('discard-confirm-dialog')), findsOneWidget);
      expect(find.textContaining('10 coins'), findsOneWidget);
      // Nothing is discarded until the user confirms.
      expect(api.discardCalls, 0);

      await tester.tap(find.byKey(const Key('discard-confirm-cancel')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(api.discardCalls, 0);

      await _teardown(tester);
    });

    testWidgets('confirming discards and reports the coins awarded', (
      tester,
    ) async {
      final api = _StubApi(
        discardResponse: const {
          'ok': true,
          'coinsAwarded': 10,
          'coins': 110,
          'capRemaining': 30,
        },
      );
      final auth = await _pump(tester, api);
      await _openPowerupSheet(tester);
      await tester.tap(find.text('DISCARD'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('discard-confirm-yes')));
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.discardCalls, 1);
      expect(find.textContaining('+10 coins'), findsOneWidget);
      // Optimistic badge bump off the server's authoritative balance.
      expect(auth.coins, 110);

      await _teardown(tester);
    });

    testWidgets(
      'an OLDER backend (no coinsAwarded) degrades to the plain toast',
      (tester) async {
        final api = _StubApi(discardResponse: const {'ok': true});
        final auth = await _pump(tester, api);
        await _openPowerupSheet(tester);
        await tester.tap(find.text('DISCARD'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byKey(const Key('discard-confirm-yes')));
        await tester.pump(const Duration(milliseconds: 300));

        expect(api.discardCalls, 1);
        expect(find.textContaining('discarded'), findsOneWidget);
        expect(find.textContaining('coins'), findsNothing);
        // No phantom balance change.
        expect(auth.coins, 100);

        await _teardown(tester);
      },
    );
  });

  group('Item 1 — discard prices come from the server when it sends them', () {
    // Review fix 2: prices live in balance config so they can be retuned
    // without an App Store release. The bundled 2/5/10 map is only a fallback.
    Future<void> openDiscardDialog(WidgetTester tester) async {
      await _openPowerupSheet(tester);
      await tester.tap(find.text('DISCARD'));
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('server prices win over the bundled table', (tester) async {
      // The held powerup is RARE. Bundled says 10; the server says 25.
      await _pump(
        tester,
        _StubApi(
          serverDiscardPrices: const {
            'COMMON': 4,
            'UNCOMMON': 9,
            'RARE': 25,
          },
        ),
      );
      await openDiscardDialog(tester);

      expect(find.textContaining('for 25 coins'), findsOneWidget);
      expect(find.textContaining('for 10 coins'), findsNothing);
      await _teardown(tester);
    });

    testWidgets('an older backend falls back to the bundled 2/5/10', (
      tester,
    ) async {
      await _pump(tester, _StubApi());
      await openDiscardDialog(tester);

      expect(find.textContaining('for 10 coins'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('a malformed discardPrices falls back rather than quoting 0', (
      tester,
    ) async {
      // A non-map, or a map with no usable numeric entries, must not be
      // treated as "everything is free".
      await _pump(
        tester,
        _StubApi(serverDiscardPrices: const {'RARE': 'lots'}),
      );
      await openDiscardDialog(tester);

      // NB 'for 0 coins', not '0 coins' — the latter is a substring of
      // '10 coins' and would pass vacuously.
      expect(find.textContaining('for 0 coins'), findsNothing);
      expect(find.textContaining('for 10 coins'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('a rarity the server omits uses its COMMON floor', (
      tester,
    ) async {
      // RARE is missing from the server table -> fall back to the server's
      // own COMMON price (4), not the bundled RARE price (10).
      await _pump(
        tester,
        _StubApi(serverDiscardPrices: const {'COMMON': 4}),
      );
      await openDiscardDialog(tester);

      expect(find.textContaining('for 4 coins'), findsOneWidget);
      await _teardown(tester);
    });
  });

  group('Item 12 — PillButton loading', () {
    testWidgets('loading swaps the label for a spinner and disables the tap', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PillButton(
              label: 'USE',
              loading: true,
              onPressed: () => taps++,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(PillButtonSpinner), findsOneWidget);
      await tester.tap(find.byType(PillButton));
      await tester.pump(const Duration(milliseconds: 50));
      expect(taps, 0);
    });

    testWidgets('a non-loading button has no spinner and still fires', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PillButton(label: 'USE', onPressed: () => taps++),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(PillButtonSpinner), findsNothing);
      await tester.tap(find.byType(PillButton));
      await tester.pump(const Duration(milliseconds: 50));
      expect(taps, 1);
    });

    testWidgets('loading preserves the button width', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PillButton(label: 'OPEN ALL BOXES', onPressed: () {}),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      final restingWidth = tester.getSize(find.byType(PillButton)).width;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PillButton(
                label: 'OPEN ALL BOXES',
                loading: true,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.getSize(find.byType(PillButton)).width, restingWidth);
    });
  });
}
