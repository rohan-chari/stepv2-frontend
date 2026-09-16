import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:step_tracker/models/billing.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/services/billing_controller.dart';
import 'package:step_tracker/widgets/billing_scope.dart';
import 'package:step_tracker/widgets/coin_pack_offers.dart';
import 'package:step_tracker/widgets/reroll_payment_sheet.dart';
import 'package:step_tracker/widgets/bara_plus_card.dart';
import 'package:step_tracker/screens/bara_plus_screen.dart';

class FakeBilling extends BillingController {
  BillingSnapshot state = const BillingSnapshot(coins: 100);
  @override
  String get userId => 'test';
  @override
  bool get isPreview => true;
  @override
  BillingSnapshot get snapshot => state;
  CoinPackOffer? purchased;
  BillingResult? nextResult;
  int restores = 0;
  int cancels = 0;
  int rerolls = 0;
  void update(BillingSnapshot value) {
    final wasPending = state.operationStatus == BillingOperationStatus.pending;
    state = value;
    if (wasPending && value.operationStatus == BillingOperationStatus.failed) {
      publishPendingFeedback(
        BillingResult(
          success: false,
          message: value.message ?? 'Purchase failed.',
        ),
      );
    } else {
      notifyListeners();
    }
  }

  @override
  Future<BillingResult> buyCoins(CoinPackOffer pack) async {
    purchased = pack;
    final result = nextResult;
    nextResult = null;
    if (result != null) return result;
    return const BillingResult(
      success: true,
      message: 'Preview purchase complete',
    );
  }

  @override
  Future<BillingResult> startTrial(BillingPlan plan) async {
    update(BillingSnapshot(status: BillingStatus.trial, plan: plan));
    return const BillingResult(success: true, message: 'Trial started');
  }

  @override
  Future<BillingResult> subscribe(BillingPlan plan) async =>
      const BillingResult(success: true, message: 'Subscribed');
  @override
  Future<BillingResult> restore() async {
    restores++;
    return const BillingResult(
      success: true,
      message: 'Preview purchases restored',
    );
  }

  @override
  Future<BillingResult> cancelRenewal() async {
    cancels++;
    return const BillingResult(
      success: true,
      message: 'Preview renewal cancelled',
    );
  }

  @override
  Future<BillingRerollResult> reroll({
    required String raceId,
    required List<String> ids,
    required RerollFunding funding,
  }) async {
    rerolls++;
    return const BillingRerollResult(success: true, message: 'Rerolled');
  }
}

Widget host(FakeBilling billing, Widget child) => BillingScope(
  controller: billing,
  child: MaterialApp(home: Scaffold(body: child)),
);

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
  testWidgets('coin offers show all accepted amounts and explicit purchase', (
    tester,
  ) async {
    final billing = FakeBilling();
    await tester.pumpWidget(
      host(billing, const SingleChildScrollView(child: CoinPackOffers())),
    );
    for (final quantity in ['500', '3,000', '7,500']) {
      expect(find.text(quantity), findsOneWidget);
    }
    await tester.tap(find.byKey(const Key('buy-coins-coins_500')));
    await tester.pump();
    expect(billing.purchased?.coins, 500);
    expect(find.text('Preview purchase complete'), findsOneWidget);
    billing.nextResult = const BillingResult(
      success: false,
      message: 'Waiting for approval',
      disposition: BillingDisposition.pending,
    );
    await tester.tap(find.byKey(const Key('buy-coins-coins_500')));
    await tester.pump();
    billing.update(
      const BillingSnapshot(
        operationStatus: BillingOperationStatus.pending,
        message: 'Waiting for approval',
      ),
    );
    await tester.pump();
    expect(find.text('Waiting for approval'), findsOneWidget);
    billing.update(
      const BillingSnapshot(
        operationStatus: BillingOperationStatus.failed,
        message: 'Purchase failed. Try again.',
      ),
    );
    await tester.pump();
    expect(find.text('Purchase failed. Try again.'), findsOneWidget);
  });
  testWidgets('membership monthly offer and trial use current Gold benefits', (
    tester,
  ) async {
    final billing = FakeBilling();
    await tester.pumpWidget(host(billing, const BaraPlusScreen()));
    await tester.ensureVisible(find.byKey(const Key('plan-monthly')));
    await tester.tap(find.byKey(const Key('plan-monthly')));
    await tester.pump();
    expect(
      find.textContaining('Monthly Gold grants 1,000 coins'),
      findsOneWidget,
    );
    expect(find.text('One free reroll per powerup'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('start-bara-trial')),
      400,
    );
    await tester.tap(find.byKey(const Key('start-bara-trial')));
    await tester.pump();
    expect(billing.snapshot.status, BillingStatus.trial);
    expect(billing.snapshot.plan, BillingPlan.monthly);
    expect(find.textContaining('Your Gold trial is active.'), findsOneWidget);
    expect(billing.snapshot.trialCredits, 0);
  });
  testWidgets(
    'selected plan copy stays white and the pricing note is centered',
    (tester) async {
      final billing = FakeBilling();
      await tester.pumpWidget(
        BillingScope(
          controller: billing,
          child: MaterialApp(
            theme: ThemeData(extensions: [AppPalette.light]),
            home: const BaraPlusScreen(),
          ),
        ),
      );

      for (final label in ['WEEKLY', r'$1.49', '200 coins / week']) {
        expect(
          tester.widget<Text>(find.text(label)).style!.color,
          AppPalette.light.textLight,
        );
      }
      final note = find.textContaining(r'$1.49 per week.');
      final noteAlign = find.ancestor(of: note, matching: find.byType(Align));
      expect(noteAlign, findsOneWidget);
      expect(tester.widget<Align>(noteAlign).alignment, Alignment.center);
    },
  );

  testWidgets('Gold benefit icons use the brighter night purple', (
    tester,
  ) async {
    final billing = FakeBilling();
    await tester.pumpWidget(
      BillingScope(
        controller: billing,
        child: MaterialApp(
          theme: ThemeData(extensions: [AppPalette.night]),
          home: const BaraPlusScreen(),
        ),
      ),
    );

    expect(
      tester.widget<Icon>(find.byIcon(Icons.local_offer_outlined)).color,
      AppPalette.night.medalGold,
    );
  });

  testWidgets('Bara Gold card uses the short premium subtitle', (tester) async {
    final billing = FakeBilling();
    await tester.pumpWidget(
      BillingScope(
        controller: billing,
        child: MaterialApp(
          home: Scaffold(body: BaraPlusCard(controller: billing)),
        ),
      ),
    );

    expect(find.text('More room to move, play, and collect.'), findsOneWidget);
    expect(find.textContaining('15% member discount'), findsNothing);
    expect(find.textContaining('Gold perks'), findsNothing);
    final cardMaterial = find.ancestor(
      of: find.byKey(const Key('bara-plus-card')),
      matching: find.byType(Material),
    );
    expect(cardMaterial, findsNWidgets(2));
    expect(tester.widget<Material>(cardMaterial.first).color, Colors.white);
  });
  testWidgets(
    'expired historical credits are not shown as active Gold benefits',
    (tester) async {
      final billing = FakeBilling()
        ..state = const BillingSnapshot(
          status: BillingStatus.expired,
          paidCredits: 8,
        );
      await tester.pumpWidget(host(billing, const BaraPlusScreen()));
      expect(find.text('8 paid rerolls'), findsNothing);
      expect(find.textContaining('remain usable'), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const Key('restore-bara')),
        400,
      );
      await tester.tap(find.byKey(const Key('restore-bara')));
      await tester.pump();
      expect(billing.restores, 1);
    },
  );
  testWidgets('reroll selection is explicit and cancelling never spends', (
    tester,
  ) async {
    final billing = FakeBilling();
    RerollFunding? choice;
    await tester.pumpWidget(
      host(
        billing,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              choice = await showRerollPaymentSheet(
                context,
                controller: billing,
                batch: true,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('50 coins'), findsWidgets);
    expect(find.textContaining('could be worse'), findsOneWidget);
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    expect(choice, isNull);
    expect(billing.rerolls, 0);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reroll-funding-coins')));
    await tester.pumpAndSettle();
    expect(choice, RerollFunding.coins);
    expect(billing.rerolls, 0);
  });
  testWidgets('membership management requires confirmation', (tester) async {
    final billing = FakeBilling()
      ..state = const BillingSnapshot(
        status: BillingStatus.active,
        plan: BillingPlan.monthly,
      );
    await tester.pumpWidget(host(billing, const BaraPlusScreen()));
    await tester.scrollUntilVisible(find.byKey(const Key('manage-bara')), 400);
    await tester.tap(find.byKey(const Key('manage-bara')));
    await tester.pumpAndSettle();
    expect(billing.cancels, 1);
  });
  testWidgets('missing billing scope has no purchase offers', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CoinPackOffers())),
    );
    expect(find.text('500'), findsNothing);
    await tester.pumpWidget(const MaterialApp(home: BaraPlusScreen()));
    expect(find.text('Bara Gold is not available right now.'), findsOneWidget);
  });
  testWidgets('small phone and large text fit light and dark membership', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final palette in [AppPalette.light, AppPalette.night]) {
      final billing = FakeBilling();
      await tester.pumpWidget(
        BillingScope(
          controller: billing,
          child: MaterialApp(
            theme: ThemeData(extensions: [palette]),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.8)),
              child: child!,
            ),
            home: const BaraPlusScreen(),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byKey(const Key('start-bara-trial')),
        300,
      );
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('coin packs fit large text on a small phone', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final billing = FakeBilling();
    await tester.pumpWidget(
      BillingScope(
        controller: billing,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(child: CoinPackOffers()),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
