import 'dart:async';
import 'package:flutter/material.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'package:step_tracker/widgets/billing_scope.dart';
import 'unified_shop_test.dart' show ShopApi;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/bara_plus_screen.dart';
import 'package:step_tracker/models/billing.dart';
import 'package:step_tracker/services/live_billing_controller.dart';
import 'package:step_tracker/services/store_billing_client.dart';
import 'package:step_tracker/widgets/coin_pack_offers.dart';
import 'live_billing_test.dart' show TestAuth, TestApi;

void main() {
  const channel = MethodChannel('purchases_flutter');
  final calls = <MethodCall>[];
  var failCoins = false, failSubscriptions = false, failEligibility = false;
  var errorCode = '23';
  Completer<void>? heldProducts;
  late TestAuth auth;
  late TestApi api;
  late RevenueCatBillingClient store;
  late LiveBillingController billing;
  Map<String, dynamic> customer() => {
    'entitlements': {'all': {}, 'active': {}},
    'allPurchaseDates': {},
    'activeSubscriptions': [],
    'allPurchasedProductIdentifiers': [],
    'nonSubscriptionTransactions': [],
    'firstSeen': '2026-01-01T00:00:00Z',
    'originalAppUserId': 'fixture',
    'allExpirationDates': {},
    'requestDate': '2026-09-10T00:00:00Z',
    'subscriptionsByProductIdentifier': {},
  };
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'test',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    errorCode = '23';
    failCoins = false;
    failSubscriptions = false;
    failEligibility = false;
    heldProducts = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'isConfigured':
              return true;
            case 'logIn':
              return {'customerInfo': customer(), 'created': false};
            case 'getCustomerInfo':
              return customer();
            case 'purchaseProduct':
              return {
                'customerInfo': customer(),
                'transaction': {
                  'transactionIdentifier': 'fixture-purchase',
                  'productIdentifier':
                      (call.arguments as Map)['productIdentifier'],
                  'purchaseDate': '2026-09-10T00:00:00Z',
                },
              };
            case 'invalidateCustomerInfoCache':
              return null;
            case 'getProductInfo':
              await heldProducts?.future;
              final args = call.arguments as Map;
              final coins = args['type'] == 'nonSubscription';
              if (coins ? failCoins : failSubscriptions) {
                throw PlatformException(
                  code: errorCode,
                  message: 'private SDK payload never log',
                );
              }
              return [
                for (final id in args['productIdentifiers'] as List)
                  {
                    'identifier': id,
                    'description': 'Product',
                    'title': 'Product',
                    'price': coins ? 1.09 : 5.49,
                    'priceString': coins ? '€1,09' : '€5,49',
                    'currencyCode': 'EUR',
                    'productCategory': coins
                        ? 'NON_SUBSCRIPTION'
                        : 'SUBSCRIPTION',
                    if (!coins)
                      'introPrice': {
                        'price': 0.0,
                        'priceString': '€0,00',
                        'period': 'P1W',
                        'cycles': 1,
                        'periodUnit': 'WEEK',
                        'periodNumberOfUnits': 1,
                      },
                  },
              ];
            case 'checkTrialOrIntroductoryPriceEligibility':
              if (failEligibility) throw PlatformException(code: '23');
              return {
                'monthly': {'status': 2, 'description': 'eligible'},
                'annual': {'status': 2, 'description': 'eligible'},
              };
            default:
              throw StateError('Unexpected native call ${call.method}');
          }
        });
    auth = TestAuth();
    api = TestApi()..perAccount = true;
    store = RevenueCatBillingClient(apiKey: 'public-test-key', platform: 'ios');
    billing = LiveBillingController(
      auth: auth,
      api: api,
      store: store,
      platform: 'ios',
    );
  });
  tearDown(() {
    billing.dispose();
    auth.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  Future<void> render(WidgetTester tester, {bool membership = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: membership
            ? BaraPlusScreen(controller: billing)
            : Scaffold(
                body: SingleChildScrollView(
                  child: CoinPackOffers(controller: billing),
                ),
              ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'cold native product load renders loading rather than unavailable',
    (tester) async {
      heldProducts = Completer<void>.sync();
      // Start and flush the native request without completing its fixture response.
      late Future<void> pending;
      await tester.runAsync(() async {
        pending = billing.refresh();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await render(tester);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Coin packs are currently unavailable.'), findsNothing);
      heldProducts!.complete();
      heldProducts = null;
      await tester.runAsync(() => pending);
      await tester.pump();
      expect(find.text('€1,09'), findsOneWidget);
    },
  );
  testWidgets(
    'real Shop loads coins and keeps membership hidden throughout native loading',
    (tester) async {
      late Future<void> pending;
      await tester.runAsync(() async {
        heldProducts = Completer<void>();
        pending = billing.refresh();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpWidget(
        BillingScope(
          controller: billing,
          child: MaterialApp(
            home: ShopTab(authService: auth, backendApiService: ShopApi()),
          ),
        ),
      );
      await tester.pump();
      final unavailable = find.text('Membership is currently unavailable.');
      expect(unavailable, findsNothing);
      expect(find.text('Loading membership…'), findsNothing);
      expect(find.text('Finding your coin packs…'), findsOneWidget);
      expect(find.byKey(const Key('shop-membership-toggle')), findsNothing);
      await tester.runAsync(() async {
        heldProducts!.complete();
        heldProducts = null;
        await pending;
      });
      await tester.pump();
      expect(find.text('Loading membership…'), findsNothing);
      expect(find.byKey(const Key('shop-membership-toggle')), findsNothing);
      expect(find.text('€1,09'), findsOneWidget);
    },
  );
  for (final code in ['channel-error', '-1']) {
    testWidgets(
      'unexpected native error code $code stays isolated and redacted',
      (tester) async {
        errorCode = code;
        failSubscriptions = true;
        final logs = <String>[];
        final original = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) logs.add(message);
        };
        try {
          await tester.runAsync(billing.refresh);
          await render(tester);
          expect(find.text('€1,09'), findsOneWidget);
          expect(
            logs,
            contains('Store catalog: subscription_products (unknown)'),
          );
          expect(logs.join(), isNot(contains('private SDK payload')));
          expect(logs.join(), isNot(contains(code)));
        } finally {
          debugPrint = original;
        }
      },
    );
  }
  testWidgets(
    'native subscriptions fail but actual coin UI keeps localized offer',
    (tester) async {
      failSubscriptions = true;
      await tester.runAsync(billing.refresh);
      await render(tester);
      expect(find.text('€1,09'), findsOneWidget);
      expect(find.byKey(const Key('buy-coins-coins_500')), findsOneWidget);
      expect(billing.plans, isEmpty);
    },
  );
  testWidgets(
    'partial native catalog checkout sends exact approved product and reconciles through backend',
    (tester) async {
      failSubscriptions = true;
      await tester.runAsync(billing.refresh);
      await render(tester);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('buy-coins-coins_500')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      final purchase = calls.singleWhere(
        (call) => call.method == 'purchaseProduct',
      );
      expect((purchase.arguments as Map)['productIdentifier'], 'coin');
      expect(api.syncHints, contains('fixture-purchase'));
      expect(auth.coins, 600);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('catalog refresh preserves pending purchase status', (
    tester,
  ) async {
    await tester.runAsync(billing.refresh);
    api.pending = true;
    await tester.runAsync(() => billing.buyCoins(billing.coinPacks.single));
    expect(billing.snapshot.operationStatus, BillingOperationStatus.pending);
    late Future<void> pending;
    await tester.runAsync(() async {
      heldProducts = Completer<void>();
      pending = billing.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await render(tester);
    expect(billing.snapshot.operationStatus, BillingOperationStatus.pending);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.runAsync(() async {
      heldProducts!.complete();
      heldProducts = null;
      await pending;
    });
    expect(billing.snapshot.operationStatus, BillingOperationStatus.pending);
  });
  testWidgets('native coins fail but actual membership keeps native offer', (
    tester,
  ) async {
    failCoins = true;
    await tester.runAsync(billing.refresh);
    await render(tester, membership: true);
    expect(billing.plans.single.price, '€5,49');
    expect(find.textContaining('€5,49'), findsWidgets);
    expect(billing.coinPacks, isEmpty);
  });
  testWidgets(
    'eligibility failure retains both offers without advertising a trial',
    (tester) async {
      failEligibility = true;
      await tester.runAsync(billing.refresh);
      await render(tester);
      expect(find.text('€1,09'), findsOneWidget);
      expect(billing.plans.single.trialDays, 0);
      await render(tester, membership: true);
      expect(find.textContaining('€5,49'), findsWidgets);
      expect(find.byKey(const Key('start-bara-trial')), findsNothing);
    },
  );
  testWidgets(
    'all failures clear native cache and UI retry restores fresh offers',
    (tester) async {
      await tester.runAsync(billing.refresh);
      failCoins = true;
      failSubscriptions = true;
      await tester.runAsync(billing.refresh);
      await render(tester);
      expect(
        find.text('Coin packs are currently unavailable.'),
        findsOneWidget,
      );
      await tester.runAsync(
        () => expectLater(
          store.purchase('coin'),
          throwsA(isA<StoreBillingException>()),
        ),
      );
      expect(calls.where((c) => c.method == 'purchaseProduct'), isEmpty);
      failCoins = false;
      failSubscriptions = false;
      await tester.runAsync(() async {
        await tester.tap(find.text('Try again'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.text('€1,09'), findsOneWidget);
    },
  );
  testWidgets(
    'partial refresh replaces cached products and rejects stale checkout',
    (tester) async {
      await tester.runAsync(billing.refresh);
      failCoins = true;
      await tester.runAsync(billing.refresh);
      await render(tester);
      expect(
        find.text('Coin packs are currently unavailable.'),
        findsOneWidget,
      );
      expect(billing.plans, isNotEmpty);
      await tester.runAsync(
        () => expectLater(
          store.purchase('coin'),
          throwsA(isA<StoreBillingException>()),
        ),
      );
    },
  );
  testWidgets(
    'identity switch discards in-flight partial results and fetches new identity',
    (tester) async {
      failSubscriptions = true;
      await tester.runAsync(() async {
        heldProducts = Completer<void>();
        final oldRefresh = billing.refresh();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        auth.switchUser();
        expect(billing.coinPacks, isEmpty);
        heldProducts!.complete();
        heldProducts = null;
        await oldRefresh;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await render(tester);
      expect(billing.userId, 'b');
      expect(find.text('€1,09'), findsOneWidget);
      final identities = calls
          .where((c) => c.method == 'logIn')
          .map((c) => (c.arguments as Map)['appUserID'])
          .toList();
      expect(identities, ['identity-a', 'identity-b']);
      expect(auth.coins, 900);
    },
  );
}
