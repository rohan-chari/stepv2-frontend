import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:step_tracker/models/billing.dart';
import 'package:step_tracker/models/character_wardrobe.dart';
import 'package:step_tracker/screens/bara_plus_screen.dart';
import 'package:step_tracker/services/billing_controller.dart';
import 'package:step_tracker/widgets/billing_scope.dart';
import 'package:step_tracker/widgets/shop_character_card.dart';

class _GoldBilling extends BillingController {
  final bool member = false;
  final directPurchases = <String>[];

  @override
  String get userId => 'gold-test-user';

  @override
  bool get isPreview => true;

  @override
  BillingSnapshot get snapshot => BillingSnapshot(
    status: member ? BillingStatus.active : BillingStatus.free,
    plan: member ? BillingPlan.weekly : null,
    givesAccess: member,
  );

  @override
  List<StorePlanOffer> get plans => const [
    StorePlanOffer(plan: BillingPlan.weekly, price: r'$1.49', trialDays: 7),
    StorePlanOffer(plan: BillingPlan.monthly, price: r'$3.99', trialDays: 7),
  ];

  @override
  Future<BillingResult> buyCoins(CoinPackOffer pack) async =>
      const BillingResult(success: true, message: 'ok');

  @override
  Future<BillingResult> buyDirectProduct(String storeProductId) async {
    directPurchases.add(storeProductId);
    return const BillingResult(
      success: true,
      message: 'Character purchase confirmed',
    );
  }

  @override
  Future<BillingResult> startTrial(BillingPlan plan) async =>
      const BillingResult(success: true, message: 'ok');

  @override
  Future<BillingResult> subscribe(BillingPlan plan) async =>
      const BillingResult(success: true, message: 'ok');

  @override
  Future<BillingResult> restore() async =>
      const BillingResult(success: true, message: 'ok');

  @override
  Future<BillingResult> cancelRenewal() async =>
      const BillingResult(success: true, message: 'ok');

  @override
  Future<BillingRerollResult> reroll({
    required String raceId,
    required List<String> ids,
    required RerollFunding funding,
  }) async => const BillingRerollResult(success: true, message: 'ok');
}

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'test',
      version: '1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  test('Gold plan and snapshot defaults are additive and defensive', () {
    expect(BillingPlan.values, contains(BillingPlan.weekly));
    expect(const BillingSnapshot().isMember, isFalse);
    expect(const BillingSnapshot().availableCredits, 0);
  });

  testWidgets(
    'Bara Gold paywall only presents current weekly/monthly benefits',
    (tester) async {
      final billing = _GoldBilling();
      await tester.pumpWidget(
        BillingScope(
          controller: billing,
          child: const MaterialApp(home: Scaffold(body: BaraPlusScreen())),
        ),
      );

      expect(find.text('Bara Gold'), findsOneWidget);
      expect(find.byKey(const Key('plan-weekly')), findsOneWidget);
      expect(find.byKey(const Key('plan-monthly')), findsOneWidget);
      expect(find.byKey(const Key('plan-annual')), findsNothing);
      expect(find.byKey(const Key('plan-permanent')), findsNothing);
      expect(find.textContaining('credit'), findsNothing);
      expect(find.textContaining('cosmetic'), findsNothing);
      expect(find.textContaining('Bara+'), findsNothing);
      expect(find.byKey(const Key('gold-benefit-coins')), findsOneWidget);
      expect(find.byKey(const Key('gold-benefit-adfree')), findsOneWidget);
      expect(find.byKey(const Key('gold-benefit-rerolls')), findsOneWidget);
      expect(find.byKey(const Key('gold-benefit-exclusive')), findsOneWidget);
      expect(find.text('Monthly coin bonus'), findsOneWidget);
      expect(find.text('Ad-free experience'), findsOneWidget);
      expect(find.text('Free rerolls on everything'), findsOneWidget);
      expect(find.text('Exclusive characters & powerups'), findsOneWidget);
      expect(find.byKey(const Key('bara-gold-best-deal')), findsOneWidget);
      expect(find.text('BEST DEAL'), findsOneWidget);
    },
  );

  testWidgets(
    'Gold character policy renders framed label and direct-IAP fallback',
    (tester) async {
      final character = ShopCharacter.fromJson({
        'characterKey': 'mouse',
        'name': 'Mouse',
        'item': {
          'id': 'mouse',
          'sku': 'mouse',
          'slot': 'CHARACTER',
          'assetKey': 'mouse',
          'priceCoins': 1000,
        },
        'owned': false,
        'canPurchase': false,
        'goldAccess': true,
        'coinPurchaseAllowed': false,
        'directPurchase': {
          'available': true,
          'storeProductId': 'bara_character_mouse_v1',
        },
        'unavailableReason': 'requires_gold_or_direct_purchase',
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ShopCharacterCard(character: character)),
        ),
      );

      expect(find.text('Bara Gold'), findsNothing);
      expect(find.byKey(const Key('bara-gold-card-frame')), findsOneWidget);
      expect(find.byKey(const Key('bara-gold-card-label')), findsOneWidget);
      expect(find.text('BUY'), findsOneWidget);
      expect(find.text('Unavailable'), findsNothing);
    },
  );

  testWidgets('Gold character with missing IAP metadata offers Get Gold', (
    tester,
  ) async {
    final character = ShopCharacter.fromJson({
      'characterKey': 'mouse',
      'name': 'Mouse',
      'item': {
        'id': 'mouse',
        'slot': 'CHARACTER',
        'assetKey': 'mouse',
        'priceCoins': 1000,
      },
      'owned': false,
      'canPurchase': false,
      'goldAccess': true,
      'directPurchase': {'available': true},
    });
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShopCharacterCard(
            character: character,
            onGetGold: () => opened = true,
          ),
        ),
      ),
    );

    expect(find.text('Get Gold'), findsOneWidget);
    expect(find.text('DIRECT PURCHASE'), findsNothing);
    await tester.tap(find.text('Get Gold'));
    expect(opened, isTrue);
  });

  testWidgets('direct character purchase action uses the server product ID', (
    tester,
  ) async {
    final billing = _GoldBilling();
    final character = ShopCharacter.fromJson({
      'characterKey': 'sea_lion',
      'name': 'Sea Lion',
      'item': {
        'id': 'sea_lion',
        'sku': 'sea_lion',
        'slot': 'CHARACTER',
        'assetKey': 'sea_lion',
        'priceCoins': 1000,
      },
      'owned': false,
      'canPurchase': false,
      'goldAccess': true,
      'coinPurchaseAllowed': false,
      'directPurchase': {
        'available': true,
        'storeProductId': 'bara_character_sea_lion_v1',
      },
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShopCharacterCard(
            character: character,
            onDirectBuy: () =>
                billing.buyDirectProduct(character.directStoreProductId!),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('shop-character-direct-sea_lion')));
    await tester.pump();
    expect(billing.directPurchases, ['bara_character_sea_lion_v1']);
    expect(find.text('BUY'), findsOneWidget);
  });
}
