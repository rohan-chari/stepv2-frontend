import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/models/billing.dart';
import 'package:step_tracker/services/billing_controller.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/bara_plus_card.dart';
import 'package:step_tracker/widgets/billing_scope.dart';
import 'package:step_tracker/widgets/home_course_track.dart';
import 'package:step_tracker/widgets/home_hero_scene.dart';

class _CardBilling extends BillingController {
  bool membershipAvailable = true;

  @override
  String get userId => 'gold-card-preview';

  @override
  bool get isPreview => true;

  @override
  bool get canShowMembership => membershipAvailable;

  @override
  BillingSnapshot get snapshot => const BillingSnapshot(coins: 100);

  void setMembershipAvailable(bool available) {
    membershipAvailable = available;
    notifyListeners();
  }

  @override
  Future<BillingResult> buyCoins(CoinPackOffer pack) async =>
      throw StateError('The promo card must not initiate a purchase.');

  @override
  Future<BillingResult> startTrial(BillingPlan plan) async =>
      throw StateError('The promo card must not initiate a trial.');

  @override
  Future<BillingResult> subscribe(BillingPlan plan) async =>
      throw StateError('The promo card must not initiate a subscription.');

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

const _benefitTitles = [
  'Ad-free experience',
  'Exclusive characters',
  'Monthly coin bonus',
  'Free rerolls',
];

Future<void> _pumpCard(
  WidgetTester tester, {
  required _CardBilling billing,
  double width = 390,
  double height = 844,
  double textScale = 1,
  bool night = false,
  bool scoped = false,
  VoidCallback? onTap,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final palette = night ? AppPalette.night : AppPalette.light;
  Widget card = BaraPlusCard(
    controller: scoped ? null : billing,
    onTap: onTap,
  );
  if (scoped) card = BillingScope(controller: billing, child: card);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        brightness: night ? Brightness.dark : Brightness.light,
        extensions: [palette],
      ),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: card,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('compact hero keeps terrain scale and the benefits below it', (
    tester,
  ) async {
    final billing = _CardBilling();
    addTearDown(billing.dispose);
    await _pumpCard(tester, billing: billing);

    expect(find.text('Bara Gold'), findsOneWidget);
    expect(find.text('Ad-free. Exclusive perks.'), findsNothing);
    expect(find.text('Upgrade to Bara Gold'), findsOneWidget);
    for (final title in _benefitTitles) {
      expect(find.text(title), findsOneWidget);
    }
    final hero = find.byKey(const Key('bara-gold-hero-scene'));
    final viewport = find.byKey(const Key('bara-gold-hero-viewport'));
    final benefits = find.byKey(const Key('bara-gold-benefits'));
    final cta = find.byKey(const Key('bara-gold-upgrade-cta'));
    final scene = tester.widget<HomeHeroScene>(hero);
    expect(scene.groundHeight, 64);
    expect(scene.groundScrollSpeed, 24);
    expect(tester.getSize(hero).height, 206);
    expect(tester.getSize(viewport).height, closeTo(160, 0.01));
    expect(
      tester.getTopLeft(benefits).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(viewport).dy),
    );
    expect(
      tester.getTopLeft(cta).dy,
      greaterThan(tester.getBottomLeft(benefits).dy),
    );
    expect(find.byType(AnimatedCapybaraWithAccessories), findsOneWidget);
    final avatar = tester.widget<AnimatedCapybaraWithAccessories>(
      find.byType(AnimatedCapybaraWithAccessories),
    );
    expect(avatar.animate, isFalse);
    expect(avatar.size, 116);
    expect(avatar.accessories.single['assetKey'], 'cape');
    expect(tester.takeException(), isNull);
  });

  testWidgets('hero, perks and CTA retain the existing navigation callback', (
    tester,
  ) async {
    final billing = _CardBilling();
    addTearDown(billing.dispose);
    var taps = 0;
    await _pumpCard(tester, billing: billing, onTap: () => taps++);

    await tester.tap(find.text('Bara Gold'));
    expect(taps, 1);
    await tester.tap(find.text('Exclusive characters'));
    expect(taps, 2);
    final cta = find.byKey(const Key('bara-gold-upgrade-cta'));
    await tester.ensureVisible(cta);
    await tester.pump();
    await tester.tap(cta);
    expect(taps, 3);
    expect(tester.takeException(), isNull);
  });

  for (final night in [false, true]) {
    for (final layout in [
      (width: 320.0, height: 844.0, scale: 1.0),
      (width: 390.0, height: 844.0, scale: 1.0),
      (width: 320.0, height: 844.0, scale: 2.0),
      (width: 844.0, height: 390.0, scale: 1.0),
      (width: 844.0, height: 390.0, scale: 2.0),
    ]) {
      testWidgets(
        'perks and CTA fit ${layout.width}x${layout.height}px at ${layout.scale}x '
        'in ${night ? 'night' : 'light'} theme',
        (tester) async {
          final billing = _CardBilling();
          addTearDown(billing.dispose);
          await _pumpCard(
            tester,
            billing: billing,
            width: layout.width,
            height: layout.height,
            textScale: layout.scale,
            night: night,
          );

          // The scenery is compact in every orientation, not only when the
          // phone is rotated. Large text keeps extra room above the avatar.
          final tall = layout.scale > 1.35;
          expect(find.text('Ad-free. Exclusive perks.'), findsNothing);
          expect(find.text('Bara Gold'), findsOneWidget);
          expect(
            tester.getSize(find.byKey(const Key('bara-gold-hero-viewport'))).height,
            closeTo(tall ? 184 : 160, 0.01),
          );
          final scene = tester.widget<HomeHeroScene>(
            find.byKey(const Key('bara-gold-hero-scene')),
          );
          expect(scene.groundHeight, tall ? 70 : 64);
          final avatar = tester.widget<AnimatedCapybaraWithAccessories>(
            find.byType(AnimatedCapybaraWithAccessories),
          );
          expect(avatar.size, tall ? 128 : 116);

          final palette = night ? AppPalette.night : AppPalette.light;
          final panel = tester.widget<Container>(
            find.byKey(const Key('bara-gold-benefits')),
          );
          expect((panel.decoration as BoxDecoration).color, palette.parchment);
          final panelRect = tester.getRect(
            find.byKey(const Key('bara-gold-benefits')),
          );
          for (final title in _benefitTitles) {
            final finder = find.text(title);
            final text = tester.widget<Text>(finder);
            final rect = tester.getRect(finder);
            expect(text.maxLines, isNull);
            expect(rect.left, greaterThanOrEqualTo(panelRect.left));
            expect(rect.right, lessThanOrEqualTo(panelRect.right));
          }
          final cta = find.byKey(const Key('bara-gold-upgrade-cta'));
          await tester.ensureVisible(cta);
          await tester.pump();
          final ctaRect = tester.getRect(cta);
          final labelRect = tester.getRect(find.text('Upgrade to Bara Gold'));
          expect(ctaRect.height, greaterThanOrEqualTo(56));
          expect(labelRect.left, greaterThanOrEqualTo(ctaRect.left));
          expect(labelRect.right, lessThanOrEqualTo(ctaRect.right));
          expect(labelRect.top, greaterThanOrEqualTo(ctaRect.top));
          expect(labelRect.bottom, lessThanOrEqualTo(ctaRect.bottom));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('membership visibility still follows the billing scope', (
    tester,
  ) async {
    final billing = _CardBilling()..membershipAvailable = false;
    addTearDown(billing.dispose);
    await _pumpCard(tester, billing: billing, scoped: true);
    expect(find.byKey(const Key('bara-plus-card')), findsNothing);

    billing.setMembershipAvailable(true);
    await tester.pump();
    expect(find.byKey(const Key('bara-plus-card')), findsOneWidget);
    expect(find.byKey(const Key('bara-gold-benefits')), findsOneWidget);

    billing.setMembershipAvailable(false);
    await tester.pump();
    expect(find.byKey(const Key('bara-plus-card')), findsNothing);
    expect(find.byKey(const Key('bara-gold-benefits')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no controller still renders no membership card', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BaraPlusCard())),
    );
    expect(find.byKey(const Key('bara-plus-card')), findsNothing);
    expect(find.byKey(const Key('bara-gold-benefits')), findsNothing);
  });
}
