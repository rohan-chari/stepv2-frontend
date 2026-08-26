// Feature batch 2026-08-10 (part 2) — Item 1 (REROLL ALL after OPEN ALL) and
// Item 4 (reroll must not repopulate the inventory before the reel lands).
//
// Pumps the REAL MultiCaseOpeningScreen and the REAL RaceDetailScreen against
// stubbed HTTP/ad layers, so every assertion is about what a user sees.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/demo/demo_race_api_service.dart';
import 'package:step_tracker/demo/demo_race_engine.dart';
import 'package:step_tracker/screens/multi_case_opening_screen.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/ad_service.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/item_slot.dart';
import 'package:step_tracker/widgets/pill_button.dart';

Finder get _rerollAllButton => find.byKey(const Key('open-all-reroll-button'));
Finder get _rerollAllDisclaimer =>
    find.byKey(const Key('open-all-reroll-disclaimer'));

List<Map<String, dynamic>> _openResults(int n) => [
  for (var i = 0; i < n; i++)
    {
      'powerupId': 'p$i',
      'type': 'PROTEIN_SHAKE',
      'rarity': 'COMMON',
      'autoActivated': false,
      'queued': false,
    },
];

/// Runs the whole reel bank from the OPEN ALL tap to the summary card.
Future<void> _openAllToSummary(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(PillButton, 'OPEN ALL'));
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 4200));
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump();
  // The summary card scales in over 450ms; before it finishes every child
  // collapses onto the same point and cannot be hit-tested.
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _pumpMulti(
  WidgetTester tester, {
  required int count,
  Future<List<Map<String, dynamic>>?> Function(List<String>)? onRerollAll,
  void Function(List<Map<String, dynamic>>)? onResults,
  List<Map<String, dynamic>>? results,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: MultiCaseOpeningScreen(
        boxCount: count,
        onRerollAll: onRerollAll,
        onResults: onResults,
        openAll: () async => results ?? _openResults(count),
      ),
    ),
  );
  await tester.pump();
}

// ── RaceDetailScreen harness ───────────────────────────────────────────────

class _FakeAdController implements ExtraSpinAdController {
  _FakeAdController({this.earn = true});

  final bool earn;
  String? lastLocalDate;
  int loads = 0;
  int shows = 0;
  bool _loaded = false;

  @override
  bool get isSupported => true;

  @override
  bool get isReady => _loaded;

  @override
  Future<void> load({required String userId, required String localDate}) async {
    loads++;
    lastLocalDate = localDate;
    _loaded = true;
  }

  @override
  Future<bool> showAndAwaitReward() async {
    shows++;
    _loaded = false;
    return earn;
  }

  @override
  void dispose() {}
}

class _BatchStubApi extends BackendApiService {
  _BatchStubApi({this.batchFailFirst = 0});

  /// How many leading batch attempts answer 409 AD_NOT_VERIFIED (SSV lag).
  final int batchFailFirst;

  /// null = key omitted (older backend). true/false = advertised value.
  bool? boxRerollBatch = true;
  bool boxReroll = true;

  int progressCalls = 0;
  int batchCalls = 0;
  int singleRerollCalls = 0;
  final List<List<String>> batchIds = [];
  final List<String> batchLocalDates = [];

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
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
  }) async {
    progressCalls++;
    return {
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
          {'id': 'box-2', 'type': 'MYSTERY_BOX', 'status': 'MYSTERY_BOX'},
        ],
        'powerupSlots': 3,
        'queuedBoxCount': 0,
        'activeEffects': const [],
        if (boxReroll) 'boxReroll': true,
        if (boxRerollBatch != null) 'boxRerollBatch': boxRerollBatch,
      },
    };
  }

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
  Future<Map<String, dynamic>> openMysteryBoxBatch({
    required String identityToken,
    required String raceId,
    required List<String> powerupIds,
    bool includeQueued = true,
    int maxCount = 20,
  }) async => {
    'results': [
      for (final id in powerupIds)
        {
          'powerupId': id,
          'type': 'PROTEIN_SHAKE',
          'rarity': 'COMMON',
          'autoActivated': false,
          'queued': false,
        },
    ],
  };

  @override
  Future<Map<String, dynamic>> openMysteryBox({
    required String identityToken,
    required String raceId,
    required String powerupId,
  }) async => const {
    'result': {
      'id': 'box-1',
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
    singleRerollCalls++;
    return const {
      'id': 'box-1',
      'type': 'ENERGY_GEL',
      'rarity': 'RARE',
      'rerolled': true,
    };
  }

  @override
  Future<Map<String, dynamic>> rerollPowerupBatch({
    required String identityToken,
    required String raceId,
    required List<String> powerupIds,
    required String localDate,
  }) async {
    batchCalls++;
    batchIds.add(List<String>.from(powerupIds));
    batchLocalDates.add(localDate);
    if (batchCalls <= batchFailFirst) {
      throw const ApiException(
        'not verified',
        statusCode: 409,
        code: 'AD_NOT_VERIFIED',
      );
    }
    return {
      'results': [
        for (final id in powerupIds)
          {
            'powerupId': id,
            'type': 'ENERGY_GEL',
            'rarity': 'RARE',
            'rerolled': true,
          },
      ],
      'rerolledCount': powerupIds.length,
    };
  }
}

Future<AuthService> _auth() async {
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
  required _BatchStubApi api,
  _FakeAdController? ad,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final auth = await _auth();
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

/// Taps OPEN ALL in the POWERUPS header and drives the bank to the summary.
Future<void> _openAllFromRace(WidgetTester tester) async {
  final openAll = find.text('OPEN ALL');
  await tester.ensureVisible(openAll.first);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(openAll.first);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  // Now the overlay's own OPEN ALL trigger.
  await _openAllToSummary(tester);
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.bara.steps',
      version: '2.2.4',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('Item 1 — the summary card gates REROLL ALL', () {
    testWidgets('no onRerollAll (older backend / Android) → the summary is '
        'byte-identical to today', (tester) async {
      await _pumpMulti(tester, count: 2);
      await _openAllToSummary(tester);

      expect(find.text('YOU OPENED 2'), findsOneWidget);
      expect(_rerollAllButton, findsNothing);
      expect(_rerollAllDisclaimer, findsNothing);
    });

    testWidgets('wired → Continue sits above REROLL ALL with the disclaimer '
        'directly beneath reroll', (tester) async {
      await _pumpMulti(tester, count: 3, onRerollAll: (_) async => null);
      await _openAllToSummary(tester);

      expect(_rerollAllButton, findsOneWidget);
      expect(_rerollAllDisclaimer, findsOneWidget);
      expect(
        tester.widget<Text>(_rerollAllDisclaimer).data,
        'Watch an ad to reroll ALL of these boxes. Every roll is replaced. '
        'The new rolls are final.',
      );

      final buttonTop = tester.getTopLeft(_rerollAllButton).dy;
      final disclaimerTop = tester.getTopLeft(_rerollAllDisclaimer).dy;
      final continueTop = tester
          .getTopLeft(find.widgetWithText(PillButton, 'Continue'))
          .dy;
      expect(buttonTop, greaterThan(continueTop));
      expect(disclaimerTop, greaterThan(buttonTop));
    });

    testWidgets('nothing rerollable (all auto-activated) → no button', (
      tester,
    ) async {
      await _pumpMulti(
        tester,
        count: 2,
        onRerollAll: (_) async => null,
        results: [
          {
            'powerupId': 'p0',
            'type': 'FANNY_PACK',
            'rarity': 'RARE',
            'autoActivated': true,
          },
          {
            'powerupId': 'p1',
            'type': 'FANNY_PACK',
            'rarity': 'RARE',
            'autoActivated': true,
          },
        ],
      );
      await _openAllToSummary(tester);

      expect(find.text('YOU OPENED 2'), findsOneWidget);
      expect(_rerollAllButton, findsNothing);
    });

    testWidgets('over the batch cap → the disclaimer says N, not ALL', (
      tester,
    ) async {
      await _pumpMulti(tester, count: 10, onRerollAll: (_) async => null);
      await _openAllToSummary(tester);

      expect(
        tester.widget<Text>(_rerollAllDisclaimer).data,
        startsWith('Watch an ad to reroll 8 of these boxes.'),
      );
    });
  });

  group('Item 1 — rerolling the bank', () {
    testWidgets('one tap re-spins every reel and lands on the NEW types', (
      tester,
    ) async {
      final handedBack = <List<Map<String, dynamic>>>[];
      List<String>? requested;

      await _pumpMulti(
        tester,
        count: 2,
        onResults: (r) =>
            handedBack.add(r.map((e) => Map<String, dynamic>.from(e)).toList()),
        onRerollAll: (ids) async {
          requested = ids;
          return [
            for (final id in ids)
              {'powerupId': id, 'type': 'RED_CARD', 'rarity': 'RARE'},
          ];
        },
      );
      await _openAllToSummary(tester);

      expect(handedBack, hasLength(1));
      expect(handedBack.first.first['type'], 'PROTEIN_SHAKE');

      await tester.tap(_rerollAllButton);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(requested, ['p0', 'p1']);
      // Back to the reel bank — the user watches the new rolls land.
      expect(find.text('YOU OPENED 2'), findsNothing);

      await tester.pump(const Duration(milliseconds: 4200));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // The summary is back with the new results, and the button is spent.
      expect(find.text('YOU OPENED 2'), findsOneWidget);
      expect(_rerollAllButton, findsNothing);
      expect(_rerollAllDisclaimer, findsNothing);
      expect(find.text('Red Card'), findsNWidgets(2));

      // onResults fired a SECOND time, carrying the rerolled types, so the
      // host's optimistic inventory is corrected.
      expect(handedBack, hasLength(2));
      expect(handedBack.last.every((r) => r['type'] == 'RED_CARD'), isTrue);
    });

    testWidgets('an unmatched powerupId keeps its ORIGINAL result', (
      tester,
    ) async {
      await _pumpMulti(
        tester,
        count: 2,
        onRerollAll: (ids) async => [
          // Only the first id comes back; the second was skipped/omitted.
          {'powerupId': 'p0', 'type': 'RED_CARD', 'rarity': 'RARE'},
        ],
      );
      await _openAllToSummary(tester);
      await tester.tap(_rerollAllButton);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 4200));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Red Card'), findsOneWidget);
      expect(find.text('Protein Shake'), findsOneWidget);
    });

    testWidgets('backing out of the ad leaves the summary and the button '
        'exactly as they were', (tester) async {
      await _pumpMulti(tester, count: 2, onRerollAll: (_) async => null);
      await _openAllToSummary(tester);

      await tester.tap(_rerollAllButton);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('YOU OPENED 2'), findsOneWidget);
      expect(_rerollAllButton, findsOneWidget);
      expect(tester.widget<PillButton>(_rerollAllButton).loading, isFalse);
      expect(tester.widget<PillButton>(_rerollAllButton).onPressed, isNotNull);
      expect(find.text('Protein Shake'), findsNWidgets(2));
    });

    testWidgets('while the ad is up the summary is undismissable and '
        'Continue is disabled', (tester) async {
      final gate = Completer<List<Map<String, dynamic>>?>();
      await _pumpMulti(tester, count: 2, onRerollAll: (_) => gate.future);
      await _openAllToSummary(tester);

      await tester.tap(_rerollAllButton);
      await tester.pump();

      expect(tester.widget<PillButton>(_rerollAllButton).loading, isTrue);
      expect(
        tester
            .widget<PillButton>(find.widgetWithText(PillButton, 'Continue'))
            .onPressed,
        isNull,
      );
      expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);

      gate.complete(null);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isTrue);
    });

    testWidgets('a throwing reroll does not wedge the spinner', (tester) async {
      await _pumpMulti(
        tester,
        count: 2,
        onRerollAll: (_) async => throw Exception('network'),
      );
      await _openAllToSummary(tester);
      await tester.tap(_rerollAllButton);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(tester.widget<PillButton>(_rerollAllButton).loading, isFalse);
      expect(find.text('YOU OPENED 2'), findsOneWidget);
    });
  });

  group('Item 1 — race detail feature detection', () {
    testWidgets('boxRerollBatch: true + an injected controller → the button '
        'renders and posts the batch', (tester) async {
      final api = _BatchStubApi();
      final ad = _FakeAdController();
      await _pumpRaceDetail(tester, api: api, ad: ad);
      await _openAllFromRace(tester);

      expect(_rerollAllButton, findsOneWidget);
      expect(ad.loads, 1, reason: 'Open All summary warms before the tap');
      await tester.tap(_rerollAllButton);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(ad.shows, 1);
      expect(api.batchCalls, 1);
      expect(api.batchIds.single, ['box-1', 'box-2']);
      // The SAME localDate the ad grant was minted with.
      expect(api.batchLocalDates.single, ad.lastLocalDate);
      expect(
        RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(api.batchLocalDates.single),
        isTrue,
      );

      await _teardown(tester);
    });

    testWidgets('the batch retries AD_NOT_VERIFIED with a stable localDate', (
      tester,
    ) async {
      final api = _BatchStubApi(batchFailFirst: 2);
      final ad = _FakeAdController();
      await _pumpRaceDetail(tester, api: api, ad: ad);
      await _openAllFromRace(tester);

      await tester.tap(_rerollAllButton);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(seconds: 1));
      }

      expect(api.batchCalls, 3);
      expect(api.batchLocalDates.toSet(), hasLength(1));
      await _teardown(tester);
    });

    testWidgets('boxRerollBatch absent (older backend) → no button', (
      tester,
    ) async {
      final api = _BatchStubApi()..boxRerollBatch = null;
      await _pumpRaceDetail(tester, api: api, ad: _FakeAdController());
      await _openAllFromRace(tester);

      expect(find.text('YOU OPENED 2'), findsOneWidget);
      expect(_rerollAllButton, findsNothing);
      expect(_rerollAllDisclaimer, findsNothing);
      await _teardown(tester);
    });

    testWidgets('backing out of the ad fires no batch request at all', (
      tester,
    ) async {
      final api = _BatchStubApi();
      final ad = _FakeAdController(earn: false);
      await _pumpRaceDetail(tester, api: api, ad: ad);
      await _openAllFromRace(tester);

      await tester.tap(_rerollAllButton);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(ad.shows, 1);
      expect(api.batchCalls, 0);
      expect(_rerollAllButton, findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('boxRerollBatch: false → no button', (tester) async {
      final api = _BatchStubApi()..boxRerollBatch = false;
      await _pumpRaceDetail(tester, api: api, ad: _FakeAdController());
      await _openAllFromRace(tester);

      expect(_rerollAllButton, findsNothing);
      await _teardown(tester);
    });

    testWidgets('no ad unit and no injected controller → no button even when '
        'the backend advertises it', (tester) async {
      final api = _BatchStubApi();
      await _pumpRaceDetail(tester, api: api);
      await _openAllFromRace(tester);

      expect(AdService.boxRerollSupported, isFalse);
      expect(_rerollAllButton, findsNothing);
      expect(api.batchCalls, 0);
      await _teardown(tester);
    });
  });

  group('Item 1 — demo/tutorial guards', () {
    // architect R3: an un-overridden call site is a live HTTPS request against
    // prod with a fabricated race id, whether or not today's UI can reach it.
    test(
      'DemoRaceApiService overrides rerollPowerupBatch (no network)',
      () async {
        final service = DemoRaceApiService(
          DemoRaceEngine(
            myUserId: 'me',
            myDisplayName: 'Rohan',
            myAccessories: const [],
          ),
        );
        final result = await service.rerollPowerupBatch(
          identityToken: 't',
          raceId: 'demo-race',
          powerupIds: const ['a'],
          localDate: '2026-08-10',
        );
        expect(result, isEmpty);
      },
    );

    test(
      'the demo engine progress payload never advertises boxRerollBatch',
      () {
        final engine = DemoRaceEngine(
          myUserId: 'me',
          myDisplayName: 'Rohan',
          myAccessories: const [],
        );
        final powerupData =
            engine.raceProgress(DateTime.now())['powerupData']
                as Map<String, dynamic>;
        expect(powerupData.containsKey('boxRerollBatch'), isFalse);
      },
    );
  });

  group('Item 4 — the reroll must not repopulate the inventory early', () {
    testWidgets('no progress refetch between the reroll response and the '
        'reel landing (single box)', (tester) async {
      final api = _BatchStubApi();
      final ad = _FakeAdController();
      await _pumpRaceDetail(tester, api: api, ad: ad);

      // Open one box the normal way and let its reel land.
      final boxSlot = find
          .byWidgetPredicate(
            (w) => w is ItemSlot && w.state == ItemSlotState.mysteryBox,
          )
          .first;
      await tester.ensureVisible(boxSlot);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(boxSlot);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.text('SWIPE OR TAP'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 4100));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 600));

      final before = api.progressCalls;
      await tester.tap(find.byKey(const Key('case-reroll-button')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // The reroll has resolved (the reel re-armed) but the overlay is still
      // up: refetching here would swap the inventory row behind the reel and
      // spoil the reveal.
      expect(api.singleRerollCalls, 1);
      expect(find.text('SWIPE OR TAP'), findsOneWidget);
      expect(api.progressCalls, before);

      await _teardown(tester);
    });

    testWidgets('no progress refetch between the BATCH reroll response and '
        'the reels landing', (tester) async {
      final api = _BatchStubApi();
      final ad = _FakeAdController();
      await _pumpRaceDetail(tester, api: api, ad: ad);
      await _openAllFromRace(tester);

      final before = api.progressCalls;
      await tester.tap(_rerollAllButton);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(api.batchCalls, 1);
      // Reels are re-spinning; the inventory behind them must be untouched.
      expect(find.text('YOU OPENED 2'), findsNothing);
      expect(api.progressCalls, before);

      await _teardown(tester);
    });
  });
}
