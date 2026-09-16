import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/billing.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'package:step_tracker/widgets/billing_scope.dart';
import 'unified_shop_test.dart' show ShopApi;
import 'package:step_tracker/screens/bara_plus_screen.dart';
import 'package:step_tracker/services/live_billing_controller.dart';
import 'package:step_tracker/services/store_billing_client.dart';
import 'live_billing_test.dart';
import 'package:step_tracker/preview/preview_billing_controller.dart';

class PermanentApi extends TestApi {}

class PermanentStore extends TestStore {
  List<String> nonSubscriptions = [];
  int manages = 0;
  @override
  Future<void> manage() async {
    manages++;
  }

  @override
  Future<List<StoreBillingProduct>> products(
    List<String> coins,
    List<String> subscriptions,
  ) async {
    nonSubscriptions = coins;
    return [
      ...await super.products(coins, subscriptions),
    ];
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<void> screen(
    WidgetTester tester,
    LiveBillingController billing,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(billing.dispose);
    await billing.refresh();
    await tester.pumpWidget(
      MaterialApp(home: BaraPlusScreen(controller: billing)),
    );
    await tester.pump();
  }

  testWidgets(
    'retired permanent and annual products are not offered by the Gold screen',
    (tester) async {
      final api = PermanentApi()..fixedCoins = 100;
      final store = PermanentStore()..eligible = true;
      final billing = LiveBillingController(
        auth: TestAuth(),
        api: api,
        store: store,
        platform: 'ios',
      );
      await screen(tester, billing);
      expect(store.nonSubscriptions, isNot(contains('permanent')));
      expect(billing.coinPacks.map((p) => p.id), isNot(contains('plus_permanent')));
      expect(find.byKey(const Key('plan-annual')), findsNothing);
      expect(find.byKey(const Key('plan-permanent')), findsNothing);
      expect(find.byKey(const Key('buy-permanent-bara')), findsNothing);
      expect(find.textContaining('One-time payment'), findsNothing);
      expect(billing.snapshot.coins, 100);
      expect(find.text('Bara Gold'), findsOneWidget);
    },
  );
  for (final overlap in [false, true]) {
    testWidgets(
      'permanent ownership and subscription overlap $overlap remain distinct',
      (tester) async {
        final api = PermanentApi()
          ..fixedCoins = 100
          ..membership = {
            'status': 'active',
            'plan': 'permanent',
            'givesAccess': true,
            'renews': false,
            'accessUntil': null,
            'nextRewardAt': '2030-05-31T10:00:00Z',
            'subscription': overlap
                ? {
                    'status': 'active',
                    'plan': 'monthly',
                    'givesAccess': true,
                    'renews': true,
                    'accessUntil': '2030-05-31T10:00:00Z',
                  }
                : null,
          };
        final billing = LiveBillingController(
          auth: TestAuth(),
          api: api,
          store: PermanentStore(),
          platform: 'android',
        );
        await screen(tester, billing);
        expect(find.text('Bara Gold'), findsOneWidget);
        expect(find.textContaining('Next reward:'), findsNothing);
        expect(find.byKey(const Key('plan-monthly')), findsNothing);
        expect(find.byKey(const Key('plan-permanent')), findsNothing);
        expect(find.byKey(const Key('plan-annual')), findsNothing);
        expect(find.byKey(const Key('subscribe-bara')), findsNothing);
        expect(find.byKey(const Key('manage-bara')), findsOneWidget);
        expect(find.textContaining('Renewal cancelled.'), findsNothing);
        expect(find.textContaining('does not cancel'), findsNothing);
        expect(billing.snapshot.coins, 100);
        expect(billing.snapshot.paidCredits, 0);
      },
    );
  }
  testWidgets(
    'legacy annual access is recognized without offering annual sales',
    (tester) async {
      final api = PermanentApi()
        ..fixedCoins = 100
        ..membership = {
          'status': 'active',
          'plan': 'annual',
          'givesAccess': true,
          'renews': true,
          'accessUntil': '2030-05-31T10:00:00Z',
        };
      final billing = LiveBillingController(
        auth: TestAuth(),
        api: api,
        store: PermanentStore(),
        platform: 'ios',
      );
      await screen(tester, billing);
      expect(find.text('Bara Gold'), findsOneWidget);
      expect(find.byKey(const Key('manage-bara')), findsOneWidget);
      expect(find.byKey(const Key('plan-annual')), findsNothing);
      expect(find.byKey(const Key('plan-permanent')), findsNothing);
      expect(billing.plans.any((p) => p.plan == BillingPlan.annual), false);
    },
  );
  testWidgets(
    'permanent native pending survives refresh without an exact new transaction',
    (tester) async {
      final api = PermanentApi()..fixedCoins = 100;
      final store = PermanentStore()..pendingError = true;
      final billing = LiveBillingController(
        auth: TestAuth(),
        api: api,
        store: store,
        platform: 'ios',
      );
      await screen(tester, billing);
      await billing.refresh();
      await tester.pump();
      expect(billing.snapshot.operationStatus, BillingOperationStatus.success);
      expect(billing.snapshot.isMember, false);
      expect(billing.snapshot.coins, 100);
      expect(billing.snapshot.paidCredits, 0);
      expect(find.byKey(const Key('plan-permanent')), findsNothing);
      expect(billing.snapshot.coins, 100);
    },
  );
  testWidgets(
    'preview exposes permanent and overlapping subscription fixtures on the real screen',
    (tester) async {
      final billing = PreviewBillingController();
      addTearDown(billing.dispose);
      final fixture = PreviewBillingScenario.values.where(
        (s) => s.name == 'permanentWithMonthly',
      );
      expect(fixture, hasLength(1));
      billing.setScenario(fixture.single);
      await tester.pumpWidget(
        MaterialApp(home: BaraPlusScreen(controller: billing)),
      );
      expect(find.text('Bara Gold'), findsOneWidget);
      expect(find.byKey(const Key('plan-permanent')), findsNothing);
      expect(find.byKey(const Key('plan-annual')), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('manage-bara')));
      expect(find.byKey(const Key('manage-bara')), findsOneWidget);
      expect(find.byKey(const Key('subscribe-bara')), findsNothing);
      billing.setScenario(
        PreviewBillingScenario.values.singleWhere((s) => s.name == 'permanent'),
      );
      await tester.pump();
      expect(find.byKey(const Key('manage-bara')), findsOneWidget);
      expect(find.byKey(const Key('plan-permanent')), findsNothing);
    },
  );
  testWidgets(
    'missing permanent additions and unknown plans degrade without invented monthly rewards',
    (tester) async {
      final api = PermanentApi()
        ..fixedCoins = 100
        ..membership = {
          'status': 'active',
          'plan': 'future_plan',
          'givesAccess': true,
          'subscription': 'invalid',
          'nextRewardAt': false,
        };
      final billing = LiveBillingController(
        auth: TestAuth(),
        api: api,
        store: PermanentStore(),
        platform: 'ios',
      );
      await screen(tester, billing);
      expect(find.text('Bara Gold'), findsOneWidget);
      expect(find.text('500 coins each month'), findsNothing);
      expect(find.textContaining('Next reward:'), findsNothing);
      expect(find.textContaining('reroll credits'), findsNothing);
      expect(find.byKey(const Key('manage-bara')), findsOneWidget);
      expect(billing.snapshot.subscription, isNull);
      expect(tester.takeException(), isNull);
    },
  );
  for (final scenario in [
    PreviewBillingScenario.free,
    PreviewBillingScenario.trial,
    PreviewBillingScenario.monthly,
  ]) {
    testWidgets(
      'preview ${scenario.name} does not expose retired permanent purchase',
      (tester) async {
        tester.view.physicalSize = const Size(900, 2600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final billing = PreviewBillingController()..setScenario(scenario);
        addTearDown(billing.dispose);
        await tester.pumpWidget(
          MaterialApp(home: BaraPlusScreen(controller: billing)),
        );
        expect(find.byKey(const Key('plan-permanent')), findsNothing);
        expect(find.byKey(const Key('plan-annual')), findsNothing);
        expect(find.byKey(const Key('buy-permanent-bara')), findsNothing);
        expect(find.textContaining('reroll credits'), findsNothing);
      },
    );
  }
  testWidgets(
    'permanent ownership and overlap fit small phone with large text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final billing = PreviewBillingController()
        ..setScenario(PreviewBillingScenario.permanentWithMonthly);
      addTearDown(billing.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: BaraPlusScreen(controller: billing),
        ),
      );
      await tester.ensureVisible(find.byKey(const Key('manage-bara')));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('manage-bara')), findsOneWidget);
    },
  );
  for (final available in [true, false]) {
    testWidgets(
      'suspended renewing subscription remains manageable with checkout available $available',
      (tester) async {
        final api = PermanentApi()
          ..available = available
          ..fixedCoins = 100
          ..membership = {
            'status': 'active',
            'plan': 'permanent',
            'givesAccess': true,
            'renews': false,
            'subscription': {
              'status': 'expired',
              'plan': 'monthly',
              'givesAccess': false,
              'renews': true,
              'providerStatus': 'in_billing_retry',
              'accessUntil': '2020-01-01T00:00:00Z',
            },
          };
        final store = PermanentStore();
        final billing = LiveBillingController(
          auth: TestAuth(),
          api: api,
          store: store,
          platform: 'android',
        );
        await screen(tester, billing);
        expect(find.byKey(const Key('manage-bara')), findsOneWidget);
        expect(find.textContaining('currently unavailable'), findsNothing);
        await tester.tap(find.byKey(const Key('manage-bara')));
        await tester.pumpAndSettle();
        expect(store.manages, 1);
        expect(billing.snapshot.coins, 100);
        expect(billing.snapshot.isPermanent, true);
      },
    );
  }
  testWidgets(
    'known permanent owner retains direct management while Shop entry is hidden',
    (tester) async {
      final api = PermanentApi()
        ..available = false
        ..fixedCoins = 100
        ..membership = {
          'status': 'active',
          'plan': 'permanent',
          'givesAccess': true,
          'renews': false,
          'subscription': {
            'status': 'expired',
            'plan': 'monthly',
            'givesAccess': false,
            'renews': true,
          },
        };
      final store = PermanentStore();
      final billing = LiveBillingController(
        auth: TestAuth(),
        api: api,
        store: store,
        platform: 'android',
      );
      addTearDown(billing.dispose);
      await billing.refresh();
      await tester.pumpWidget(
        BillingScope(
          controller: billing,
          child: MaterialApp(
            home: ShopTab(
              authService: TestAuth(),
              backendApiService: ShopApi(),
              initialFocus: ShopFocus.membership,
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('shop-membership-toggle')), findsNothing);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(BaraPlusBody), findsNothing);
      await tester.pumpWidget(
        MaterialApp(home: BaraPlusScreen(controller: billing)),
      );
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('manage-bara')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('manage-bara')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(store.manages, 1);
      expect(find.byKey(const Key('buy-permanent-bara')), findsNothing);
    },
  );
  testWidgets(
    'paused subscription without renewal is not described as cancelled',
    (tester) async {
      final api = PermanentApi()
        ..fixedCoins = 100
        ..membership = {
          'status': 'active',
          'plan': 'permanent',
          'givesAccess': true,
          'renews': false,
          'subscription': {
            'status': 'expired',
            'plan': 'monthly',
            'givesAccess': false,
            'renews': false,
            'providerStatus': 'paused',
          },
        };
      final store = PermanentStore();
      final billing = LiveBillingController(
        auth: TestAuth(),
        api: api,
        store: store,
        platform: 'android',
      );
      await screen(tester, billing);
      expect(find.byKey(const Key('manage-bara')), findsOneWidget);
      expect(find.textContaining('cancelled'), findsNothing);
      expect(
        find.textContaining('Check your store for renewal and payment status.'),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('manage-bara')));
      await tester.pumpAndSettle();
      expect(store.manages, 1);
      expect(billing.snapshot.isPermanent, true);
    },
  );
}
