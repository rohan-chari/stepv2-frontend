import 'dart:async';
import 'dart:ui' show SemanticsAction;
import 'package:step_tracker/styles.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/preview/preview_billing_controller.dart';
import 'package:step_tracker/services/live_billing_controller.dart';
import 'package:step_tracker/services/store_billing_client.dart';
import 'live_billing_test.dart' show TestAuth, TestApi, TestStore;
import 'package:step_tracker/models/billing.dart';
import 'package:step_tracker/screens/bara_plus_screen.dart';
import 'package:step_tracker/screens/get_coins_screen.dart';
import 'package:step_tracker/services/billing_controller.dart';
import 'package:step_tracker/widgets/billing_scope.dart';
import 'package:step_tracker/widgets/coin_pack_offers.dart';
import 'package:step_tracker/widgets/game_toast.dart';

class ToastBilling extends BillingController {
  String account = 'one';
  BillingSnapshot state = const BillingSnapshot();
  Future<BillingResult> Function() action = () async =>
      const BillingResult(success: true, message: 'Purchase verified');
  @override
  String get userId => account;
  @override
  bool get isPreview => true;
  @override
  BillingSnapshot get snapshot => state;
  void announce() => notifyListeners();
  @override
  Future<BillingResult> buyCoins(CoinPackOffer pack) => action();
  @override
  Future<BillingResult> restore() => action();
  @override
  Future<BillingResult> startTrial(BillingPlan plan) => action();
  @override
  Future<BillingResult> subscribe(BillingPlan plan) => action();
  @override
  Future<BillingResult> cancelRenewal() => action();
  @override
  Future<BillingRerollResult> reroll({
    required String raceId,
    required List<String> ids,
    required RerollFunding funding,
  }) async => const BillingRerollResult(success: false, message: 'Unavailable');
}

Widget host(ToastBilling billing, {bool membership = false}) => MaterialApp(
  home: BillingScope(
    controller: billing,
    child: Scaffold(
      body: SingleChildScrollView(
        child: membership ? const BaraPlusBody() : const CoinPackOffers(),
      ),
    ),
  ),
);

class CancelledStore extends TestStore {
  @override
  Future<String?> purchase(String productId) async =>
      throw const StoreBillingException('Checkout closed', cancelled: true);
}

class ToastCoinsApi extends TestApi {
  @override
  Future<Map<String, dynamic>> fetchDailyRewardStatus({
    required String identityToken,
    required String localDate,
  }) async => {'claimedToday': false, 'ladder': <dynamic>[]};

  @override
  Future<Map<String, dynamic>> fetchReferralStatus({
    required String identityToken,
  }) async => {};
}

void main() {
  setUp(
    () => PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'test',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    ),
  );

  testWidgets(
    'coin card supports one accessible checkout action and disables it while pending',
    (tester) async {
      final handle = tester.ensureSemantics();
      final pending = Completer<BillingResult>();
      var calls = 0;
      final billing = ToastBilling()
        ..action = () {
          calls++;
          return pending.future;
        };
      await tester.pumpWidget(host(billing));
      final target = find.bySemanticsLabel(r'Buy 500 coins for $0.99');
      expect(target, findsOneWidget);
      final node = tester.getSemantics(target);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      node.owner!.performAction(
        node.id,
        SemanticsAction.tap,
      );
      await tester.pump();
      expect(calls, 1);
      expect(
        tester
            .getSemantics(target)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse,
      );
      await tester.tap(find.byKey(const Key('buy-coins-coins_500')));
      expect(calls, 1);
      pending.complete(
        const BillingResult(success: true, message: 'Purchase verified'),
      );
      await tester.pump();
      expect(
        tester
            .getSemantics(target)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      handle.dispose();
      billing.dispose();
    },
  );

  testWidgets(
    'coin purchase uses a themed price strip and a transient success toast',
    (tester) async {
      final billing = ToastBilling();
      await tester.pumpWidget(host(billing));
      final buy = find.byKey(const Key('buy-coins-coins_500'));
      expect(tester.widget<InkWell>(buy).onTap, isNotNull);
      expect(find.text(r'$0.99'), findsOneWidget);
      expect(find.text(r'Buy · $0.99'), findsNothing);
      final strip = tester.widget<Container>(
        find.byKey(const Key('coin-price-strip-coins_500')),
      );
      final decoration = strip.decoration! as BoxDecoration;
      final colors = AppColors.of(tester.element(buy));
      expect(decoration.color, colors.pillGold.withValues(alpha: .22));
      await tester.tap(buy);
      await tester.pump();
      expect(find.byKey(const Key('info-toast-shell')), findsOneWidget);
      expect(find.text('Purchase verified'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      billing.announce();
      await tester.pump();
      expect(find.text('Purchase verified'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      billing.dispose();
    },
  );

  testWidgets('purchase toast disappears when another route covers checkout', (
    tester,
  ) async {
    final billing = ToastBilling();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(body: CoinPackOffers(controller: billing)),
      ),
    );
    await tester.tap(find.byKey(const Key('buy-coins-coins_500')));
    await tester.pump();
    expect(find.text('Purchase verified'), findsOneWidget);
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Another screen')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Purchase verified'), findsNothing);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Purchase verified'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    billing.dispose();
  });

  testWidgets(
    'standalone Get Coins shows checkout toast and drops completion after exit',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final billing = ToastBilling();
      final auth = TestAuth();
      final api = ToastCoinsApi();
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        BillingScope(
          controller: billing,
          child: MaterialApp(
            navigatorKey: navigator,
            home: const Scaffold(body: Text('App origin')),
          ),
        ),
      );
      Future<void> openCoins() async {
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) =>
                GetCoinsScreen(authService: auth, backendApiService: api),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.ensureVisible(
          find.byKey(const Key('buy-coins-coins_500')),
        );
        await tester.pump();
      }

      await openCoins();
      await tester.tap(find.byKey(const Key('buy-coins-coins_500')));
      await tester.pump();
      expect(find.byKey(const Key('info-toast-shell')), findsOneWidget);
      expect(find.text('Purchase verified'), findsOneWidget);
      navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.byType(GetCoinsScreen), findsNothing);
      expect(find.text('App origin'), findsOneWidget);
      expect(find.text('Purchase verified'), findsNothing);

      final pending = Completer<BillingResult>();
      var checkouts = 0;
      billing.action = () {
        checkouts++;
        return pending.future;
      };
      await openCoins();
      await tester.tap(find.byKey(const Key('buy-coins-coins_500')));
      await tester.pump();
      expect(checkouts, 1);
      navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.byType(GetCoinsScreen), findsNothing);
      expect(find.text('App origin'), findsOneWidget);
      pending.complete(
        const BillingResult(success: true, message: 'Late coin checkout'),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Late coin checkout'), findsNothing);
      expect(find.byKey(const Key('info-toast-shell')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      billing.dispose();
      auth.dispose();
    },
  );

  testWidgets(
    'anchored purchase toast never intercepts header during entrance',
    (tester) async {
      final billing = ToastBilling();
      var headerTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: GameToastAnchor(
            top: 100,
            child: Scaffold(
              body: Column(
                children: [
                  SizedBox(
                    height: 100,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => headerTaps++,
                        child: const Text('Back'),
                      ),
                    ),
                  ),
                  const Expanded(child: SizedBox()),
                  CoinPackOffers(controller: billing),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('buy-coins-coins_500')));
      await tester.pump();
      for (final milliseconds in [0, 80, 80, 120, 180]) {
        await tester.pump(Duration(milliseconds: milliseconds));
        final before = headerTaps;
        await tester.tapAt(tester.getCenter(find.text('Back')));
        expect(
          headerTaps,
          before + 1,
          reason: 'header stays reachable during toast motion',
        );
      }
      await tester.pumpWidget(const SizedBox());
      billing.dispose();
    },
  );

  testWidgets('failed coin purchase shows error toast and permits retry', (
    tester,
  ) async {
    final billing = ToastBilling()
      ..action = () async =>
          const BillingResult(success: false, message: 'Store unavailable');
    await tester.pumpWidget(host(billing));
    final buy = find.byKey(const Key('buy-coins-coins_500'));
    await tester.tap(buy);
    await tester.pump();
    expect(find.byKey(const Key('error-toast-shell')), findsOneWidget);
    expect(find.text('Store unavailable'), findsOneWidget);
    expect(tester.widget<InkWell>(buy).onTap, isNotNull);
    await tester.pumpWidget(const SizedBox());
    billing.dispose();
  });

  testWidgets(
    'Bara restore feedback is a toast and is removed with its route',
    (tester) async {
      final billing = ToastBilling();
      await tester.pumpWidget(host(billing, membership: true));
      final restore = find.byKey(const Key('restore-bara'));
      await tester.ensureVisible(restore);
      await tester.tap(restore);
      await tester.pump();
      expect(find.byKey(const Key('info-toast-shell')), findsOneWidget);
      expect(find.text('Purchase verified'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 4));
      expect(tester.takeException(), isNull);
      billing.dispose();
    },
  );

  testWidgets(
    'preview pending checkout shows completion once through the real controller',
    (tester) async {
      final billing = PreviewBillingController()..simulateNextPending();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CoinPackOffers(controller: billing)),
        ),
      );
      await tester.tap(find.byKey(const Key('buy-coins-coins_500')));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(find.text('Check purchase status'), findsOneWidget);
      expect(find.byKey(const Key('error-toast-shell')), findsNothing);
      billing.finishPending();
      await tester.pump();
      expect(find.byKey(const Key('info-toast-shell')), findsOneWidget);
      expect(
        find.text('Preview purchase completed. No payment was taken.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoinPackOffers(
              key: const Key('reopened'),
              controller: billing,
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('info-toast-shell')), findsNothing);
      expect(
        find.text('Preview purchase completed. No payment was taken.'),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      billing.dispose();
    },
  );

  testWidgets(
    'native cancelled checkout is neutral and leaves purchase control usable',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final billing = LiveBillingController(
        auth: TestAuth(),
        api: TestApi(),
        store: CancelledStore(),
        platform: 'ios',
      );
      await billing.refresh();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CoinPackOffers(controller: billing)),
        ),
      );
      final buy = find.byKey(const Key('buy-coins-coins_500'));
      await tester.tap(buy);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('error-toast-shell')), findsNothing);
      expect(find.text('Checkout closed'), findsNothing);
      expect(tester.widget<InkWell>(buy).onTap, isNotNull);
      await tester.pumpWidget(const SizedBox());
      billing.dispose();
    },
  );

  testWidgets('native pending checkout reconciles into one success toast', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = TestStore()..pendingError = true;
    final api = TestApi();
    final billing = LiveBillingController(
      auth: TestAuth(),
      api: api,
      store: store,
      platform: 'ios',
    );
    await billing.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CoinPackOffers(controller: billing)),
      ),
    );
    await tester.tap(find.byKey(const Key('buy-coins-coins_500')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Check purchase status'), findsOneWidget);
    expect(find.byKey(const Key('error-toast-shell')), findsNothing);
    store.nativeTransactions.add('new-transaction');
    await billing.refresh();
    await tester.pump();
    expect(find.byKey(const Key('info-toast-shell')), findsOneWidget);
    expect(find.textContaining('Purchase reconciled.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    billing.dispose();
  });

  for (final membership in [false, true]) {
    testWidgets(
      'late ${membership ? 'membership' : 'coin'} completion cannot notify another account',
      (tester) async {
        final pending = Completer<BillingResult>();
        final billing = ToastBilling()..action = () => pending.future;
        await tester.pumpWidget(host(billing, membership: membership));
        final action = find.byKey(
          Key(membership ? 'restore-bara' : 'buy-coins-coins_500'),
        );
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pump();
        billing.account = 'two';
        billing.announce();
        await tester.pump();
        pending.complete(
          const BillingResult(success: true, message: 'Old account result'),
        );
        await tester.pump();
        expect(find.text('Old account result'), findsNothing);
        expect(find.byKey(const Key('info-toast-shell')), findsNothing);
        await tester.pumpWidget(const SizedBox());
        billing.dispose();
      },
    );
  }
}
