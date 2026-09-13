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

const _sections = <String, List<String>>{
  'overview': [
    'dashboard-summary',
    'dashboard-growth',
    'dashboard-dau-engagement',
  ],
  'growth': ['dashboard-growth'],
  'activity': ['dashboard-dau-engagement'],
  'retention': [
    'dashboard-summary',
    'dashboard-retention',
    'dashboard-retention-mature',
  ],
  'races': [
    'dashboard-summary',
    'dashboard-engagement',
    'dashboard-activation',
  ],
  'invites': ['dashboard-funnels'],
  'onboarding': ['dashboard-funnels'],
  'ads': ['dashboard-revenue', 'ads'],
  'shop': ['economy'],
};

Map<String, dynamic> _inner(
  String section, {
  int days = 7,
  int accounts = 321,
  String status = 'available',
}) => {
  'generatedAt': '2026-09-13T12:00:00Z',
  'snapshot': {
    'generatedAt': '2026-09-13T12:00:00Z',
    'status': 'fresh',
    'refreshIntervalSeconds': 900,
  },
  'metricsDashboard': {
    'schemaVersion': 2,
    'status': status,
    'window': {
      'days': days,
      'start': '2026-09-07',
      'end': '2026-09-13',
      'timeZone': 'America/New_York',
    },
    'summary': {
      'growth': {
        'totalSignups': accounts,
        'signupsToday': 3,
        'signupsLast7Days': 21,
      },
      'retention': {
        'd1': {'numerator': 3, 'denominator': 4, 'percent': 75},
      },
    },
    'retention': {
      'cohorts': [],
      'secondRaceWithin7d': {'numerator': 1, 'denominator': 2, 'percent': 50},
    },
    'userGrowth': {'daily': []},
  },
  if (section == 'economy') 'coinEconomy': {'purchasesBySku': []},
};

Map<String, dynamic> _page(String view, String window) => {
  'view': view,
  'generatedAt': '2026-09-13T12:00:00Z',
  'snapshot': {
    'generatedAt': '2026-09-13T12:00:00Z',
    'status': 'fresh',
    'refreshIntervalSeconds': 900,
  },
  'sections': {
    for (final section in _sections[view] ?? <String>[])
      section: _inner(
        section,
        days: section == 'dashboard-retention-mature'
            ? 90
            : window == '30d'
            ? 30
            : 7,
      ),
  },
};

class _PageApi extends BackendApiService {
  final views = <(String, String, String)>[];
  final legacy = <(String, String?)>[];
  final legacyFailures = <String, ApiException>{};
  final blockers = <String, Completer<Map<String, dynamic>>>{};
  final responses = <String, Map<String, dynamic>>{};
  ApiException? failure;
  bool oldServer = false;
  int purchaseCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchAdminStatsView({
    required String identityToken,
    required String view,
    required String window,
    required String section,
  }) async {
    views.add((view, window, section));
    final error = failure;
    if (error != null) throw error;
    if (oldServer) return _inner(section);
    return blockers['$view:$window']?.future ??
        Future.value(responses[view] ?? _page(view, window));
  }

  @override
  Future<Map<String, dynamic>> fetchAdminStats({
    required String identityToken,
    List<String> sections = const [],
    String? window,
  }) async {
    legacy.add((sections.single, window));
    final error = legacyFailures[sections.single];
    if (error != null) throw error;
    return _inner(sections.single, days: window == '90d' ? 90 : 7);
  }

  @override
  Future<Map<String, dynamic>> fetchAdminPurchases({
    required String identityToken,
    String kind = 'all',
    String environment = 'production',
    int limit = 20,
    String? cursor,
  }) async {
    purchaseCalls++;
    return {'items': [], 'nextCursor': null};
  }
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple',
    'auth_session_token': 'session',
    'auth_user_identifier': 'apple-user',
    'auth_backend_user_id': 'admin',
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

Future<AdminDashboardController> _detail(
  WidgetTester tester,
  _PageApi api,
  String title,
) async {
  final controller = AdminDashboardController(api, await _auth());
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: AdminDashboardDetail(title: title, controller: controller),
    ),
  );
  await _pump(tester);
  return controller;
}

Future<void> _show(
  WidgetTester tester,
  Finder finder, {
  double delta = 280,
}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find.byType(Scrollable).first,
  );
  await _pump(tester);
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
    'overview requests exactly one page and Today reuses its 7d payload',
    (tester) async {
      final api = _PageApi();
      await tester.pumpWidget(
        MaterialApp(
          home: AdminScreen(authService: await _auth(), backendApiService: api),
        ),
      );
      await _pump(tester);
      expect(api.views, [('overview', '7d', 'dashboard-summary')]);
      expect(api.legacy, isEmpty);
      expect(find.text('321 total accounts'), findsOneWidget);
      await tester.tap(find.text('Today'));
      await _pump(tester);
      expect(api.views.length, 1);
      await tester.tap(find.text('30 days'));
      await _pump(tester);
      expect(api.views.last, ('overview', '30d', 'dashboard-summary'));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Ads and Shop are separate lazy pages; Shop always requests 30d',
    (tester) async {
      final api = _PageApi();
      await _detail(tester, api, 'Ads & shop');
      expect(api.views, [('ads', '7d', 'dashboard-revenue')]);
      expect(api.purchaseCalls, 0);
      await tester.tap(find.text('Shop'));
      await _pump(tester);
      expect(api.views.last, ('shop', '30d', 'economy'));
      expect(api.legacy, isEmpty);
      await _show(tester, find.text('Recent purchases'));
      expect(api.purchaseCalls, 1);
    },
  );

  testWidgets(
    'Retention consumes its own summary and mature90d section in one response',
    (tester) async {
      final api = _PageApi();
      final controller = await _detail(tester, api, 'Retention');
      expect(
        controller
            .state('dashboard-retention-mature', view: AdminView.retention)
            .envelope
            ?.window
            .days,
        90,
      );
      expect(api.views, [('retention', '7d', 'dashboard-summary')]);
      expect(api.legacy, isEmpty);
      expect(find.text('75.0%'), findsOneWidget);
      await _show(tester, find.text('Another race within 7 days'));
      expect(find.text('50.0%'), findsOneWidget);
      expect(
        find.textContaining('First finishes in last 90 days'),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'same summary section never mixes Overview and Retention projections',
    (tester) async {
      final api = _PageApi();
      final page = _page('retention', '7d');
      page['sections']['dashboard-summary'] = _inner(
        'dashboard-summary',
        accounts: 999,
      );
      api.responses['retention'] = page;
      await tester.pumpWidget(
        MaterialApp(
          home: AdminScreen(authService: await _auth(), backendApiService: api),
        ),
      );
      await _pump(tester);
      await _show(tester, find.text('Retention'));
      await tester.tap(find.text('Retention'));
      await _pump(tester);
      expect(api.views.map((call) => call.$1), ['overview', 'retention']);
      await tester.pageBack();
      await _pump(tester);
      await _show(tester, find.text('321 total accounts'), delta: -280);
      expect(find.text('999 total accounts'), findsNothing);
      expect(api.views.length, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'funnel tabs load only their page despite sharing the same section name',
    (tester) async {
      final api = _PageApi();
      await _detail(tester, api, 'Invites & onboarding');
      expect(api.views.map((call) => call.$1), ['invites']);
      await tester.tap(find.text('Onboarding'));
      await _pump(tester);
      expect(api.views.map((call) => call.$1), ['invites', 'onboarding']);
      expect(api.legacy, isEmpty);
    },
  );

  testWidgets(
    'old backend fallback reuses first reply and requests only remaining page sections',
    (tester) async {
      final api = _PageApi()..oldServer = true;
      await _detail(tester, api, 'Retention');
      expect(api.views.length, 1);
      expect(api.legacy, [
        ('dashboard-retention', '7d'),
        ('dashboard-retention', '90d'),
      ]);
      expect(find.text('75.0%'), findsOneWidget);
      await tester.tap(find.byTooltip('Refresh Retention'));
      await _pump(tester);
      expect(api.views.length, 1);
      expect(api.legacy.length, 5);
    },
  );

  testWidgets(
    'advertised malformed view never fans out into legacy analytics',
    (tester) async {
      final api = _PageApi()
        ..responses['growth'] = {'view': 'growth', 'sections': 'broken'};
      await _detail(tester, api, 'Growth');
      expect(api.views.length, 1);
      expect(api.legacy, isEmpty);
      expect(find.textContaining('Couldn’t update'), findsWidgets);
    },
  );

  testWidgets(
    'cold pending page shows checking and completes with one bounded page follow-up',
    (tester) async {
      final api = _PageApi()
        ..failure = const ApiException(
          'Calculating',
          statusCode: 503,
          code: 'ADMIN_ANALYTICS_PENDING',
        );
      await _detail(tester, api, 'Growth');
      expect(find.textContaining('Checking'), findsWidgets);
      expect(find.textContaining('Couldn’t update'), findsNothing);
      expect(find.textContaining('no daily history available'), findsNothing);
      api.failure = null;
      await tester.pump(const Duration(seconds: 50));
      await _pump(tester);
      expect(api.views.length, 2);
      expect(api.legacy, isEmpty);
      expect(find.textContaining('Checking'), findsNothing);
    },
  );

  testWidgets(
    'pending page follow-ups stop after two attempts and offer retry',
    (tester) async {
      final api = _PageApi()
        ..failure = const ApiException(
          'Calculating',
          statusCode: 503,
          code: 'ADMIN_ANALYTICS_PENDING',
        );
      await _detail(tester, api, 'Growth');
      for (var i = 0; i < 2; i++) {
        await tester.pump(const Duration(seconds: 50));
        await _pump(tester);
      }
      expect(api.views.length, 3);
      expect(find.textContaining('Checking'), findsNothing);
      expect(find.text('Retry'), findsWidgets);
      await tester.pump(const Duration(minutes: 3));
      expect(api.views.length, 3);
    },
  );

  testWidgets('switching page tabs gets its own bounded completion attempts', (
    tester,
  ) async {
    final api = _PageApi()
      ..failure = const ApiException(
        'Calculating',
        statusCode: 503,
        code: 'ADMIN_ANALYTICS_PENDING',
      );
    await _detail(tester, api, 'Ads & shop');
    for (var i = 0; i < 2; i++) {
      await tester.pump(const Duration(seconds: 50));
      await _pump(tester);
    }
    expect(api.views.length, 3);
    await tester.tap(find.text('Shop'));
    await _pump(tester);
    api.failure = null;
    await tester.pump(const Duration(seconds: 50));
    await _pump(tester);
    expect(api.views.where((call) => call.$1 == 'shop').length, 2);
  });

  testWidgets(
    'projected disabled page clears the previously available snapshot',
    (tester) async {
      final api = _PageApi();
      await tester.pumpWidget(
        MaterialApp(
          home: AdminScreen(authService: await _auth(), backendApiService: api),
        ),
      );
      await _pump(tester);
      expect(find.text('321 total accounts'), findsOneWidget);
      api.responses['overview'] = {
        'view': 'overview',
        'sections': {
          for (final section in _sections['overview'] ?? <String>[])
            section: _inner(section, status: 'disabled'),
        },
      };
      await tester.tap(find.byTooltip('Refresh overview'));
      await _pump(tester);
      expect(find.text('321 total accounts'), findsNothing);
      expect(api.legacy, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'stale overview follows up once for the whole page, never per section',
    (tester) async {
      final api = _PageApi();
      final stale = _page('overview', '7d');
      stale['snapshot']['status'] = 'stale';
      api.responses['overview'] = stale;
      await tester.pumpWidget(
        MaterialApp(
          home: AdminScreen(authService: await _auth(), backendApiService: api),
        ),
      );
      await _pump(tester);
      api.responses['overview'] = _page('overview', '7d');
      await tester.pump(const Duration(seconds: 50));
      await _pump(tester);
      expect(api.views.map((call) => call.$1), ['overview', 'overview']);
      expect(api.legacy, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'late range completion cannot overwrite newly selected page window',
    (tester) async {
      final api = _PageApi();
      final blocker = Completer<Map<String, dynamic>>();
      api.blockers['growth:7d'] = blocker;
      await _detail(tester, api, 'Growth');
      await tester.tap(find.text('30 days'));
      await _pump(tester);
      blocker.complete(_page('growth', '7d'));
      await _pump(tester);
      expect(api.views.map((call) => call.$2), ['7d', '30d']);
      expect(find.textContaining('30 days · ET'), findsWidgets);
      expect(api.legacy, isEmpty);
    },
  );
  testWidgets(
    'queued obsolete range is canceled and revisiting still loads it',
    (tester) async {
      final api = _PageApi();
      final blocker = Completer<Map<String, dynamic>>();
      api.blockers['growth:7d'] = blocker;
      final controller = await _detail(tester, api, 'Growth');
      await tester.tap(find.text('30 days'));
      await _pump(tester);
      await tester.tap(find.text('7 days'));
      await _pump(tester);
      blocker.complete(_page('growth', '7d'));
      await _pump(tester);
      expect(api.views.map((call) => call.$2), ['7d']);
      expect(
        controller
            .state(
              'dashboard-growth',
              view: AdminView.growth,
              range: AdminRange.month,
            )
            .loading,
        isFalse,
      );
      await tester.tap(find.text('30 days'));
      await _pump(tester);
      expect(api.views.map((call) => call.$2), ['7d', '30d']);
    },
  );

  testWidgets(
    'queued tab is canceled after switching back and remains loadable',
    (tester) async {
      final api = _PageApi();
      final blocker = Completer<Map<String, dynamic>>();
      api.blockers['ads:7d'] = blocker;
      await _detail(tester, api, 'Ads & shop');
      await tester.tap(find.text('Shop'));
      await _pump(tester);
      await tester.tap(find.text('Ads'));
      await _pump(tester);
      blocker.complete(_page('ads', '7d'));
      await _pump(tester);
      expect(api.views.map((call) => call.$1), ['ads']);
      await tester.tap(find.text('Shop'));
      await _pump(tester);
      expect(api.views.map((call) => call.$1), ['ads', 'shop']);
    },
  );

  testWidgets(
    'queued page does not dispatch in background and resumes when visible',
    (tester) async {
      final api = _PageApi();
      final blocker = Completer<Map<String, dynamic>>();
      api.blockers['growth:7d'] = blocker;
      await _detail(tester, api, 'Growth');
      await tester.tap(find.text('30 days'));
      await _pump(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      blocker.complete(_page('growth', '7d'));
      await _pump(tester);
      expect(api.views.map((call) => call.$2), ['7d']);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _pump(tester);
      expect(api.views.map((call) => call.$2), ['7d', '30d']);
    },
  );

  testWidgets(
    'disposed detail cannot dispatch queued work through its shared controller',
    (tester) async {
      final api = _PageApi();
      final blocker = Completer<Map<String, dynamic>>();
      api.blockers['growth:7d'] = blocker;
      final controller = await _detail(tester, api, 'Growth');
      await tester.tap(find.text('30 days'));
      await _pump(tester);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Elsewhere'))),
      );
      blocker.complete(_page('growth', '7d'));
      await _pump(tester);
      expect(api.views.map((call) => call.$2), ['7d']);
      await tester.pumpWidget(
        MaterialApp(
          home: AdminDashboardDetail(title: 'Growth', controller: controller),
        ),
      );
      await _pump(tester);
      expect(api.views.map((call) => call.$2), ['7d', '30d']);
    },
  );

  testWidgets(
    'shared pending page has one checking banner on overview and details',
    (tester) async {
      final api = _PageApi()
        ..failure = const ApiException(
          'Calculating',
          statusCode: 503,
          code: 'ADMIN_ANALYTICS_PENDING',
        );
      await tester.pumpWidget(
        MaterialApp(
          home: AdminScreen(authService: await _auth(), backendApiService: api),
        ),
      );
      await _pump(tester);
      expect(
        find.textContaining('Checking for calculated data'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await _detail(tester, api, 'Retention');
      expect(
        find.textContaining('Checking for calculated data'),
        findsOneWidget,
      );
    },
  );
  testWidgets('hidden retained route cancels its queue and loads on return', (
    tester,
  ) async {
    final api = _PageApi();
    final blocker = Completer<Map<String, dynamic>>();
    api.blockers['growth:7d'] = blocker;
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
    await tester.tap(find.text('30 days'));
    await _pump(tester);
    unawaited(
      navigator.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Another route')),
        ),
      ),
    );
    await _pump(tester);
    blocker.complete(_page('growth', '7d'));
    await _pump(tester);
    expect(api.views.map((call) => call.$2), ['7d']);
    navigator.currentState?.pop();
    await _pump(tester);
    expect(api.views.map((call) => call.$2), ['7d', '30d']);
  });

  testWidgets(
    'distinct partial section errors remain visible beside the shared status area',
    (tester) async {
      final api = _PageApi()..oldServer = true;
      api.legacyFailures['dashboard-engagement'] = const ApiException(
        'Old endpoint',
        statusCode: 404,
      );
      api.legacyFailures['dashboard-activation'] = const ApiException(
        'Unavailable',
        statusCode: 503,
      );
      await _detail(tester, api, 'Races & friends');
      expect(
        find.textContaining('This section requires a server update.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Couldn’t update this section.'),
        findsOneWidget,
      );
    },
  );
}
