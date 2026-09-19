import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/models/billing.dart';
import 'package:step_tracker/services/billing_controller.dart';
import 'package:step_tracker/widgets/bara_plus_card.dart';
import 'package:step_tracker/widgets/home_course_track.dart';

class _GoldCardBilling extends BillingController {
  @override
  String get userId => 'user';

  @override
  bool get isPreview => true;

  @override
  BillingSnapshot get snapshot => const BillingSnapshot(coins: 100);

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
  }) async => throw UnimplementedError();
}

void main() {
  testWidgets('Bara Gold card uses live capybara with only the cape accessory', (
    tester,
  ) async {
    final billing = _GoldCardBilling();
    addTearDown(billing.dispose);
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 390,
              child: BaraPlusCard(
                controller: billing,
                onTap: () => tapped = true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Bara Gold'), findsOneWidget);
    expect(find.text('Ad-free. Exclusive perks.'), findsOneWidget);
    expect(find.text('Upgrade to Bara Gold'), findsOneWidget);
    expect(find.byKey(const Key('bara-gold-cape-avatar')), findsOneWidget);
    expect(find.byKey(const Key('bara-gold-upgrade-cta')), findsOneWidget);

    final avatar = tester.widget<AnimatedCapybaraWithAccessories>(
      find.byType(AnimatedCapybaraWithAccessories),
    );
    expect(avatar.animal, isNull);
    expect(avatar.accessories, hasLength(1));
    expect(avatar.accessories.single['slot'], 'BACK');
    expect(avatar.accessories.single['assetKey'], 'cape');
    expect(
      (avatar.accessories.single['renderMetadata'] as Map)['renderLayer'],
      'behind',
    );

    await tester.tap(find.byKey(const Key('bara-plus-card')));
    expect(tapped, isTrue);
  });
}
