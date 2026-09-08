import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/services/store_billing_client.dart';

// Native transport contract tests cannot be expressed as widget placement:
// exercise the actual RevenueCat adapter and inspect the SDK channel boundary.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('purchases_flutter');
  final calls = <MethodCall>[];
  late Map<String, dynamic> subscription;
  var permanent = false;
  Map<String, dynamic> customer() => {
    'entitlements': {'all': {}, 'active': {}},
    'allPurchaseDates': {},
    'activeSubscriptions': ['bara_plus_v1:monthly'],
    'allPurchasedProductIdentifiers': ['bara_plus_v1:monthly'],
    'nonSubscriptionTransactions': permanent
        ? [
            {
              'transactionIdentifier': 'permanent-store-id',
              'productIdentifier': 'bara_plus_permanent_v1',
              'purchaseDate': '2026-09-07T00:00:00Z',
            },
          ]
        : [],
    'firstSeen': '2026-01-01T00:00:00Z',
    'originalAppUserId': 'billing-user',
    'allExpirationDates': {},
    'requestDate': '2026-09-07T00:00:00Z',
    'subscriptionsByProductIdentifier': {'bara_plus_v1': subscription},
  };
  setUp(() {
    calls.clear();
    permanent = false;
    subscription = {
      'productIdentifier': 'bara_plus_v1',
      'productPlanIdentifier': 'monthly',
      'purchaseDate': '2026-09-01T00:00:00Z',
      'isSandbox': true,
      'isActive': true,
      'willRenew': true,
      'store': 'PLAY_STORE',
      'storeTransactionId': 'old-monthly-transaction',
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'isConfigured':
              return false;
            case 'setupPurchases':
              return null;
            case 'invalidateCustomerInfoCache':
              return null;
            case 'getCustomerInfo':
              return customer();
            case 'getProductInfo':
              return [
                {
                  'identifier': permanent
                      ? 'bara_plus_permanent_v1'
                      : 'bara_plus_v1:annual',
                  'description': 'Bara+',
                  'title': 'Bara+ Yearly',
                  'price': 49.99,
                  'priceString': '\$49.99',
                  'currencyCode': 'USD',
                  'productCategory': permanent
                      ? 'NON_SUBSCRIPTION'
                      : 'SUBSCRIPTION',
                },
              ];
            case 'purchaseProduct':
              return {
                'customerInfo': customer(),
                'transaction': {
                  'transactionIdentifier': permanent
                      ? 'permanent-store-id'
                      : 'old-monthly-transaction',
                  'productIdentifier': permanent
                      ? 'bara_plus_permanent_v1'
                      : 'bara_plus_v1:monthly',
                  'purchaseDate': '2026-09-01T00:00:00Z',
                },
              };
            default:
              throw StateError('Unexpected native call ${call.method}');
          }
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  test(
    'actual Android SDK call sends exact old base plan and DEFERRED replacement',
    () async {
      final store = RevenueCatBillingClient(
        apiKey: 'public-test-key',
        platform: 'android',
      );
      await store.identify('billing-user');
      await store.products([], ['bara_plus_v1:annual']);
      await store.changePlan(
        oldProductId: 'bara_plus_v1:monthly',
        newProductId: 'bara_plus_v1:annual',
      );
      final purchase = calls.singleWhere(
        (call) => call.method == 'purchaseProduct',
      );
      final args = purchase.arguments as Map;
      expect(args['googleOldProductIdentifier'], 'bara_plus_v1:monthly');
      expect(args['storeReplacementMode'], 'DEFERRED');
      expect(args['productIdentifier'], 'bara_plus_v1:annual');
      expect(
        calls.indexWhere(
          (call) => call.method == 'invalidateCustomerInfoCache',
        ),
        lessThan(calls.indexWhere((call) => call.method == 'getCustomerInfo')),
      );
    },
  );
  test(
    'native transaction history matches base plans exactly and rejects missing IDs',
    () async {
      final store = RevenueCatBillingClient(
        apiKey: 'public-test-key',
        platform: 'android',
      );
      expect(await store.transactionIds('bara_plus_v1:annual'), isEmpty);
      expect(await store.transactionIds('bara_plus_v1:monthly'), [
        'old-monthly-transaction',
      ]);
      subscription['storeTransactionId'] = null;
      await expectLater(
        store.transactionIds('bara_plus_v1:monthly'),
        throwsA(isA<StoreBillingException>()),
      );
    },
  );
  test(
    'subscription from another store cannot use a native plan change',
    () async {
      subscription['store'] = 'APP_STORE';
      final store = RevenueCatBillingClient(
        apiKey: 'public-test-key',
        platform: 'android',
      );
      await store.products([], ['bara_plus_v1:annual']);
      await expectLater(
        store.changePlan(
          oldProductId: 'bara_plus_v1:monthly',
          newProductId: 'bara_plus_v1:annual',
        ),
        throwsA(isA<StoreBillingException>()),
      );
      expect(calls.where((call) => call.method == 'purchaseProduct'), isEmpty);
    },
  );
  test(
    'permanent product uses native nonSubscription lookup and exact transaction ID',
    () async {
      permanent = true;
      final store = RevenueCatBillingClient(
        apiKey: 'public-test-key',
        platform: 'android',
      );
      await store.identify('billing-user');
      final products = await store.products(['bara_plus_permanent_v1'], []);
      expect(products.single.id, 'bara_plus_permanent_v1');
      final lookup = calls.singleWhere((c) => c.method == 'getProductInfo');
      expect((lookup.arguments as Map)['type'], 'nonSubscription');
      expect(await store.transactionIds('bara_plus_permanent_v1'), [
        'permanent-store-id',
      ]);
      expect(
        await store.purchase('bara_plus_permanent_v1'),
        'permanent-store-id',
      );
      final purchase = calls.singleWhere((c) => c.method == 'purchaseProduct');
      expect(
        (purchase.arguments as Map)['productIdentifier'],
        'bara_plus_permanent_v1',
      );
      expect((purchase.arguments as Map)['googleOldProductIdentifier'], isNull);
      expect(
        calls.any((c) => c.method.toLowerCase().contains('consume')),
        false,
      );
    },
  );
}
