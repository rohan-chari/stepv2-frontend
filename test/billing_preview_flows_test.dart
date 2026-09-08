import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/models/billing.dart';
import 'package:step_tracker/preview/preview_billing_controller.dart';
import 'package:step_tracker/widgets/reroll_payment_sheet.dart';
import 'package:step_tracker/widgets/coin_pack_offers.dart';
import 'package:step_tracker/widgets/billing_scope.dart';

void main() {
  testWidgets(
    'real preview batch consent debits once and cancellation debits nothing',
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
      expect(controller.snapshot.paidCredits, 10);
      expect(controller.snapshot.coins, 850);
      await tester.tap(find.text('Reroll batch'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reroll-funding-credits')));
      await tester.pumpAndSettle();
      expect(result?.success, true);
      expect(result?.rows.length, 3);
      expect(controller.snapshot.paidCredits, 9);
      expect(controller.snapshot.coins, 850);
      await tester.tap(find.text('Reroll batch'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reroll-funding-coins')));
      await tester.pumpAndSettle();
      expect(result?.success, false);
      expect(controller.snapshot.coins, 850);
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
      await tester.tap(find.text(r'$0.99'));
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
      await tester.tap(find.text(r'$0.99'));
      await tester.pump();
      controller.setScenario(PreviewBillingScenario.free);
      await tester.pump(const Duration(seconds: 1));
      expect(controller.snapshot.coins, 350);
      expect(controller.snapshot.operationStatus, BillingOperationStatus.idle);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
