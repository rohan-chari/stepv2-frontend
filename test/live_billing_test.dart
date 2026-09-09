import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/billing.dart';
import 'package:step_tracker/screens/bara_plus_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/live_billing_controller.dart';
import 'package:step_tracker/services/store_billing_client.dart';
import 'package:step_tracker/widgets/coin_pack_offers.dart';
import 'package:step_tracker/widgets/bara_plus_card.dart';
import 'package:step_tracker/widgets/reroll_payment_sheet.dart';

class TestAuth extends AuthService {
  String id = 'a';
  int wallet = 100;
  @override
  String? get userId => id;
  @override
  String? get authToken => 'token-$id';
  @override
  int get coins => wallet;
  @override
  Future<void> updateCoins(int coins) async {
    wallet = coins;
    notifyListeners();
  }

  void switchUser() {
    id = 'b';
    notifyListeners();
  }
}

class TestApi extends BackendApiService {
  bool available = true;
  Map<String, dynamic>? membership;
  int? fixedCoins;
  bool oldBackend = false;
  bool perAccount = false;
  Map<String, dynamic>? rawBootstrap;
  bool pending = false;
  int syncCalls = 0;
  int serverCoins = 100;
  final rerollResponses = <String, Map<String, dynamic>>{};
  bool timeoutReroll = false;
  final keys = <String>[];
  final syncHints = <String?>[];
  final syncTokens = <String>[];
  Map<String, dynamic> data({String identityToken = 'token-a'}) => {
    'available': available,
    'contract': 'bara-billing-v1',
    'identity': {
      'appUserId': perAccount && identityToken == 'token-b'
          ? 'identity-b'
          : 'identity-a',
      'environment': 'production',
    },
    'products': [
      {
        'id': 'coins_500',
        'storeProductId': 'coin',
        'kind': 'coins',
        'coins': 500,
      },
      {
        'id': 'plus_monthly',
        'storeProductId': 'monthly',
        'kind': 'subscription',
        'plan': 'monthly',
        'coins': 500,
      },
      {
        'id': 'plus_annual',
        'storeProductId': 'annual',
        'kind': 'subscription',
        'plan': 'annual',
        'coins': 6000,
      },
    ],
    'membership': membership ?? {'status': 'free'},
    'coins':
        fixedCoins ??
        (perAccount && identityToken == 'token-b' ? 900 : serverCoins),
    'credits': {'paid': 0, 'trial': 0},
    'reroll': {'supported': true, 'coinCost': 50, 'maxItems': 8},
    'termsUrl': 'https://example.com/terms',
    'privacyUrl': 'https://example.com/privacy',
  };
  @override
  Future<Map<String, dynamic>> fetchBillingBootstrap({
    required String identityToken,
    required String platform,
  }) async {
    if (oldBackend) throw const ApiException('Not found', statusCode: 404);
    return rawBootstrap ?? data(identityToken: identityToken);
  }

  @override
  Future<Map<String, dynamic>> syncBilling({
    required String identityToken,
    required String platform,
    String? transactionId,
  }) async {
    syncHints.add(transactionId);
    syncTokens.add(identityToken);
    return {
      ...data(identityToken: identityToken),
      'status': pending ? 'pending' : 'complete',
      'coins':
          fixedCoins ??
          (perAccount && identityToken == 'token-b'
              ? 900
              : ++syncCalls == 1 || pending
              ? 100
              : 600),
    };
  }

  @override
  Future<Map<String, dynamic>> purchaseBoxReroll({
    required String identityToken,
    required String raceId,
    required List<String> powerupIds,
    required String funding,
    required String idempotencyKey,
    int? expectedCoinCost,
  }) async {
    keys.add(idempotencyKey);
    if (timeoutReroll) throw Exception('network');
    if (rerollResponses[idempotencyKey] case final Map<String, dynamic> saved) {
      return saved;
    }
    serverCoins = 50;
    return rerollResponses[idempotencyKey] = {
      'results': [
        {
          'powerupId': powerupIds.first,
          'type': 'GHOST_PEPPER',
          'rarity': 'EPIC',
          'rerolled': true,
        },
      ],
      'coins': 50,
      'credits': {'paid': 0, 'trial': 0},
    };
  }
}

class TestStore extends StoreBillingClient {
  int purchases = 0;
  bool eligible = false;
  bool pendingError = false;
  bool uncertainError = false;
  bool baselineFails = false;
  List<String> nativeTransactions = ['old-transaction'];
  String identity = '';
  final purchaseIdentities = <String>[];
  Completer<String?>? purchaseCompleter;
  final planChanges = <List<String>>[];
  bool rejectPlanChange = false;
  bool restoreAccountMismatch = false;
  @override
  Future<void> changePlan({
    required String oldProductId,
    required String newProductId,
  }) async {
    planChanges.add([oldProductId, newProductId]);
    if (rejectPlanChange) {
      throw const StoreBillingException(
        'Plan change cancelled.',
        cancelled: true,
      );
    }
  }

  @override
  Future<List<String>> transactionIds(String productId) async {
    if (baselineFails) throw Exception('Native history unavailable');
    return [...nativeTransactions];
  }

  VoidCallback? duringPurchase;
  @override
  bool get configured => true;
  @override
  Future<void> identify(String identity) async {
    this.identity = identity;
  }

  @override
  Future<List<StoreBillingProduct>> products(
    List<String> coins,
    List<String> subscriptions,
  ) async => [
    const StoreBillingProduct(id: 'coin', price: '€1,09'),
    const StoreBillingProduct(id: 'annual', price: '€54,99'),
    StoreBillingProduct(
      id: 'monthly',
      price: '€5,49',
      trialDays: eligible ? 7 : 0,
    ),
  ];
  @override
  Future<String?> purchase(String productId) async {
    purchases++;
    purchaseIdentities.add(identity);
    if (uncertainError) {
      throw const StoreBillingException(
        'Store connection interrupted.',
        uncertain: true,
      );
    }
    if (pendingError) {
      throw const StoreBillingException(
        'Waiting for store approval.',
        pending: true,
      );
    }
    duringPurchase?.call();
    return purchaseCompleter?.future ?? Future.value('transaction-1');
  }

  @override
  Future<void> restore() async {
    if (restoreAccountMismatch) {
      throw const StoreBillingException(
        'This purchase belongs to another Bara account. Sign in to the original account to restore it.',
        accountMismatch: true,
      );
    }
  }

  @override
  Future<void> manage() async {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'localized offers and noneligible subscribe CTA render on real screens',
    (tester) async {
      final auth = TestAuth(), api = TestApi(), store = TestStore();
      final billing = LiveBillingController(
        auth: auth,
        api: api,
        store: store,
        platform: 'ios',
      );
      addTearDown(billing.dispose);
      await billing.refresh();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CoinPackOffers(controller: billing)),
        ),
      );
      expect(find.text('Buy · €1,09'), findsOneWidget);
      expect(find.textContaining(r'$0.99'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(home: BaraPlusScreen(controller: billing)),
      );
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byKey(const Key('subscribe-bara')),
        500,
      );
      expect(find.text('SUBSCRIBE'), findsOneWidget);
      expect(find.text('TRY 7 DAYS FREE'), findsNothing);
      expect(find.textContaining('€5,49/month'), findsOneWidget);
    },
  );
  testWidgets('missing backend data hides purchase offers without crashing', (
    tester,
  ) async {
    final api = TestApi()..available = false;
    final billing = LiveBillingController(
      auth: TestAuth(),
      api: api,
      store: TestStore(),
      platform: 'ios',
    );
    addTearDown(billing.dispose);
    await billing.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CoinPackOffers(controller: billing)),
      ),
    );
    expect(find.text('Fill your coin pouch'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  test(
    'native purchase remains pending without a local coin grant then reconciles',
    () async {
      final auth = TestAuth(), api = TestApi()..pending = true;
      final billing = LiveBillingController(
        auth: auth,
        api: api,
        store: TestStore(),
        platform: 'ios',
      );
      addTearDown(billing.dispose);
      await billing.refresh();
      final result = await billing.buyCoins(billing.coinPacks.first);
      expect(result.success, isFalse);
      expect(auth.wallet, 100);
      expect(billing.snapshot.operationStatus, BillingOperationStatus.pending);
      api.pending = false;
      await billing.refresh();
      expect(auth.wallet, 600);
    },
  );
  test(
    'purchase completion from previous account never updates new account wallet',
    () async {
      final auth = TestAuth(), store = TestStore();
      final billing = LiveBillingController(
        auth: auth,
        api: TestApi(),
        store: store,
        platform: 'ios',
      );
      addTearDown(billing.dispose);
      await billing.refresh();
      store.duringPurchase = auth.switchUser;
      await billing.buyCoins(billing.coinPacks.first);
      expect(auth.wallet, 100);
    },
  );
  test(
    'reroll retries preserve durable UUID after a timeout and controller recreation',
    () async {
      final auth = TestAuth(), api = TestApi()..timeoutReroll = true;
      var billing = LiveBillingController(
        auth: auth,
        api: api,
        store: TestStore(),
        platform: 'ios',
      );
      await billing.refresh();
      await billing.reroll(
        raceId: 'r',
        ids: ['box'],
        funding: RerollFunding.coins,
      );
      billing.dispose();
      billing = LiveBillingController(
        auth: auth,
        api: api,
        store: TestStore(),
        platform: 'ios',
      );
      addTearDown(billing.dispose);
      await billing.refresh();
      api.timeoutReroll = false;
      final result = await billing.reroll(
        raceId: 'r',
        ids: ['box'],
        funding: RerollFunding.coins,
      );
      expect(result.success, isTrue);
      expect(api.keys.length, 2);
      expect(api.keys[0], api.keys[1]);
      expect(auth.wallet, 50);
    },
  );
  testWidgets(
    'a timed out debit remains retryable when the wallet is now empty',
    (tester) async {
      final auth = TestAuth(), api = TestApi()..timeoutReroll = true;
      final billing = LiveBillingController(
        auth: auth,
        api: api,
        store: TestStore(),
        platform: 'ios',
      );
      addTearDown(billing.dispose);
      await billing.refresh();
      await billing.reroll(
        raceId: 'r',
        ids: ['box'],
        funding: RerollFunding.coins,
      );
      auth.wallet = 0;
      final pending = await billing.pendingReroll(raceId: 'r', ids: ['box']);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showRerollPaymentSheet(
                context,
                controller: billing,
                pendingFunding: pending,
              ),
              child: const Text('OPEN'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      expect(find.text('RETRY PREVIOUS COIN REROLL'), findsOneWidget);
      await tester.tap(find.byKey(const Key('reroll-funding-coins')));
      await tester.pumpAndSettle();
      expect(find.text('RETRY PREVIOUS COIN REROLL'), findsNothing);
    },
  );
  testWidgets('only eligible native offers show free trial and legal links', (
    tester,
  ) async {
    final billing = LiveBillingController(
      auth: TestAuth(),
      api: TestApi(),
      store: TestStore()..eligible = true,
      platform: 'ios',
    );
    addTearDown(billing.dispose);
    await billing.refresh();
    await tester.pumpWidget(
      MaterialApp(home: BaraPlusScreen(controller: billing)),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('start-bara-trial')),
      500,
    );
    expect(find.text('TRY 7 DAYS FREE'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Privacy Policy'), 300);
    expect(find.text('Terms of Use'), findsOneWidget);
  });
  test(
    'replayed historical reroll response cannot overwrite the current wallet',
    () async {
      final auth = TestAuth(), api = TestApi();
      final billing = LiveBillingController(
        auth: auth,
        api: api,
        store: TestStore(),
        platform: 'ios',
      );
      addTearDown(billing.dispose);
      await billing.refresh();
      await billing.reroll(
        raceId: 'r',
        ids: ['box'],
        funding: RerollFunding.coins,
      );
      api.serverCoins = 777;
      await auth.updateCoins(777);
      await billing.reroll(
        raceId: 'r',
        ids: ['box'],
        funding: RerollFunding.coins,
      );
      expect(auth.wallet, 777);
    },
  );
  testWidgets(
    'older backend after refresh removes stale purchase and paid reroll controls',
    (tester) async {
      final api = TestApi();
      final billing = LiveBillingController(
        auth: TestAuth(),
        api: api,
        store: TestStore(),
        platform: 'android',
      );
      addTearDown(billing.dispose);
      await billing.refresh();
      expect(billing.supportsRace('r'), isTrue);
      api.oldBackend = true;
      await billing.refresh();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CoinPackOffers(controller: billing)),
        ),
      );
      expect(find.text('Fill your coin pouch'), findsNothing);
      expect(billing.supportsRace('r'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'null additive fields preserve the existing wallet and hide checkout',
    (tester) async {
      final api = TestApi()
        ..rawBootstrap = {
          'contract': 'bara-billing-v1',
          'available': true,
          'identity': null,
          'membership': null,
          'credits': null,
          'coins': null,
          'products': null,
          'reroll': null,
        };
      final auth = TestAuth();
      final billing = LiveBillingController(
        auth: auth,
        api: api,
        store: TestStore(),
        platform: 'ios',
      );
      addTearDown(billing.dispose);
      await billing.refresh();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CoinPackOffers(controller: billing)),
        ),
      );
      expect(find.text('Fill your coin pouch'), findsNothing);
      expect(auth.wallet, 100);
      expect(billing.snapshot.status, BillingStatus.free);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'native pending approval has a visible retry on the coin screen',
    (tester) async {
      final billing = LiveBillingController(
        auth: TestAuth(),
        api: TestApi(),
        store: TestStore()..pendingError = true,
        platform: 'ios',
      );
      await billing.refresh();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CoinPackOffers(controller: billing)),
        ),
      );
      await tester.tap(find.byKey(const Key('buy-coins-coins_500')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Check purchase status'), findsOneWidget);
      expect(find.textContaining('Purchase confirmed'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      billing.dispose();
    },
  );

  testWidgets(
    'native pending survives empty sync and process recreation until exact new transaction appears',
    (tester) async {
      final auth = TestAuth(),
          api = TestApi(),
          store = TestStore()..pendingError = true;
      var billing = LiveBillingController(
        auth: auth,
        api: api,
        store: store,
        platform: 'ios',
      );
      await billing.refresh();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CoinPackOffers(controller: billing)),
        ),
      );
      await tester.tap(find.byKey(const Key('buy-coins-coins_500')));
      await tester.pump(const Duration(milliseconds: 200));
      await billing.refresh();
      expect(billing.snapshot.operationStatus, BillingOperationStatus.pending);
      await tester.pumpWidget(const SizedBox.shrink());
      billing.dispose();
      billing = LiveBillingController(
        auth: auth,
        api: api,
        store: store,
        platform: 'ios',
      );
      addTearDown(billing.dispose);
      await billing.refresh();
      expect(billing.snapshot.operationStatus, BillingOperationStatus.pending);
      store.nativeTransactions.add('new-approved-transaction');
      await billing.refresh();
      expect(billing.snapshot.operationStatus, BillingOperationStatus.success);
      expect(api.syncHints.last, 'new-approved-transaction');
    },
  );
  testWidgets(
    'baseline failure prevents native checkout from real buy button',
    (tester) async {
      final store = TestStore()..baselineFails = true;
      final billing = LiveBillingController(
        auth: TestAuth(),
        api: TestApi(),
        store: store,
        platform: 'ios',
      );
      addTearDown(billing.dispose);
      await billing.refresh();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CoinPackOffers(controller: billing)),
        ),
      );
      await tester.tap(find.byKey(const Key('buy-coins-coins_500')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(store.purchases, 0);
    },
  );
  testWidgets(
    'delayed native checkout stays with original identity across a real screen account switch',
    (tester) async {
      final auth = TestAuth(), api = TestApi()..perAccount = true;
      final store = TestStore()..purchaseCompleter = Completer<String?>();
      final billing = LiveBillingController(
        auth: auth,
        api: api,
        store: store,
        platform: 'ios',
      );
      addTearDown(billing.dispose);
      await billing.refresh();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CoinPackOffers(controller: billing)),
        ),
      );
      await tester.tap(find.byKey(const Key('buy-coins-coins_500')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(store.purchaseIdentities, ['identity-a']);
      auth.switchUser();
      await tester.pump(const Duration(milliseconds: 100));
      store.purchaseCompleter!.complete('a-only-transaction');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(billing.userId, 'b');
      expect(auth.wallet, 900);
      expect(store.identity, 'identity-b');
      expect(api.syncTokens, ['token-a', 'token-b']);
      expect(api.syncHints, isNot(contains('a-only-transaction')));
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('billing.sync.v1.ios.a'),
        contains('a-only-transaction'),
      );
      expect(prefs.getString('billing.sync.v1.ios.b'), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('ambiguous native network error cannot start a second checkout', (
    tester,
  ) async {
    final store = TestStore()..uncertainError = true;
    final billing = LiveBillingController(
      auth: TestAuth(),
      api: TestApi(),
      store: store,
      platform: 'ios',
    );
    await billing.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CoinPackOffers(controller: billing)),
      ),
    );
    await tester.tap(find.byKey(const Key('buy-coins-coins_500')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(billing.snapshot.operationStatus, BillingOperationStatus.pending);
    await tester.tap(find.byKey(const Key('buy-coins-coins_500')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(store.purchases, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    billing.dispose();
  });
  for (final reject in [false, true]) {
    testWidgets(
      'deferred plan change ${reject ? 'cancellation' : 'success'} keeps current paid plan and wallet',
      (tester) async {
        final api = TestApi()
          ..membership = {
            'status': 'active',
            'plan': 'annual',
            'accessUntil': DateTime.now()
                .add(const Duration(days: 30))
                .toUtc()
                .toIso8601String(),
            'renews': true,
            'discountPercent': 15,
          }
          ..fixedCoins = 100;
        final store = TestStore()..rejectPlanChange = reject;
        final billing = LiveBillingController(
          auth: TestAuth(),
          api: api,
          store: store,
          platform: 'android',
        );
        addTearDown(billing.dispose);
        await billing.refresh();
        await tester.pumpWidget(
          MaterialApp(home: BaraPlusScreen(controller: billing)),
        );
        await tester.scrollUntilVisible(
          find.byKey(const Key('change-bara-plan')),
          500,
        );
        await tester.tap(find.byKey(const Key('change-bara-plan')));
        await tester.pumpAndSettle();
        expect(find.textContaining('€5,49/month'), findsOneWidget);
        expect(find.textContaining('next renewal'), findsWidgets);
        await tester.tap(find.byKey(const Key('confirm-bara-plan-change')));
        await tester.pump(const Duration(milliseconds: 400));
        expect(store.planChanges, [
          ['annual', 'monthly'],
        ]);
        expect(billing.snapshot.plan, BillingPlan.annual);
        expect(billing.snapshot.coins, 100);
        expect(billing.snapshot.paidCredits, 0);
        expect(store.purchases, 0);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('billing.sync.v1.android.a'), isNull);
        expect(
          find.textContaining(
            reject ? 'Plan change cancelled.' : 'Plan change requested',
          ),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'restore ownership conflict directs original account without pending payment',
    (tester) async {
      final billing = LiveBillingController(
        auth: TestAuth(),
        api: TestApi(),
        store: TestStore()..restoreAccountMismatch = true,
        platform: 'ios',
      );
      addTearDown(billing.dispose);
      await billing.refresh();
      await tester.pumpWidget(
        MaterialApp(home: BaraPlusScreen(controller: billing)),
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('restore-bara')),
        500,
      );
      await tester.tap(find.byKey(const Key('restore-bara')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.textContaining('Sign in to the original account'),
        findsOneWidget,
      );
      expect(billing.snapshot.operationStatus, BillingOperationStatus.failed);
      expect(billing.snapshot.coins, 100);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('billing.sync.v1.ios.a'), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final scenario in [
    (
      label: 'verified grace after paid period',
      access: true,
      days: -1,
      member: true,
    ),
    (
      label: 'verified grace without synthetic expiry',
      access: true,
      days: null,
      member: true,
    ),
    (
      label: 'explicit denial before expiry',
      access: false,
      days: 30,
      member: false,
    ),
    (label: 'legacy expired membership', access: null, days: -1, member: false),
    (
      label: 'legacy unexpired membership',
      access: null,
      days: 30,
      member: true,
    ),
    (
      label: 'malformed access keeps legacy expiry',
      access: 'true',
      days: -1,
      member: false,
    ),
  ]) {
    testWidgets(
      '${scenario.label} renders authoritative membership without gifts',
      (tester) async {
        final expiry = scenario.days == null
            ? null
            : DateTime.now().add(Duration(days: scenario.days!)).toUtc();
        final api = TestApi()
          ..fixedCoins = 100
          ..membership = {
            'status': 'active',
            'plan': 'monthly',
            'accessUntil': expiry?.toIso8601String(),
            'renews': true,
            'discountPercent': 15,
            if (scenario.access != null) 'givesAccess': scenario.access,
          };
        final billing = LiveBillingController(
          auth: TestAuth(),
          api: api,
          store: TestStore(),
          platform: 'ios',
        );
        addTearDown(billing.dispose);
        await billing.refresh();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: BaraPlusCard(controller: billing)),
          ),
        );
        expect(billing.snapshot.isMember, scenario.member);
        expect(
          billing.snapshot.effectiveDiscountPercent,
          scenario.member ? 15 : 0,
        );
        expect(
          find.textContaining('rerolls left'),
          scenario.member ? findsOneWidget : findsNothing,
        );
        expect(billing.snapshot.accessUntil, expiry);
        expect(billing.snapshot.coins, 100);
        expect(billing.snapshot.paidCredits, 0);
        expect(billing.snapshot.trialCredits, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
