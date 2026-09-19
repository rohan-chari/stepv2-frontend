import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/admin_metrics_dashboard.dart';
import 'package:step_tracker/screens/admin_metrics_dashboard.dart';
import 'package:step_tracker/screens/admin_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';

class _DauApi extends BackendApiService {
  final List<List<String>> sectionsCalls = [];
  final List<String?> windows = [];

  final viewCalls = <(String, String)>[];
  @override
  Future<Map<String, dynamic>> fetchAdminStatsView({
    required String identityToken,
    required String view,
    required String window,
    required String section,
  }) async {
    viewCalls.add((view, window));
    return {
      'view': view,
      'sections': {
        for (final name
            in view == 'overview'
                ? [
                    'dashboard-summary',
                    'dashboard-growth',
                    'dashboard-dau-engagement',
                  ]
                : ['dashboard-dau-engagement'])
          name: _metricsWithDau(_completeDauEngagement),
      },
    };
  }

  @override
  Future<Map<String, dynamic>> fetchAdminStats({
    required String identityToken,
    List<String> sections = const [],
    String? window,
  }) async {
    sectionsCalls.add(sections);
    windows.add(window);
    final metrics = <String, dynamic>{
      'schemaVersion': 2,
      'status': 'available',
      'window': {
        'days': 30,
        'start': '2026-07-26',
        'end': '2026-08-24',
        'timeZone': 'America/New_York',
      },
      'sources': <String, dynamic>{},
      'coverage': <String, dynamic>{},
      'summary': {
        'growth': {'engagedBoxOpenersToday': 31},
      },
    };
    if (sections.contains('dashboard-dau-engagement')) {
      metrics['dauEngagement'] = _completeDauEngagement;
    }
    return {'metricsDashboard': metrics};
  }
}

Future<AuthService> _adminAuth() async {
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

Future<void> _pumpDauBody(
  WidgetTester tester,
  Map<String, dynamic> stats,
) async {
  tester.view.physicalSize = const Size(1170, 3400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppThemeData.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: AdminMetricsSectionBody(
            section: 'dashboard-dau-engagement',
            envelope: AdminMetricsEnvelope.fromStats(stats),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

const _actions = <String, dynamic>{
  'raceParticipation': {'users': 44, 'events': 71},
  'boxOpen': {'users': 31, 'events': 58},
  'powerupUse': {'users': 19, 'events': 26},
  'dailyRewardClaim': {'users': 62, 'events': 62},
  'notificationOpen': {'users': 12, 'events': 12},
  'rewardedAd': {'users': 17, 'events': 24},
  'leaderboardView': {'users': 36, 'events': 102},
  'raceCreated': {'users': 8, 'events': 10},
  'raceCompleted': {'users': 21, 'events': 24},
};

Map<String, dynamic> get _completeDauEngagement => {
  'asOf': '2026-08-24T12:00:00.000Z',
  'timeZone': 'America/New_York',
  'actionBasedDau': {'users': 74, 'status': 'available'},
  'today': {
    'date': '2026-08-24',
    'actions': _actions,
    'averageActionReach': 27.8,
    'usersWithAnyAction': 74,
  },
  'averageActionReach': 27.8,
  'usersWithAnyAction': 74,
  'comparisons': {
    'dayOverDay': {
      'current': 74,
      'prior': 68,
      'absoluteChange': 6,
      'percentChange': 8.8,
      'status': 'available',
      'currentStart': '2026-08-24',
      'currentEnd': '2026-08-24',
      'priorStart': '2026-08-23',
      'priorEnd': '2026-08-23',
    },
    'weekOverWeek': {
      'current': 70,
      'prior': null,
      'absoluteChange': null,
      'percentChange': null,
      'status': 'gathering_data',
      'currentStart': '2026-08-18',
      'currentEnd': '2026-08-24',
      'priorStart': '2026-08-11',
      'priorEnd': '2026-08-17',
    },
    'monthOverMonth': {'status': 'gathering_data'},
    'sixMonthsOverSixMonths': {'status': 'gathering_data'},
    'yearOverYear': {'status': 'gathering_data'},
  },
  'daily': [
    {
      'date': '2026-08-24',
      'actionBasedDau': 74,
      'averageActionReach': 27.8,
      'usersWithAnyAction': 74,
    },
  ],
};

Map<String, dynamic> _metricsWithDau(Map<String, dynamic> dau) => {
  'metricsDashboard': {
    'schemaVersion': 2,
    'status': 'available',
    'window': {'days': 30, 'timeZone': 'America/New_York'},
    'sources': <String, dynamic>{},
    'coverage': <String, dynamic>{},
    'dauEngagement': dau,
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('DAU + engagement dashboard section', () {
    testWidgets(
      'overview and Activity request separate cached pages with visible action data',
      (tester) async {
        tester.view.physicalSize = const Size(390, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final api = _DauApi();
        await tester.pumpWidget(
          MaterialApp(
            home: AdminScreen(
              authService: await _adminAuth(),
              backendApiService: api,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(api.viewCalls, [('overview', '7d')]);
        expect(find.text('74'), findsWidgets);
        Future<void> open() async {
          await tester.scrollUntilVisible(
            find.text('Activity'),
            350,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Activity'));
          await tester.pumpAndSettle();
        }

        await open();
        expect(api.viewCalls, [('overview', '7d'), ('activity', '7d')]);
        expect(find.text('People taking an action'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Boxes opened'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('31 people'), findsOneWidget);
        expect(find.textContaining('58 events'), findsOneWidget);
        await tester.tap(find.text('Boxes opened'));
        await tester.pumpAndSettle();
        expect(find.text('Boxes opened · people'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await open();
        expect(api.viewCalls, [('overview', '7d'), ('activity', '7d')]);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'renders action reach, raw events, union, daily rows, and comparisons',
      (tester) async {
        await _pumpDauBody(tester, _metricsWithDau(_completeDauEngagement));

        expect(find.text('ACTION-BASED DAU'), findsOneWidget);
        expect(find.text('74'), findsWidgets);
        expect(find.text('Race participation'), findsNWidgets(6));
        expect(find.text('44 users · 71 events'), findsOneWidget);
        expect(find.text('Mystery box opens'), findsNWidgets(6));
        expect(find.text('31 users · 58 events'), findsOneWidget);
        expect(find.text('Powerup use'), findsNWidgets(6));
        expect(find.text('Daily reward claims'), findsNWidgets(6));
        expect(find.text('Notification opens'), findsNWidgets(6));
        expect(find.text('Verified rewarded ads'), findsNWidgets(6));
        expect(find.text('Leaderboard views'), findsNWidgets(6));
        expect(find.text('Race creation'), findsNWidgets(6));
        expect(find.text('Race completion'), findsNWidgets(6));
        expect(find.text('AVERAGE ACTION REACH'), findsOneWidget);
        expect(find.text('27.8'), findsWidgets);
        expect(find.text('USERS WITH ANY ACTION'), findsOneWidget);
        expect(find.text('DAILY ACTION REACH'), findsOneWidget);
        expect(find.text('2026-08-24'), findsWidgets);
        expect(find.text('COMPARISONS'), findsOneWidget);
        expect(find.text('DAY OVER DAY'), findsOneWidget);
        expect(find.text('74 current · 68 prior · +6 · 8.8%'), findsOneWidget);
        expect(find.text('WEEK OVER WEEK'), findsOneWidget);
        expect(find.text('GATHERING DATA'), findsWidgets);
        expect(find.text('DAU DENOMINATOR'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'renders successful zero and degrades malformed leaves safely',
      (tester) async {
        final zero = {
          'actionBasedDau': {'users': 0, 'status': 'available'},
          'today': {
            'date': '2026-08-24',
            'actions': {
              'boxOpen': {'users': 0, 'events': 0},
            },
            'averageActionReach': 0,
            'usersWithAnyAction': 0,
          },
          'comparisons': {
            'dayOverDay': {'status': 'gathering_data'},
          },
          'daily': [
            {'date': 42, 'actionBasedDau': 'not-a-number'},
          ],
        };
        await _pumpDauBody(tester, _metricsWithDau(zero));

        expect(find.text('ACTION-BASED DAU'), findsOneWidget);
        expect(find.text('0'), findsWidgets);
        expect(find.text('Mystery box opens'), findsNWidgets(6));
        expect(find.text('0 users · 0 events'), findsOneWidget);
        expect(find.text('GATHERING DATA'), findsWidgets);
        expect(find.text('UNAVAILABLE'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a missing dauEngagement block shows unavailable safely', (
      tester,
    ) async {
      await _pumpDauBody(tester, {
        'metricsDashboard': {
          'schemaVersion': 1,
          'status': 'available',
          'window': {'days': 30, 'timeZone': 'America/New_York'},
        },
      });

      expect(find.text('UNAVAILABLE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Android uses the same page contract and action overview', (
      tester,
    ) async {
      final api = _DauApi();
      await tester.pumpWidget(
        MaterialApp(
          home: AdminScreen(
            authService: await _adminAuth(),
            backendApiService: api,
            isIosForTesting: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(api.viewCalls, [('overview', '7d')]);
      expect(find.text('74'), findsWidgets);
      expect(find.text('Active users'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
