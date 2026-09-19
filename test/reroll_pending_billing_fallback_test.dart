import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/models/billing.dart';
import 'package:step_tracker/services/billing_controller.dart';
import 'package:step_tracker/widgets/pill_button.dart';
import 'package:step_tracker/widgets/reroll_payment_sheet.dart';

class _PendingPurchaseBilling extends BillingController {
  @override
  String get userId => 'testflight-user';

  @override
  bool get isPreview => false;

  @override
  bool get rerollBusy => false;

  @override
  BillingSnapshot get snapshot => const BillingSnapshot(
    status: BillingStatus.free,
    givesAccess: false,
    coins: 3706,
    operationStatus: BillingOperationStatus.pending,
    message: 'Purchase is being confirmed.',
  );

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

  @override
  Future<BillingRerollResult> reroll({
    required String raceId,
    required List<String> ids,
    required RerollFunding funding,
  }) async => const BillingRerollResult(success: true, message: 'ok');
}

void main() {
  testWidgets(
    'pending TestFlight purchase does not disable coin or ad rerolls',
    (tester) async {
      final billing = _PendingPurchaseBilling();
      addTearDown(billing.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showRerollPaymentSheet(
                  context,
                  controller: billing,
                  adSupported: true,
                  batch: true,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final coinButton = tester.widget<PillButton>(
        find.byKey(const Key('reroll-funding-coins')),
      );
      final adButton = tester.widget<PillButton>(
        find.byKey(const Key('reroll-funding-ad')),
      );

      expect(find.textContaining('Balance: 3,706'), findsOneWidget);
      expect(coinButton.onPressed, isNotNull);
      expect(adButton.onPressed, isNotNull);
      expect(find.byKey(const Key('reroll-funding-gold')), findsNothing);
    },
  );
}
