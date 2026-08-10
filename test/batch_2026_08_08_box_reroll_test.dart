// Feature batch 2026-08-08 — Item 11: rewarded-ad mystery-box reroll.
//
// Covers the gating (flag on/off, demo, already-rerolled), the re-spin to the
// new result, and the ui-test-planner's risks 4 and 5: the button must NOT
// leak onto the OPEN ALL flow, the hand-forked daily-reward reel, or the demo.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:step_tracker/demo/demo_race_engine.dart';
import 'package:step_tracker/screens/case_opening_screen.dart';
import 'package:step_tracker/screens/multi_case_opening_screen.dart';
import 'package:step_tracker/tutorial/tutorial_preview_data.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/ad_service.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/item_slot.dart';
import 'package:step_tracker/widgets/pill_button.dart';

Map<String, dynamic> _openResult({String type = 'PROTEIN_SHAKE'}) => {
  'result': {
    'id': 'pu-1',
    'type': type,
    'rarity': 'COMMON',
    'autoActivated': false,
  },
};

Finder get _rerollButton => find.byKey(const Key('case-reroll-button'));

/// Drives the reel from open to reveal. The strip is swipe-OR-TAP gated; the
/// spinning icon never settles, so pump fixed durations (same shape as
/// test/case_opening_toast_test.dart).
Future<void> _spinToReveal(WidgetTester tester) async {
  await tester.tap(find.text('SWIPE OR TAP'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 4100));
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _pumpCase(
  WidgetTester tester, {
  Future<Map<String, dynamic>?> Function(String)? onReroll,
  Future<Map<String, dynamic>> Function()? openMysteryBox,
  bool demoMode = false,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: CaseOpeningScreen(
        openMysteryBox: openMysteryBox ?? () async => _openResult(),
        onReroll: onReroll,
        demoMode: demoMode,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}


// ── Fix-1 harness: the real RaceDetailScreen -> AdService -> API chain ──────

class _FakeAdController implements ExtraSpinAdController {
  _FakeAdController({this.earn = true});

  final bool earn;
  String? lastLocalDate;
  String? lastUserId;
  bool _loaded = false;

  @override
  bool get isSupported => true;

  @override
  bool get isReady => _loaded;

  @override
  Future<void> load({
    required String userId,
    required String localDate,
  }) async {
    lastUserId = userId;
    lastLocalDate = localDate;
    _loaded = true;
  }

  @override
  Future<bool> showAndAwaitReward() async {
    _loaded = false;
    return earn;
  }

  @override
  void dispose() {}
}

class _RerollStubApi extends BackendApiService {
  _RerollStubApi({this.failFirst = 0});

  /// How many leading attempts answer 409 AD_NOT_VERIFIED (SSV lag).
  final int failFirst;

  /// Whether the progress payload advertises the feature; set by the pump
  /// helper before the screen loads.
  bool boxReroll = true;

  int rerollCalls = 0;
  final List<String> localDates = [];

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async => {
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
    'participants': const [
      {'userId': 'user-1', 'displayName': 'Runner 1', 'status': 'ACCEPTED'},
    ],
  };

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async => {
    'status': 'ACTIVE',
    'participants': const [
      {
        'userId': 'user-1',
        'displayName': 'Runner 1',
        'totalSteps': 9000,
        'finishedAt': null,
      },
    ],
    'powerupData': {
      'enabled': true,
      'inventory': const [
        {'id': 'box-1', 'type': 'MYSTERY_BOX', 'status': 'MYSTERY_BOX'},
      ],
      'powerupSlots': 3,
      'queuedBoxCount': 0,
      'activeEffects': const [],
      if (boxReroll) 'boxReroll': true,
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
  Future<Map<String, dynamic>> openMysteryBox({
    required String identityToken,
    required String raceId,
    required String powerupId,
  }) async => const {
    'result': {
      'id': 'pu-1',
      'type': 'PROTEIN_SHAKE',
      'rarity': 'COMMON',
      'autoActivated': false,
    },
  };

  @override
  Future<Map<String, dynamic>> rerollPowerup({
    required String identityToken,
    required String raceId,
    required String powerupId,
    required String localDate,
  }) async {
    rerollCalls++;
    localDates.add(localDate);
    if (rerollCalls <= failFirst) {
      throw const ApiException(
        'not verified',
        statusCode: 409,
        code: 'AD_NOT_VERIFIED',
      );
    }
    return const {
      'id': 'pu-1',
      'type': 'ENERGY_GEL',
      'rarity': 'RARE',
      'rerolled': true,
    };
  }
}

Future<AuthService> _rerollAuth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Runner',
    'auth_coins': 100,
    'auth_held_coins': 0,
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Future<void> _pumpRaceDetail(
  WidgetTester tester, {
  required _RerollStubApi api,
  required _FakeAdController ad,
  required bool boxReroll,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  api.boxReroll = boxReroll;
  final auth = await _rerollAuth();
  await tester.pumpWidget(
    MaterialApp(
      home: RaceDetailScreen(
        authService: auth,
        raceId: 'race-1',
        backendApiService: api,
        boxRerollAdController: ad,
      ),
    ),
  );
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Taps the mystery-box slot and drives its reel to the reveal.
Future<void> _openBoxAndReveal(WidgetTester tester) async {
  final boxSlot = find.byWidgetPredicate(
    (w) => w is ItemSlot && w.state == ItemSlotState.mysteryBox,
  );
  await tester.ensureVisible(boxSlot);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(boxSlot);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await _spinToReveal(tester);
}

Future<void> _teardownRace(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  await tester.pump(const Duration(milliseconds: 100));
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

  group('gating', () {
    testWidgets('no button before the reveal', (tester) async {
      await _pumpCase(tester, onReroll: (_) async => null);
      expect(_rerollButton, findsNothing);
    });

    testWidgets('button appears after the reveal when wired', (tester) async {
      await _pumpCase(tester, onReroll: (_) async => null);
      await _spinToReveal(tester);

      expect(find.text('UNBOXED'), findsOneWidget);
      expect(_rerollButton, findsOneWidget);
      expect(find.text('REROLL · WATCH AD'), findsOneWidget);
    });

    testWidgets('flag off (onReroll null) → no button ever', (tester) async {
      await _pumpCase(tester);
      await _spinToReveal(tester);

      expect(find.text('UNBOXED'), findsOneWidget);
      expect(_rerollButton, findsNothing);
    });

    testWidgets('demo mode hides it even when wired', (tester) async {
      await _pumpCase(tester, onReroll: (_) async => null, demoMode: true);
      await _spinToReveal(tester);

      expect(find.text('UNBOXED'), findsOneWidget);
      expect(_rerollButton, findsNothing);
    });
  });

  group('rerolling', () {
    testWidgets('a successful reroll re-spins to the NEW result', (
      tester,
    ) async {
      var calls = 0;
      String? rerolledId;
      await _pumpCase(
        tester,
        onReroll: (id) async {
          calls++;
          rerolledId = id;
          return {'id': id, 'type': 'ENERGY_GEL', 'rarity': 'RARE'};
        },
      );
      await _spinToReveal(tester);
      expect(find.text('UNBOXED'), findsOneWidget);

      await tester.tap(_rerollButton);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(calls, 1);
      expect(rerolledId, 'pu-1');

      // The reel re-arms so the user watches their reroll land.
      expect(find.text('UNBOXED'), findsNothing);
      expect(find.text('SWIPE OR TAP'), findsOneWidget);

      await _spinToReveal(tester);

      // Landed again, on the NEW powerup — and no second server roll.
      expect(find.text('UNBOXED'), findsOneWidget);
      expect(calls, 1);
      // One reroll per box: the button is gone for good.
      expect(_rerollButton, findsNothing);
    });

    // 2026-08-10: the post-reroll swipe used to go back through _rollResult and
    // fire a SECOND POST /open for a powerup that is no longer a box — in prod
    // a 400 and a bogus "Failed to open mystery box" toast over a good reroll.
    testWidgets('the post-reroll swipe spins to the reroll without a second '
        'server open', (tester) async {
      var opens = 0;
      final revealed = <Map<String, dynamic>>[];
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: CaseOpeningScreen(
            openMysteryBox: () async {
              opens++;
              return _openResult();
            },
            onReroll: (id) async =>
                {'id': id, 'type': 'COMPRESSION_SOCKS', 'rarity': 'RARE'},
            onRevealed: revealed.add,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await _spinToReveal(tester);
      expect(opens, 1);

      await tester.tap(_rerollButton);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await _spinToReveal(tester);

      // Landed on the REROLLED type — no second roll request went out, so the
      // original type cannot have been re-fetched over it.
      expect(opens, 1);
      expect(find.text('UNBOXED'), findsOneWidget);
      expect(find.text('Compression Socks'), findsOneWidget);
      expect(find.text('Protein Shake'), findsNothing);

      // And the host's inventory hook got the POST-reroll outcome (same row
      // id) — not a stale copy of the original roll.
      expect(revealed.length, 2);
      final second =
          (revealed.last['result'] as Map<String, dynamic>?) ?? revealed.last;
      expect(second['id'], 'pu-1');
      expect(second['type'], 'COMPRESSION_SOCKS');
      expect(second['rarity'], 'RARE');
      expect(second['autoActivated'], false);
    });

    testWidgets('backing out of the ad keeps the original result', (
      tester,
    ) async {
      await _pumpCase(tester, onReroll: (_) async => null);
      await _spinToReveal(tester);
      await tester.tap(_rerollButton);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Still revealed, still offering the reroll (no credit was spent).
      expect(find.text('UNBOXED'), findsOneWidget);
      expect(_rerollButton, findsOneWidget);
      final button = tester.widget<PillButton>(_rerollButton);
      expect(button.loading, isFalse);
    });

    testWidgets('a throwing reroll does not wedge the spinner', (tester) async {
      await _pumpCase(
        tester,
        onReroll: (_) async => throw Exception('network'),
      );
      await _spinToReveal(tester);
      await tester.tap(_rerollButton);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(tester.widget<PillButton>(_rerollButton).loading, isFalse);
    });
  });

  group('the button must not leak to other reels', () {
    // ui-test-planner risk 4.
    testWidgets('MultiCaseOpeningScreen (OPEN ALL) has no reroll', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: MultiCaseOpeningScreen(
            boxCount: 2,
            openAll: () async => [
              {'powerupId': 'a', 'type': 'PROTEIN_SHAKE', 'rarity': 'COMMON'},
              {'powerupId': 'b', 'type': 'ENERGY_GEL', 'rarity': 'RARE'},
            ],
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(_rerollButton, findsNothing);
      expect(find.text('REROLL · WATCH AD'), findsNothing);
    });

    // Risk 4 again: the daily-reward reel is a hand-forked copy of the case
    // chrome. A structural guard is the honest test here — it must not import
    // or construct CaseOpeningScreen, so it cannot inherit the button.
    test('the daily-reward reel does not reuse CaseOpeningScreen', () {
      // Guarded at the source level rather than by pumping the whole daily
      // reward screen, which needs a backend + ad controller.
      const path = 'lib/screens/daily_reward_screen.dart';
      final source = _readSource(path);
      expect(
        source.contains('CaseOpeningScreen('),
        isFalse,
        reason:
            'daily_reward_screen is a hand-forked reel; if it ever starts '
            'constructing CaseOpeningScreen it would inherit the reroll '
            'button. Pass onReroll: null explicitly if that changes.',
      );
      expect(source.contains('onReroll'), isFalse);
    });
  });

  group('demo/tutorial fixtures must not advertise boxReroll', () {
    // ui-test-planner risk 5.
    test('the demo engine progress payload has no boxReroll', () {
      final engine = DemoRaceEngine(
        myUserId: 'me',
        myDisplayName: 'Rohan',
        myAccessories: const [],
      );
      final progress = engine.raceProgress(DateTime.now());
      final powerupData = progress['powerupData'] as Map<String, dynamic>;
      expect(powerupData.containsKey('boxReroll'), isFalse);
      expect(powerupData['boxReroll'], isNull);
    });

    test('the tutorial preview payloads have no boxReroll', () {
      final detail = tutorialPreviewRaceDetail();
      expect(detail.toString().contains('boxReroll'), isFalse);
    });
  });
  group('the reroll request carries localDate (fix 1)', () {
    testWidgets(
      'the SAME localDate as the ad grant is posted, and is stable across '
      'AD_NOT_VERIFIED retries',
      (tester) async {
        final api = _RerollStubApi(failFirst: 2);
        final ad = _FakeAdController();

        await _pumpRaceDetail(tester, api: api, ad: ad, boxReroll: true);
        await _openBoxAndReveal(tester);

        expect(_rerollButton, findsOneWidget);
        await tester.tap(_rerollButton);
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(seconds: 1));
        }

        // Three attempts: two AD_NOT_VERIFIED, then success.
        expect(api.rerollCalls, 3);
        expect(api.localDates, hasLength(3));
        // Non-empty, YYYY-MM-DD, and identical on every retry — a retry loop
        // that recomputed the date could cross local midnight and orphan the
        // grant.
        for (final d in api.localDates) {
          expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d), isTrue);
        }
        expect(api.localDates.toSet(), hasLength(1));
        // And it matches the date the ad grant was minted with.
        expect(api.localDates.first, ad.lastLocalDate);

        await _teardownRace(tester);
      },
    );

    testWidgets('no ad reward earned => no reroll request at all', (
      tester,
    ) async {
      final api = _RerollStubApi();
      final ad = _FakeAdController(earn: false);

      await _pumpRaceDetail(tester, api: api, ad: ad, boxReroll: true);
      await _openBoxAndReveal(tester);
      await tester.tap(_rerollButton);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(api.rerollCalls, 0);
      await _teardownRace(tester);
    });

    testWidgets('the button is hidden when the backend omits boxReroll', (
      tester,
    ) async {
      final api = _RerollStubApi();
      await _pumpRaceDetail(
        tester,
        api: api,
        ad: _FakeAdController(),
        boxReroll: false,
      );
      await _openBoxAndReveal(tester);

      expect(_rerollButton, findsNothing);
      await _teardownRace(tester);
    });
  });

  group('review fix 5 — the reroll ad unit has NO fallback', () {
    test('an absent define disables the surface instead of borrowing', () {
      // This suite runs with no --dart-define, which is exactly the staging /
      // dev configuration. The reroll unit must resolve EMPTY and report
      // unsupported — never silently fall through to the extra-spin unit,
      // which would blend two placements into one AdMob reporting line and
      // put the feature on builds the spec says should not have it.
      expect(AdService.boxRerollAdUnitId, isEmpty);
      expect(AdService.boxRerollSupported, isFalse);
    });

    test('the powerup-unlock unit DOES still fall back (unchanged)', () {
      // Guards against someone "fixing" both getters the same way: only the
      // reroll unit is meant to be strict.
      expect(AdService.powerupUnlockAdUnitId, isNotNull);
    });

    testWidgets(
      'with no define and no injected controller, the button stays hidden '
      'even when the backend advertises boxReroll',
      (tester) async {
        final api = _RerollStubApi();
        tester.view.physicalSize = const Size(1170, 2532);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        api.boxReroll = true;
        final auth = await _rerollAuth();
        await tester.pumpWidget(
          MaterialApp(
            home: RaceDetailScreen(
              authService: auth,
              raceId: 'race-1',
              backendApiService: api,
              // No boxRerollAdController -> production path -> needs the define.
            ),
          ),
        );
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await _openBoxAndReveal(tester);

        expect(_rerollButton, findsNothing);
        expect(api.rerollCalls, 0);
        await _teardownRace(tester);
      },
    );
  });

}

String _readSource(String relativePath) {
  // ignore: avoid_slow_async_io
  final file = File(relativePath);
  return file.readAsStringSync();
}
