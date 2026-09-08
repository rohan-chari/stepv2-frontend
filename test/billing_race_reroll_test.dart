import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/billing.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/billing_controller.dart';
import 'package:step_tracker/widgets/billing_scope.dart';
import 'package:step_tracker/widgets/item_slot.dart';
import 'package:step_tracker/widgets/pill_button.dart';

class _RerollStubApi extends BackendApiService {
  _RerollStubApi();

  /// How many leading attempts answer 409 AD_NOT_VERIFIED (SSV lag).
  final int failFirst = 0;

  /// Whether the progress payload advertises the feature; set by the pump
  /// helper before the screen loads.
  bool boxReroll = true;
  List<Map<String, dynamic>>? inventory;

  int rerollCalls = 0;
  final List<String> localDates = [];

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
      'inventory':
          inventory ??
          const [
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

class _Billing extends BillingController {
  String identity = 'user-1';
  bool supported = true;
  int calls = 0;
  List<String> selectedIds = [];
  RerollFunding? funding;
  @override
  String get userId => identity;
  @override
  bool get isPreview => true;
  @override
  bool supportsRace(String raceId) => supported && raceId == 'race-1';
  @override
  BillingSnapshot get snapshot =>
      const BillingSnapshot(coins: 100, paidCredits: 2);
  @override
  Future<BillingRerollResult> reroll({
    required String raceId,
    required List<String> ids,
    required RerollFunding funding,
  }) async {
    calls++;
    selectedIds = List.of(ids);
    this.funding = funding;
    return const BillingRerollResult(
      success: false,
      message: 'Preview retry needed',
    );
  }

  @override
  Future<BillingResult> buyCoins(CoinPackOffer pack) async =>
      throw UnimplementedError();
  @override
  Future<BillingResult> startTrial(BillingPlan plan) async =>
      throw UnimplementedError();
  @override
  Future<BillingResult> subscribe(BillingPlan plan) async =>
      throw UnimplementedError();
  @override
  Future<BillingResult> restore() async => throw UnimplementedError();
  @override
  Future<BillingResult> cancelRenewal() async => throw UnimplementedError();
}

Future<void> _launch(
  WidgetTester tester,
  _Billing billing, {
  String type = 'PROTEIN_SHAKE',
  bool demo = false,
  int boxes = 0,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final auth = await _rerollAuth();
  addTearDown(auth.dispose);
  final api = _RerollStubApi()
    ..boxReroll = false
    ..inventory = [
      {
        'id': 'held-1',
        'type': type,
        'rarity': 'COMMON',
        'status': 'HELD',
        'upgradeLevel': 0,
        'usedAt': null,
        'rerolledAt': null,
      },
    ];
  if (boxes > 0) {
    api.inventory = [
      for (var i = 0; i < boxes; i++)
        {'id': 'box-$i', 'type': 'MYSTERY_BOX', 'status': 'MYSTERY_BOX'},
    ];
  }
  await tester.pumpWidget(
    BillingScope(
      controller: billing,
      child: MaterialApp(
        home: RaceDetailScreen(
          authService: auth,
          raceId: 'race-1',
          backendApiService: api,
          demoMode: demo,
        ),
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (boxes > 0) return;
  final held = find.byWidgetPredicate(
    (w) => w is ItemSlot && w.state == ItemSlotState.held,
  );
  await tester.ensureVisible(held);
  await tester.tap(held);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  setUp(
    () => PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.bara.steps',
      version: '2.2.0',
      buildNumber: '1',
      buildSignature: '',
    ),
  );
  for (final type in ['PROTEIN_SHAKE', 'POCKET_WATCH']) {
    testWidgets(
      '$type held reroll asks for funding and cancel spends nothing',
      (tester) async {
        final billing = _Billing();
        addTearDown(billing.dispose);
        await _launch(tester, billing, type: type);
        expect(find.byKey(const Key('stash-held-reroll')), findsOneWidget);
        expect(find.text('REROLL · WATCH AD'), findsNothing);
        await tester.drag(
          find
              .descendant(
                of: find.byType(BottomSheet),
                matching: find.byType(SingleChildScrollView),
              )
              .first,
          const Offset(0, -650),
        );
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byKey(const Key('stash-held-reroll')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byKey(const Key('reroll-funding-coins')), findsOneWidget);
        expect(find.byKey(const Key('reroll-funding-credits')), findsOneWidget);
        expect(find.byKey(const Key('reroll-funding-ad')), findsNothing);
        await tester.tap(find.text('CANCEL'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(billing.calls, 0);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'paid selection reaches controller and failure does not retire item',
    (tester) async {
      final billing = _Billing();
      addTearDown(billing.dispose);
      await _launch(tester, billing);
      await tester.drag(
        find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(SingleChildScrollView),
            )
            .first,
        const Offset(0, -650),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.byKey(const Key('stash-held-reroll')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const Key('reroll-funding-coins')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(billing.calls, 1);
      expect(billing.funding, RerollFunding.coins);
      final held = find.byWidgetPredicate(
        (w) => w is ItemSlot && w.state == ItemSlotState.held,
      );
      await tester.tap(held);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('stash-held-reroll')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final count in [1, 2]) {
    testWidgets(
      '$count revealed boxes route through the shared funding selector',
      (tester) async {
        final billing = _Billing();
        addTearDown(billing.dispose);
        await _launch(tester, billing, boxes: count);
        if (count == 1) {
          final box = find.byWidgetPredicate(
            (w) => w is ItemSlot && w.state == ItemSlotState.mysteryBox,
          );
          await tester.ensureVisible(box);
          await tester.pump(const Duration(milliseconds: 100));
          await tester.tap(box);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
          await tester.tap(find.text('SWIPE OR TAP'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 4100));
          await tester.pump(const Duration(milliseconds: 700));
          await tester.pump(const Duration(milliseconds: 600));
        } else {
          await tester.ensureVisible(find.text('OPEN ALL').first);
          await tester.pump(const Duration(milliseconds: 100));
          await tester.tap(find.text('OPEN ALL').first);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
          await tester.tap(find.widgetWithText(PillButton, 'OPEN ALL'));
          await tester.pump();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 4200));
          await tester.pump(const Duration(milliseconds: 700));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
        }
        final button = find.byKey(
          Key(count == 1 ? 'case-reroll-button' : 'open-all-reroll-button'),
        );
        expect(button, findsOneWidget);
        await tester.tap(button);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byKey(const Key('reroll-funding-coins')), findsOneWidget);
        if (count > 1) {
          expect(
            find.text('One action rerolls all eligible boxes.'),
            findsOneWidget,
          );
        }
        await tester.tap(find.byKey(const Key('reroll-funding-credits')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(billing.calls, 1);
        expect(billing.selectedIds, hasLength(count));
        expect(billing.funding, RerollFunding.credits);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  for (final mode in ['different account', 'unsupported race', 'demo']) {
    testWidgets('$mode never exposes paid rerolls', (tester) async {
      final billing = _Billing();
      addTearDown(billing.dispose);
      if (mode == 'different account') billing.identity = 'someone-else';
      if (mode == 'unsupported race') billing.supported = false;
      await _launch(tester, billing, demo: mode == 'demo');
      expect(find.byKey(const Key('stash-held-reroll')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
