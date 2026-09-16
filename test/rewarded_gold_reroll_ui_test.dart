import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/models/billing.dart';
import 'package:step_tracker/services/billing_controller.dart';
import 'package:step_tracker/widgets/billing_scope.dart';
import 'package:step_tracker/widgets/reroll_payment_sheet.dart';

class _RerollBilling extends BillingController {
  _RerollBilling(this.member);

  final bool member;

  @override
  String get userId => member ? 'gold-user' : 'free-user';
  @override
  bool get isPreview => true;
  @override
  BillingSnapshot get snapshot => BillingSnapshot(
    status: member ? BillingStatus.active : BillingStatus.free,
    plan: member ? BillingPlan.weekly : null,
    givesAccess: member,
    coins: 100,
  );
  @override
  Future<BillingResult> buyCoins(CoinPackOffer pack) async =>
      const BillingResult(success: true, message: 'ok');
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
  testWidgets('free single reroll exposes ad and Remove Ads', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BillingScope(
          controller: _RerollBilling(false),
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showRerollPaymentSheet(
                  context,
                  controller: BillingScope.read(context)!,
                  adSupported: true,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reroll-funding-ad')), findsOneWidget);
    expect(find.byKey(const Key('remove-ads-action')), findsOneWidget);
    expect(find.byKey(const Key('reroll-funding-gold')), findsNothing);
  });

  testWidgets('Gold batch reroll exposes only the free Gold action', (
    tester,
  ) async {
    final billing = _RerollBilling(true);
    await tester.pumpWidget(
      MaterialApp(
        home: BillingScope(
          controller: billing,
          child: Builder(
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
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reroll-funding-gold')), findsOneWidget);
    expect(find.byKey(const Key('reroll-funding-ad')), findsNothing);
    expect(find.byKey(const Key('remove-ads-action')), findsNothing);
    expect(find.textContaining('One free reroll per powerup'), findsOneWidget);
  });
}
