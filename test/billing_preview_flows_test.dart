import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/models/billing.dart';
import 'package:step_tracker/preview/preview_billing_controller.dart';
import 'package:step_tracker/widgets/reroll_payment_sheet.dart';
import 'package:step_tracker/widgets/coin_pack_offers.dart';
import 'package:step_tracker/widgets/billing_scope.dart';

void main() {
  test('preview supports both current Gold plans and their coin grants', () async {
    final controller = PreviewBillingController();
    addTearDown(controller.dispose);

    expect(controller.plans.map((offer) => offer.price), [r'$1.49', r'$3.99']);
    expect(
      controller.plans.map((offer) => offer.coinGrant),
      [200, 1000],
    );

    final weeklyTrial = await controller.startTrial(BillingPlan.weekly);
    expect(weeklyTrial.success, isTrue);
    expect(controller.snapshot.plan, BillingPlan.weekly);
    expect(controller.snapshot.status, BillingStatus.trial);
    expect(controller.snapshot.coins, 550);
    expect(controller.snapshot.availableCredits, 0);

    controller.setScenario(PreviewBillingScenario.free);
    final monthly = await controller.subscribe(BillingPlan.monthly);
    expect(monthly.success, isTrue);
    expect(controller.snapshot.plan, BillingPlan.monthly);
    expect(controller.snapshot.coins, 1350);
    expect(controller.snapshot.availableCredits, 0);

    final annual = await controller.subscribe(BillingPlan.annual);
    expect(annual.success, isFalse);
    final permanent = await controller.subscribe(BillingPlan.permanent);
    expect(permanent.success, isFalse);
  });

  test('weekly and monthly Gold previews both start seven-day trials', () async {
    final controller = PreviewBillingController();
    addTearDown(controller.dispose);

    final weekly = await controller.startTrial(BillingPlan.weekly);
    expect(weekly.success, isTrue);
    expect(controller.snapshot.accessUntil, isNotNull);
    expect(
      controller.snapshot.accessUntil!.difference(DateTime.now()).inDays,
      inInclusiveRange(6, 7),
    );

    controller.setScenario(PreviewBillingScenario.free);
    final monthly = await controller.startTrial(BillingPlan.monthly);
    expect(monthly.success, isTrue);
    expect(controller.snapshot.plan, BillingPlan.monthly);
    expect(controller.snapshot.coins, 1350);
  });

  testWidgets(
    'Gold preview batch reroll is free and still limited to one attempt',
    (tester) async {
      final controller = PreviewBillingController();
      addTearDown(controller.dispose);
      controller.setScenario(PreviewBillingScenario.monthly);
      final ids = controller.createBoxes(3);
      BillingRerollResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Reroll batch'),
                onPressed: () async {
                  final funding = await showRerollPaymentSheet(
                    context,
                    controller: controller,
                    batch: true,
                  );
                  if (funding != null) {
                    result = await controller.reroll(
                      raceId: 'billing-preview-race',
                      ids: ids,
                      funding: funding,
                    );
                  }
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Reroll batch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();
      expect(controller.snapshot.coins, 350);
      await tester.tap(find.text('Reroll batch'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reroll-funding-gold')));
      await tester.pumpAndSettle();
      expect(result?.success, true);
      expect(result?.rows.length, 3);
      expect(controller.snapshot.paidCredits, 0);
      expect(controller.snapshot.coins, 350);
      await tester.tap(find.text('Reroll batch'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reroll-funding-gold')), findsOneWidget);
      await tester.tap(find.byKey(const Key('reroll-funding-gold')));
      await tester.pumpAndSettle();
      expect(result?.success, false);
      expect(controller.snapshot.coins, 350);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'preview purchase waits for pending completion and reset cancels in-flight grant',
    (tester) async {
      final controller = PreviewBillingController();
      addTearDown(controller.dispose);
      controller.simulateNextPending();
      await tester.pumpWidget(
        BillingScope(
          controller: controller,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: CoinPackOffers()),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('buy-coins-coins_500')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(
        controller.snapshot.operationStatus,
        BillingOperationStatus.pending,
      );
      expect(controller.snapshot.coins, 350);
      controller.finishPending();
      await tester.pump();
      expect(controller.snapshot.coins, 850);
      await tester.tap(find.byKey(const Key('buy-coins-coins_500')));
      await tester.pump();
      controller.setScenario(PreviewBillingScenario.free);
      await tester.pump(const Duration(seconds: 1));
      expect(controller.snapshot.coins, 350);
      expect(controller.snapshot.operationStatus, BillingOperationStatus.idle);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
