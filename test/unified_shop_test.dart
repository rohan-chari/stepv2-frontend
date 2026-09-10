import 'support/shop_navigation.dart';
import 'package:flutter/material.dart';
import 'package:step_tracker/models/billing.dart';
import 'package:step_tracker/screens/tabs/profile_tab.dart';
import 'package:step_tracker/screens/bara_plus_screen.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/pill_button.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/billing_scope.dart';
import 'package:step_tracker/widgets/coin_pack_offers.dart';
import 'billing_components_test.dart' show FakeBilling;

class ShopApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchShopCharacters({
    required String identityToken,
    int limit = 24,
    String? cursor,
    String? localDate,
  }) async => {
    'contract': 'character-wardrobes-v1',
    'appearanceRevision': 0,
    'activeCharacterKey': 'default',
    'activeCharacterVisible': true,
    'coins': 100,
    'characters': [
      {
        'characterKey': 'default',
        'name': 'Capybara',
        'item': null,
        'owned': true,
        'active': true,
        'canPurchase': false,
        'canActivate': true,
        'canEdit': true,
        'availability': 'available',
        'outfit': {
          'revision': 0,
          'editable': true,
          'hasHiddenItems': false,
          'slots': {
            'HEAD': null,
            'FACE': null,
            'NECK': null,
            'BACK': null,
            'FEET': null,
          },
          'items': [],
          'unavailableItemIds': [],
        },
      },
    ],
    'nextCursor': null,
  };

  @override
  Future<Map<String, dynamic>> fetchShopCatalog({
    required String identityToken,
  }) async => {'coins': 100, 'items': [], 'ownedItemIds': [], 'equipped': {}};
  @override
  Future<Map<String, dynamic>> fetchPowerupShopCatalog({
    required String identityToken,
  }) async => {
    'coins': 100,
    'items': [
      {
        'sku': 'PW_TEST',
        'name': 'Shield',
        'description': 'Protect your steps',
        'priceCoins': 50,
        'powerupType': 'STEALTH_MODE',
      },
    ],
  };
  @override
  Future<Map<String, dynamic>> fetchPowerupInventory({
    required String identityToken,
  }) async => {'items': []};
}

class AvailabilityBilling extends FakeBilling {
  bool packs = false;
  bool membership = false;
  List<CoinPackOffer>? offers;
  @override
  bool get isPreview => false;
  @override
  bool get isAvailable => packs || membership;
  @override
  List<CoinPackOffer> get coinPacks =>
      packs ? (offers ?? CoinPackOffer.previewOffers) : [];
  @override
  List<StorePlanOffer> get plans =>
      membership ? StorePlanOffer.previewOffers : [];
  @override
  Future<void> refresh() async {
    packs = true;
    membership = true;
    notifyListeners();
  }
}

Future<AuthService> shopAuth({bool tutorialDue = false}) async {
  final auth = AuthService();
  await auth.restoreSession();
  if (tutorialDue) {
    await auth.syncFromBackendUser({
      'id': 'user',
      'shopTutorialCompletedAt': null,
    }, authoritative: true);
  }
  return auth;
}

Future<void> pumpShop(
  WidgetTester tester, {
  FakeBilling? billing,
  ShopFocus focus = ShopFocus.featured,
  bool tutorialDue = false,
  double width = 390,
  double textScale = 1,
  AppPalette? palette,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  final auth = await shopAuth(tutorialDue: tutorialDue);
  final child = MaterialApp(
    theme: ThemeData(extensions: [palette ?? AppPalette.light]),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        padding: const EdgeInsets.only(bottom: 34),
      ),
      child: child!,
    ),
    home: ShopTab(
      authService: auth,
      backendApiService: ShopApi(),
      initialFocus: focus,
    ),
  );
  await tester.pumpWidget(
    billing == null
        ? BillingScope.disabled(child: child)
        : BillingScope(controller: billing, child: child),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
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
    SharedPreferences.setMockInitialValues({
      'auth_identity_token': 'token',
      'auth_user_identifier': 'apple',
      'auth_session_token': 'session',
      'auth_backend_user_id': 'user',
      'auth_coins': 100,
    });
  });
  testWidgets('default Shop unifies purchases and keeps Items reachable', (
    tester,
  ) async {
    final auth = AuthService();
    await auth.restoreSession();
    await tester.pumpWidget(
      BillingScope(
        controller: FakeBilling(),
        child: MaterialApp(
          home: ShopTab(authService: auth, backendApiService: ShopApi()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Featured'), findsOneWidget);
    expect(find.byType(CoinPackOffers), findsOneWidget);
    expect(find.byKey(const Key('shop-membership-toggle')), findsOneWidget);
    expect(find.text('INVENTORY'), findsNothing);
    expect(find.byKey(const Key('shop-bottom-navigation')), findsNothing);
    expect(find.byKey(const Key('shop-section-characters')), findsOneWidget);
    await selectShopCategory(tester, 'POWERUPS');
    await tester.pump();
    expect(find.text('INVENTORY'), findsNothing);
    expect(find.byKey(const Key('shop-bottom-navigation')), findsNothing);
    expect(find.byKey(const Key('shop-section-characters')), findsOneWidget);
    expect(find.byType(CoinPackOffers), findsOneWidget);
  });
  testWidgets('coin pack artwork replaces placeholder icons', (tester) async {
    await tester.pumpWidget(
      BillingScope(
        controller: FakeBilling(),
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: CoinPackOffers())),
        ),
      ),
    );
    expect(find.byIcon(Icons.pets_rounded), findsNothing);
    for (final tier in ['small', 'medium', 'large']) {
      expect(
        find.image(AssetImage('assets/images/shop/coin_sack_$tier.png')),
        findsOneWidget,
      );
    }
  });
  for (final focus in [ShopFocus.coins, ShopFocus.membership]) {
    testWidgets(
      'explicit ${focus.name} defers first visit tutorial until Items',
      (tester) async {
        addTearDown(tester.view.reset);
        await pumpShop(
          tester,
          billing: FakeBilling(),
          focus: focus,
          tutorialDue: true,
        );
        expect(find.byKey(const Key('tutorial-callout-card')), findsNothing);
        expect(find.byType(CoinPackOffers), findsOneWidget);
        expect(
          find.byType(BaraPlusBody),
          focus == ShopFocus.membership ? findsOneWidget : findsNothing,
        );
        await closeShopMembership(tester);
        await tester.drag(
          find.byType(CustomScrollView).first,
          const Offset(0, -450),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
        expect(find.byKey(const Key('tutorial-callout-card')), findsOneWidget);
      },
    );
  }
  testWidgets('normal first visit mounts Items tutorial', (tester) async {
    addTearDown(tester.view.reset);
    await pumpShop(tester, billing: FakeBilling(), tutorialDue: true);
    expect(find.text('INVENTORY'), findsNothing);
    expect(find.byKey(const Key('shop-bottom-navigation')), findsNothing);
    expect(find.byKey(const Key('shop-section-characters')), findsOneWidget);
    expect(find.byKey(const Key('tutorial-callout-card')), findsOneWidget);
  });
  testWidgets('missing billing keeps Items and shows no sample prices', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await pumpShop(tester);
    expect(find.text('Coin packs are currently unavailable.'), findsOneWidget);
    expect(find.byKey(const Key('buy-coins-coins_500')), findsNothing);
    await selectShopCategory(tester, 'POWERUPS');
    await tester.pump();
    expect(find.text('INVENTORY'), findsNothing);
    expect(find.byKey(const Key('shop-bottom-navigation')), findsNothing);
    expect(find.byKey(const Key('shop-section-characters')), findsOneWidget);
  });
  testWidgets('sections recover independently from unavailable store', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final billing = AvailabilityBilling();
    await pumpShop(tester, billing: billing);
    expect(find.text('Membership is currently unavailable.'), findsOneWidget);
    expect(find.text('Coin packs are currently unavailable.'), findsOneWidget);
    await tester.tap(find.text('Try again').first);
    await tester.pump();
    expect(find.byKey(const Key('shop-membership-toggle')), findsOneWidget);
    expect(find.byKey(const Key('buy-coins-coins_500')), findsOneWidget);
    billing.membership = false;
    billing.update(billing.state);
    await tester.pump();
    expect(find.text('Membership is currently unavailable.'), findsOneWidget);
    expect(find.byKey(const Key('buy-coins-coins_500')), findsOneWidget);
    billing.membership = true;
    billing.packs = false;
    billing.update(billing.state);
    await tester.pump();
    expect(find.byKey(const Key('shop-membership-toggle')), findsOneWidget);
    expect(find.text('Coin packs are currently unavailable.'), findsOneWidget);
  });
  testWidgets('unknown product keeps verified amount price and generic sack', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final billing = AvailabilityBilling()
      ..packs = true
      ..offers = const [
        CoinPackOffer(id: 'future_pack', coins: 777, price: '€2,49'),
      ];
    await pumpShop(tester, billing: billing);
    expect(find.text('777'), findsOneWidget);
    expect(find.text('Buy · €2,49'), findsOneWidget);
    expect(
      find.image(const AssetImage('assets/images/shop/coin_sack_small.png')),
      findsOneWidget,
    );
    expect(find.text('BEST VALUE'), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('buy-coins-future_pack')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('buy-coins-future_pack')));
    await tester.pump();
    expect(billing.purchased?.id, 'future_pack');
    expect(billing.purchased?.coins, 777);
  });
  testWidgets('loading has skeletons without invented prices', (tester) async {
    addTearDown(tester.view.reset);
    final billing = AvailabilityBilling()
      ..state = const BillingSnapshot(
        operationStatus: BillingOperationStatus.loading,
      );
    await pumpShop(tester, billing: billing);
    expect(find.text('Finding your coin packs…'), findsOneWidget);
    expect(find.byKey(const Key('buy-coins-coins_500')), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'embedded membership keeps plans without repeating marketing hero',
    (tester) async {
      addTearDown(tester.view.reset);
      await pumpShop(
        tester,
        billing: FakeBilling(),
        focus: ShopFocus.membership,
      );
      expect(find.text('A LITTLE EXTRA JOY'), findsNothing);
      expect(find.text('For you. For your capy.'), findsNothing);
      expect(find.text('THE MONTHLY LOOK'), findsOneWidget);
      expect(find.byKey(const Key('plan-monthly')), findsOneWidget);
      expect(find.byKey(const Key('restore-bara')), findsOneWidget);
    },
  );
  testWidgets('narrow enlarged membership stacks cosmetic and plan choices', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await pumpShop(
      tester,
      billing: FakeBilling(),
      focus: ShopFocus.membership,
      width: 320,
      textScale: 1.6,
    );
    final art = find.image(
      const AssetImage('assets/images/accessories/wizard_hat.png'),
    );
    expect(
      tester.getBottomLeft(art).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.text('THE MONTHLY LOOK')).dy),
    );
    final monthly = find.byKey(const Key('plan-monthly'));
    final permanent = find.byKey(const Key('plan-permanent'));
    expect(
      tester.getBottomLeft(monthly).dy,
      lessThan(tester.getTopLeft(permanent).dy),
    );
    expect(tester.getSize(monthly).width, tester.getSize(permanent).width);
    expect(find.text('Something to show off'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('shared pending checkout blocks membership and all coin offers', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final billing = FakeBilling();
    await pumpShop(tester, billing: billing, focus: ShopFocus.membership);
    billing.update(
      const BillingSnapshot(
        operationStatus: BillingOperationStatus.pending,
        message: 'Waiting for approval',
      ),
    );
    await tester.pump();
    for (final key in [
      'start-bara-trial',
      'buy-coins-coins_500',
      'buy-coins-coins_2800',
      'buy-coins-coins_6000',
    ]) {
      expect(tester.widget<PillButton>(find.byKey(Key(key))).onPressed, isNull);
    }
    expect(find.text('Check purchase status'), findsWidgets);
    billing.update(const BillingSnapshot());
    await tester.pump();
    expect(
      tester
          .widget<PillButton>(find.byKey(const Key('start-bara-trial')))
          .onPressed,
      isNotNull,
    );
  });
  testWidgets(
    'Profile omits Membership while Featured retains embedded management',
    (tester) async {
      addTearDown(tester.view.reset);
      final auth = await shopAuth();
      final billing = FakeBilling()
        ..state = const BillingSnapshot(
          status: BillingStatus.active,
          plan: BillingPlan.monthly,
        );
      await tester.pumpWidget(
        BillingScope(
          controller: billing,
          child: MaterialApp(
            home: ProfileTab(
              authService: auth,
              displayName: 'Walker',
              onSettingsChanged: () {},
              backendApiService: ShopApi(),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Membership'), findsNothing);
      await pumpShop(tester, billing: billing, focus: ShopFocus.membership);
      expect(find.byType(ShopTab), findsOneWidget);
      expect(find.byType(BaraPlusBody), findsOneWidget);
      expect(find.byType(BaraPlusScreen), findsNothing);
      expect(find.byKey(const Key('manage-bara')), findsOneWidget);
    },
  );
  for (final width in [320.0, 390.0]) {
    for (final palette in [AppPalette.light, AppPalette.night]) {
      testWidgets(
        'Shop fits $width large text ${palette == AppPalette.light ? "day" : "night"}',
        (tester) async {
          addTearDown(tester.view.reset);
          await pumpShop(
            tester,
            billing: FakeBilling(),
            width: width,
            textScale: 1.8,
            palette: palette,
            focus: ShopFocus.membership,
          );
          expect(tester.takeException(), isNull);
          await closeShopMembership(tester);
          await tester.ensureVisible(
            find.byKey(const Key('buy-coins-coins_6000')),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(
            tester.getSize(find.byKey(const Key('coin-tile-coins_500'))).width,
            tester.getSize(find.byKey(const Key('coin-tile-coins_6000'))).width,
          );
          await selectShopCategory(tester, 'POWERUPS');
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
