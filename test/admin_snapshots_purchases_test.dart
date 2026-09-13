import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/admin_dashboard_controller.dart';
import 'package:step_tracker/screens/admin_dashboard_detail.dart';
import 'package:step_tracker/screens/admin_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _Api extends BackendApiService {
  final statsCalls = <String>[];
  final purchaseCalls = <(String, String?)>[];
  final pending = <String, Completer<Map<String, dynamic>>>{};
  Map<String, dynamic> stats = {
    'generatedAt': '2026-09-13T12:00:00Z',
    'snapshot': {
      'generatedAt': '2026-09-13T12:00:00Z',
      'freshUntil': '2026-09-13T12:15:00Z',
      'status': 'stale',
      'refreshIntervalSeconds': 900,
    },
    'metricsDashboard': {'schemaVersion': 2, 'status': 'available'},
    'coinEconomy': {'purchasesBySku': []},
  };
  Map<String, dynamic> purchases = {'items': [], 'nextCursor': null};
  int? purchaseError;
  int? statsError;

  @override
  Future<Map<String, dynamic>> fetchAdminStats({
    required String identityToken,
    List<String> sections = const [],
    String? window,
  }) async {
    statsCalls.addAll(sections);
    if (statsError != null) {
      throw ApiException('Unavailable', statusCode: statsError);
    }
    return stats;
  }

  @override
  Future<Map<String, dynamic>> fetchAdminPurchases({
    required String identityToken,
    String kind = 'all',
    String environment = 'production',
    int limit = 20,
    String? cursor,
  }) async {
    purchaseCalls.add((kind, cursor));
    if (purchaseError != null) {
      throw ApiException('Unavailable', statusCode: purchaseError);
    }
    return pending[kind]?.future ?? Future.value(purchases);
  }
}

Map<String, dynamic> _row(
  String id,
  String kind,
  String? username, {
  Object? coins = 250,
  String status = 'purchased',
  String funding = 'coins',
  String? userStatus,
}) => {
  'id': id,
  'kind': kind,
  'username': username,
  'userStatus': userStatus,
  'productId': 'sku-$id',
  'productName': 'Product $id',
  'occurredAt': '2026-09-13T11:40:00Z',
  'status': status,
  'funding': funding,
  'coinsSpent': coins,
  'cashAmount': null,
  'currency': null,
};

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'admin-1',
    'auth_display_name': 'Admin',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Future<void> _pump(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _shop(WidgetTester tester, _Api api, {double scale = 1}) async {
  final controller = AdminDashboardController(api, await _auth());
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child ?? const SizedBox.shrink(),
      ),
      home: AdminDashboardDetail(title: 'Ads & shop', controller: controller),
    ),
  );
  await _pump(tester);
  expect(api.purchaseCalls, isEmpty);
  await tester.tap(find.text('Shop'));
  await _pump(tester);
}

Future<void> _show(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await _pump(tester);
}

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets(
    'Shop lazily associates all purchase types with usernames and honest amounts',
    (tester) async {
      final api = _Api()
        ..purchases = {
          'items': [
            _row('coin', 'coin_pack', 'CoinBara', coins: null, funding: 'cash'),
            _row(
              'sub',
              'subscription',
              'MemberBara',
              coins: null,
              status: 'trial',
              funding: 'trial',
            ),
            _row('game', 'in_game', 'GameBara'),
            _row('deleted', 'other', null, coins: 'bad', userStatus: 'deleted'),
            _row(
              'unnamed',
              'in_game',
              null,
              coins: 0,
              status: 'free',
              funding: 'free',
            ),
          ],
          'nextCursor': null,
        };
      await _shop(tester, api);
      await _show(tester, find.text('Recent purchases'));
      expect(api.purchaseCalls, [('all', null)]);
      expect(
        find.text('Last 30 days · Production billing records'),
        findsOneWidget,
      );
      for (final name in [
        'CoinBara',
        'MemberBara',
        'GameBara',
        'Deleted account',
        'Username unavailable',
      ]) {
        await _show(tester, find.text(name));
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('0 coins'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'purchase pagination keeps rows on error, retries cursor, and deduplicates IDs',
    (tester) async {
      final api = _Api()
        ..purchases = {
          'items': [_row('a', 'in_game', 'FirstBara')],
          'nextCursor': 'opaque',
        };
      await _shop(tester, api);
      await _show(tester, find.text('Load more'));
      api.purchaseError = 503;
      await tester.tap(find.text('Load more'));
      await _pump(tester);
      expect(find.text('FirstBara'), findsOneWidget);
      await _show(tester, find.text('Retry purchases'));
      api.purchaseError = null;
      api.purchases = {
        'items': [
          _row('a', 'in_game', 'FirstBara'),
          _row('b', 'in_game', 'SecondBara'),
        ],
        'nextCursor': null,
      };
      await tester.tap(find.text('Retry purchases'));
      await _pump(tester);
      expect(api.purchaseCalls.last, ('all', 'opaque'));
      expect(find.text('FirstBara'), findsOneWidget);
      expect(find.text('SecondBara'), findsOneWidget);
    },
  );

  testWidgets('filter changes ignore late prior responses and reset cursor', (
    tester,
  ) async {
    final api = _Api();
    api.pending['all'] = Completer();
    await _shop(tester, api);
    await _show(tester, find.text('Coin packs'));
    api.purchases = {
      'items': [_row('pack', 'coin_pack', 'NewestBara')],
      'nextCursor': null,
    };
    await tester.tap(find.text('Coin packs'));
    await _pump(tester);
    api.pending['all']?.complete({
      'items': [_row('old', 'in_game', 'WrongBara')],
      'nextCursor': 'old',
    });
    await _pump(tester);
    expect(find.text('NewestBara'), findsOneWidget);
    expect(find.text('WrongBara'), findsNothing);
    expect(api.purchaseCalls.last, ('coin_pack', null));
  });

  testWidgets(
    'empty and older backend purchase states preserve shop analytics',
    (tester) async {
      final api = _Api();
      await _shop(tester, api);
      await _show(tester, find.text('No recorded purchases in this period.'));
      api.purchaseError = 404;
      await tester.tap(find.text('Subscriptions'));
      await _pump(tester);
      expect(
        find.text('Purchase history is unavailable on this server.'),
        findsOneWidget,
      );
      expect(find.text('Most-purchased items'), findsOneWidget);
    },
  );

  testWidgets(
    'long purchase names and filters fit narrow screens with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _Api()
        ..purchases = {
          'items': [
            _row(
              'long',
              'in_game',
              'A very long current public username with many words',
            ),
          ],
          'nextCursor': null,
        };
      await _shop(tester, api, scale: 1.8);
      await _show(tester, find.text('In-game purchases'));
      await _show(
        tester,
        find.text('A very long current public username with many words'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'freshness uses calculated timestamps and stale status; old fields use fetched',
    (tester) async {
      final api = _Api();
      await _shop(tester, api);
      await _show(tester, find.textContaining('Shop · Calculated'));
      expect(find.textContaining('updates every 15 min'), findsOneWidget);
      expect(find.textContaining('STALE'), findsWidgets);
      api.stats = {
        'coinEconomy': {'purchasesBySku': []},
      };
      await tester.tap(find.byTooltip('Refresh Ads & shop'));
      await _pump(tester);
      await _show(tester, find.textContaining('Shop · Fetched'));
      expect(find.textContaining('Shop · Calculated'), findsNothing);
    },
  );

  testWidgets(
    'disabled response removes previously available cached analytics',
    (tester) async {
      final api = _Api();
      api.stats['metricsDashboard'] = {
        'schemaVersion': 2,
        'status': 'available',
        'summary': {
          'growth': {'totalSignups': 8123},
        },
      };
      await tester.pumpWidget(
        MaterialApp(
          home: AdminScreen(authService: await _auth(), backendApiService: api),
        ),
      );
      await _pump(tester);
      expect(find.text('8,123 total accounts'), findsOneWidget);
      api.stats = {
        'metricsDashboard': {'schemaVersion': 2, 'status': 'disabled'},
      };
      await tester.tap(find.byTooltip('Refresh overview'));
      await _pump(tester);
      expect(find.text('8,123 total accounts'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'refresh failure retains calculated values with stale freshness',
    (tester) async {
      final api = _Api();
      await _shop(tester, api);
      api.statsError = 503;
      await tester.tap(find.byTooltip('Refresh Ads & shop'));
      await _pump(tester);
      await _show(tester, find.textContaining('Shop · Calculated'));
      expect(find.textContaining('STALE'), findsWidgets);
      expect(
        find.textContaining('Couldn’t update this section.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('malformed rows and amounts never become fake zero purchases', (
    tester,
  ) async {
    final api = _Api()
      ..purchases = {
        'items': [
          null,
          'broken',
          {'username': 'No ID'},
          _row(
            'bad',
            'future_kind',
            'VisibleBara',
            coins: '250',
            funding: 'unknown',
          ),
        ],
        'nextCursor': null,
      };
    await _shop(tester, api);
    await _show(tester, find.text('VisibleBara'));
    expect(find.text('Amount unrecorded'), findsOneWidget);
    expect(find.text('0 coins'), findsNothing);
    expect(find.textContaining('Other activity'), findsOneWidget);
    expect(find.textContaining('Some records are unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'stale snapshot is replaced by a bounded follow-up without waiting fifteen minutes',
    (tester) async {
      final api = _Api();
      final controller = AdminDashboardController(api, await _auth());
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: AdminDashboardDetail(title: 'Growth', controller: controller),
        ),
      );
      await _pump(tester);
      expect(api.statsCalls, ['dashboard-growth']);
      api.stats['snapshot'] = {
        'generatedAt': '2026-09-13T12:01:00Z',
        'status': 'fresh',
        'refreshIntervalSeconds': 900,
      };
      await tester.pump(const Duration(seconds: 50));
      await _pump(tester);
      expect(api.statsCalls, ['dashboard-growth', 'dashboard-growth']);
      expect(controller.state('dashboard-growth').snapshotStale, isFalse);
      await tester.pump(const Duration(minutes: 3));
      expect(api.statsCalls.length, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'cold 503 gets bounded follow-up and persistent stale snapshots stop after two attempts',
    (tester) async {
      final api = _Api()..statsError = 503;
      final controller = AdminDashboardController(api, await _auth());
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: AdminDashboardDetail(title: 'Growth', controller: controller),
        ),
      );
      await _pump(tester);
      expect(controller.state('dashboard-growth').envelope, isNull);
      api.statsError = null;
      await tester.pump(const Duration(seconds: 50));
      await _pump(tester);
      expect(controller.state('dashboard-growth').envelope, isNotNull);
      await tester.pump(const Duration(seconds: 50));
      await _pump(tester);
      expect(api.statsCalls.length, 3);
      await tester.pump(const Duration(minutes: 3));
      expect(api.statsCalls.length, 3);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'snapshot follow-ups stop in background, hidden routes, and disposal',
    (tester) async {
      final api = _Api();
      final controller = AdminDashboardController(api, await _auth());
      addTearDown(controller.dispose);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: AdminDashboardDetail(title: 'Growth', controller: controller),
        ),
      );
      await _pump(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 60));
      expect(api.statsCalls.length, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      unawaited(
        navigator.currentState?.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Hidden')),
          ),
        ),
      );
      await _pump(tester);
      await tester.pump(const Duration(seconds: 60));
      expect(api.statsCalls.length, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 60));
      expect(api.statsCalls.length, 1);
    },
  );

  testWidgets('authorization failures never schedule analytics follow-ups', (
    tester,
  ) async {
    final api = _Api()..statsError = 403;
    final controller = AdminDashboardController(api, await _auth());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AdminDashboardDetail(title: 'Growth', controller: controller),
      ),
    );
    await _pump(tester);
    await tester.pump(const Duration(minutes: 3));
    expect(api.statsCalls.length, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'stacked detail refreshes only its visible section and resumes after age expires',
    (tester) async {
      final api = _Api();
      api.stats['snapshot'] = {'status': 'fresh'};
      var now = DateTime(2026, 9, 13, 12);
      final controller = AdminDashboardController(
        api,
        await _auth(),
        now: () => now,
      );
      addTearDown(controller.dispose);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: AdminDashboardDetail(title: 'Growth', controller: controller),
        ),
      );
      await _pump(tester);
      unawaited(
        navigator.currentState?.push(
          MaterialPageRoute<void>(
            builder: (_) =>
                AdminDashboardDetail(title: 'Activity', controller: controller),
          ),
        ),
      );
      await _pump(tester);
      api.statsCalls.clear();
      now = now.add(const Duration(minutes: 15));
      await tester.pump(const Duration(minutes: 15));
      await _pump(tester);
      expect(api.statsCalls, ['dashboard-dau-engagement']);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 16));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _pump(tester);
      expect(api.statsCalls, [
        'dashboard-dau-engagement',
        'dashboard-dau-engagement',
      ]);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'one foreground refresh timer pauses in background and hidden routes and stops on dispose',
    (tester) async {
      final api = _Api();
      api.stats['snapshot'] = {'status': 'fresh'};
      await tester.pumpWidget(
        MaterialApp(
          home: AdminScreen(authService: await _auth(), backendApiService: api),
        ),
      );
      await _pump(tester);
      final first = api.statsCalls.length;
      await tester.pump(const Duration(minutes: 15));
      await _pump(tester);
      expect(api.statsCalls.length, first * 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final paused = api.statsCalls.length;
      await tester.pump(const Duration(minutes: 16));
      expect(api.statsCalls.length, paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _pump(tester);
      await tester.tap(find.text('Tools'));
      await _pump(tester);
      final hidden = api.statsCalls.length;
      await tester.pump(const Duration(minutes: 16));
      expect(api.statsCalls.length, hidden);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(minutes: 16));
      expect(api.statsCalls.length, hidden);
    },
  );
}
