import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/models/billing.dart';
import 'package:step_tracker/screens/bara_plus_screen.dart';
import 'package:step_tracker/services/billing_controller.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/bara_gold_benefits.dart';
import 'package:step_tracker/widgets/coin_glyph.dart';
import 'package:step_tracker/widgets/pill_button.dart';

class _Billing extends BillingController {
  BillingSnapshot state = const BillingSnapshot();
  List<StorePlanOffer> offers = const [
    StorePlanOffer(plan: BillingPlan.weekly, price: r'$1.49', trialDays: 7),
    StorePlanOffer(plan: BillingPlan.monthly, price: r'$3.99', trialDays: 7),
  ];

  @override
  String get userId => 'modal-preview';
  @override
  bool get isPreview => true;
  @override
  BillingSnapshot get snapshot => state;
  @override
  List<StorePlanOffer> get plans => offers;
  @override
  Future<BillingResult> buyCoins(CoinPackOffer pack) async => throw UnimplementedError();
  @override
  Future<BillingResult> startTrial(BillingPlan plan) async => throw UnimplementedError();
  @override
  Future<BillingResult> subscribe(BillingPlan plan) async => throw UnimplementedError();
  @override
  Future<BillingResult> restore() async => throw UnimplementedError();
  @override
  Future<BillingResult> cancelRenewal() async => throw UnimplementedError();
  @override
  Future<BillingRerollResult> reroll({
    required String raceId,
    required List<String> ids,
    required RerollFunding funding,
  }) async => throw UnimplementedError();
}

Future<void> _pumpBody(
  WidgetTester tester,
  _Billing billing, {
  bool night = false,
  bool standalone = false,
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: [night ? AppPalette.night : AppPalette.light]),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: BaraPlusBody(controller: billing, standalone: standalone),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  for (final night in [false, true]) {
    testWidgets(
      'modal keeps all perks and plans with matching ${night ? 'night' : 'day'} styling',
      (tester) async {
        final billing = _Billing();
        addTearDown(billing.dispose);
        await _pumpBody(tester, billing, night: night);
        // The host sheet owns its title; no duplicate or rotating teaser here.
        expect(find.text('Bara Gold'), findsNothing);
        expect(find.byType(PageView), findsNothing);
        expect(find.byType(CoinGlyph), findsOneWidget);
        final hero = find.byKey(const Key('bara-gold-paywall-hero'));
        var previousBottom = tester.getBottomLeft(hero).dy;
        expect(tester.getSize(hero).height, closeTo(114, 0.01));
        for (final benefit in BaraGoldBenefit.values) {
          final tile = find.byKey(Key('gold-benefit-${benefit.id}'));
          expect(tile, findsOneWidget);
          expect(find.descendant(of: tile, matching: find.text(benefit.title)), findsOneWidget);
          expect(find.descendant(of: tile, matching: find.text(benefit.detail)), findsOneWidget);
          expect(tester.getTopLeft(tile).dy, greaterThan(previousBottom));
          previousBottom = tester.getBottomLeft(tile).dy;
        }
        expect(find.byKey(const Key('plan-weekly')), findsOneWidget);
        expect(find.byKey(const Key('plan-monthly')), findsOneWidget);
        expect(find.byKey(const Key('plan-annual')), findsNothing);
        expect(find.byKey(const Key('plan-permanent')), findsNothing);
        expect(find.text(r'$1.49'), findsOneWidget);
        expect(find.text(r'$3.99'), findsOneWidget);
        expect(find.text('BEST DEAL'), findsOneWidget);
        final cta = tester.widget<PillButton>(find.byKey(const Key('start-bara-trial')));
        expect(cta.variant, PillButtonVariant.secondary);
        expect(cta.onPressed, isNotNull);
        expect(find.textContaining('Auto-renews until cancelled.'), findsOneWidget);
        expect(find.byKey(const Key('restore-bara')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('large text grows plan cards without changing the two-plan layout', (
    tester,
  ) async {
    final billing = _Billing();
    addTearDown(billing.dispose);
    await _pumpBody(tester, billing, standalone: true, scale: 2);
    expect(find.text('Bara Gold'), findsOneWidget);
    final weekly = find.byKey(const Key('bara-gold-weekly-slot'));
    final monthly = find.byKey(const Key('bara-gold-monthly-slot'));
    expect(tester.getSize(weekly).height, 300);
    expect(tester.getSize(monthly).height, 300);
    expect(tester.getTopLeft(weekly).dy, tester.getTopLeft(monthly).dy);
    expect(tester.takeException(), isNull);
  });

  testWidgets('active and unavailable states retain their original controls', (
    tester,
  ) async {
    final billing = _Billing()
      ..state = const BillingSnapshot(
        status: BillingStatus.active,
        plan: BillingPlan.monthly,
        givesAccess: true,
      );
    addTearDown(billing.dispose);
    await _pumpBody(tester, billing);
    expect(find.byKey(const Key('manage-bara')), findsOneWidget);
    expect(find.byKey(const Key('restore-bara')), findsOneWidget);
    expect(find.byKey(const Key('start-bara-trial')), findsNothing);
    expect(find.byKey(const Key('gold-benefit-adfree')), findsNothing);
    billing.state = const BillingSnapshot();
    billing.offers = [];
    await _pumpBody(tester, billing);
    expect(find.text('Store pricing is currently unavailable.'), findsOneWidget);
    expect(find.byKey(const Key('subscribe-bara')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
