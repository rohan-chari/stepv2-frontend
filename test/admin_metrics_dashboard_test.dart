import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/admin_metrics_dashboard.dart';
import 'package:step_tracker/screens/admin_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _DashboardApi extends BackendApiService {
  _DashboardApi({
    this.responses = const {},
    this.failuresRemaining = const {},
    this.blocker,
  });

  final Map<String, Map<String, dynamic>> responses;
  final Map<String, int> failuresRemaining;
  final Map<String, int> _failureAttempts = {};
  final Completer<void>? blocker;
  final List<String> calls = [];
  int inFlight = 0;
  int maxInFlight = 0;

  @override
  Future<Map<String, dynamic>> fetchAdminStats({
    required String identityToken,
    List<String> sections = const [],
    String? window,
  }) async {
    final section = sections.isEmpty ? 'legacy' : sections.single;
    calls.add(section);
    inFlight += 1;
    maxInFlight = inFlight > maxInFlight ? inFlight : maxInFlight;
    try {
      if (blocker != null) await blocker!.future;
      final attemptedFailures = _failureAttempts[section] ?? 0;
      final allowedFailures = failuresRemaining[section] ?? 0;
      if (attemptedFailures < allowedFailures) {
        _failureAttempts[section] = attemptedFailures + 1;
        throw Exception('failed once $section');
      }
      return responses[section] ?? const <String, dynamic>{};
    } finally {
      inFlight -= 1;
    }
  }

  @override
  Future<Map<String, dynamic>> fetchAdminSettings({
    required String identityToken,
  }) async => const {'bannerAdsEnabled': true};

  @override
  Future<Map<String, dynamic>> fetchAdminSuggestions({
    required String identityToken,
    int limit = 50,
  }) async => const {'suggestions': <Map<String, dynamic>>[]};
}

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

Map<String, dynamic> _dashboard(
  String block,
  Object? value, {
  String status = 'available',
  Object? coverage,
  Object? sources,
}) {
  final resolvedSources =
      sources ??
      {
        'productDb': {
          'status': 'available',
          'asOf': '2026-08-18T15:04:05.000Z',
        },
        'foregroundActivity': {
          'status': 'collecting',
          'asOf': '2026-08-18T15:04:05.000Z',
        },
        'appStoreConnect': {'status': 'not_configured', 'asOf': null},
        'admob': {'status': 'not_configured', 'asOf': null},
      };
  return {
    'generatedAt': '2026-08-18T15:04:05.000Z',
    'metricsDashboard': {
      'schemaVersion': 2,
      'status': status,
      'window': {
        'days': 30,
        'start': '2026-07-20',
        'end': '2026-08-18',
        'timeZone': 'America/New_York',
      },
      'coverage': ?coverage,
      'sources': resolvedSources,
      block: value,
    },
  };
}

Map<String, dynamic> _summary() => _dashboard(
  'summary',
  {
    'growth': {
      'totalSignups': 1234,
      'signupsToday': 9,
      'signupsLast7Days': 61,
      'engagedBoxOpenersToday': 117,
      'observedForegroundDau': 112,
      'observedForegroundWau': null,
    },
    'retention': {
      'd1': {'numerator': 18, 'denominator': 40, 'percent': 45.0},
      'd7': {'numerator': 10, 'denominator': 38, 'percent': 26.3},
      'd30': {'numerator': null, 'denominator': null, 'percent': null},
    },
    'races': {
      'usersInActiveNonFeaturedRaces': 88,
      'activeNonFeaturedRaces': 21,
      'activeDailyRaces': 4,
      'nonFeaturedRacesCreatedToday': 7,
    },
  },
  coverage: {
    'metricCoverage': {
      'observedForegroundDau': {
        'status': 'mature',
        'collectingSince': '2026-08-08',
        'eligible': 702,
        'totalPopulation': 1234,
        'eligibilityPercent': 56.9,
      },
      'observedForegroundWau': {
        'status': 'collecting',
        'collectingSince': '2026-08-08',
        'eligible': 702,
        'totalPopulation': 1234,
        'eligibilityPercent': 56.9,
      },
      'retentionD30': {
        'status': 'collecting',
        'collectingSince': '2026-08-08',
        'eligible': 0,
        'totalPopulation': 0,
        'eligibilityPercent': null,
      },
    },
  },
);

Map<String, Map<String, dynamic>> _completeResponses() => {
  'dashboard-summary': _summary(),
  'dashboard-growth': _dashboard('userGrowth', {
    'daily': [
      {
        'date': '2026-08-17',
        'signups': 8,
        'observedForegroundUsers': 112,
        'appleFirstTimeDownloads': null,
        'appleDeletions': null,
      },
    ],
    'observedForegroundWau': 310,
    'observedForegroundMau': null,
  }),
  'dashboard-funnels':
      _dashboard('inviteFunnel', {
          'linkOpens': 200,
          'uniqueLinkOpens': 151,
          'attributedSignups': 32,
          'joinedRace': 21,
          'qualified': 14,
          'rewarded': 13,
          'openToSignup': {
            'numerator': 32,
            'denominator': 151,
            'percent': 21.2,
          },
          'signupToJoinedRace': {
            'numerator': 21,
            'denominator': 32,
            'percent': 65.6,
          },
          'joinedRaceToQualified': {
            'numerator': 14,
            'denominator': 21,
            'percent': 66.7,
          },
          'qualifiedToRewarded': {
            'numerator': 13,
            'denominator': 14,
            'percent': 92.9,
          },
        })
        ..['metricsDashboard']['onboardingFunnel'] = {
          'cohortWindowDays': 30,
          'stages': [
            {
              'key': 'onboarding_started',
              'count': 80,
              'previousSpineConversion': {
                'numerator': null,
                'denominator': null,
                'percent': null,
              },
              'startConversion': {
                'numerator': 80,
                'denominator': 80,
                'percent': 100.0,
              },
            },
            {
              'key': 'tutorial_opened',
              'count': 40,
              'previousSpineConversion': {
                'numerator': 40,
                'denominator': 50,
                'percent': 80.0,
              },
              'startConversion': {
                'numerator': 40,
                'denominator': 80,
                'percent': 50.0,
              },
            },
            {
              'key': 'tutorial_skipped',
              'count': 7,
              'previousSpineConversion': {
                'numerator': null,
                'denominator': null,
                'percent': null,
              },
              'startConversion': {
                'numerator': 7,
                'denominator': 80,
                'percent': 8.8,
              },
            },
            {
              'key': 'demo_box_opened',
              'count': 30,
              'previousSpineConversion': {
                'numerator': 30,
                'denominator': 40,
                'percent': 75.0,
              },
              'startConversion': {
                'numerator': 30,
                'denominator': 80,
                'percent': 37.5,
              },
            },
          ],
        },
  'dashboard-activation': _dashboard('activation', {
    'daily': [
      {
        'date': '2026-08-17',
        'liveRaceParticipants': 44,
        'raceCreators': 6,
        'racesCreated': 7,
      },
    ],
    'healthWithin24h': {'numerator': 21, 'denominator': 40, 'percent': 52.5},
    'raceWithin24h': {'numerator': 18, 'denominator': 40, 'percent': 45.0},
    'firstRacePowerUse': {'numerator': 11, 'denominator': 28, 'percent': 39.3},
    'friends': [
      {
        'bucket': '0',
        'ratio': {'numerator': 520, 'denominator': 1234, 'percent': 42.1},
      },
    ],
  }),
  'dashboard-retention': _dashboard('retention', {
    'd1': {'numerator': 18, 'denominator': 40, 'percent': 45.0},
    'd7': {'numerator': 10, 'denominator': 38, 'percent': 26.3},
    'd30': {'numerator': null, 'denominator': null, 'percent': null},
    'cohorts': [
      {
        'signupDate': '2026-08-10',
        'eligibleSignups': 12,
        'd1': {'numerator': 6, 'denominator': 12, 'percent': 50.0},
        'd7': {'numerator': 3, 'denominator': 12, 'percent': 25.0},
        'd30': {'numerator': null, 'denominator': null, 'percent': null},
      },
    ],
    'secondRaceWithin7d': {'numerator': 17, 'denominator': 31, 'percent': 54.8},
    'secondRaceWithin30d': {
      'numerator': 22,
      'denominator': 31,
      'percent': 71.0,
    },
  }),
  'dashboard-engagement': _dashboard('raceEngagement', {
    'daily': [
      {
        'date': '2026-08-17',
        'racesCreated': 7,
        'racesStarted': 5,
        'newParticipants': 29,
        'liveRaceParticipants': 44,
        'powerupsUsed': 61,
        'grossCoinCredits': 25000,
        'grossCoinDebits': 17000,
        'dailyRewardClaims': 93,
        'distinctDailyRewardClaimers': 76,
      },
    ],
    'averageRunnersPerStartedRace': 4.2,
    'visibility': {
      'public': {'numerator': 12, 'denominator': 31, 'percent': 38.7},
      'private': {'numerator': 19, 'denominator': 31, 'percent': 61.3},
    },
    'racesPerObservedActiveUser': {
      'numerator': 146,
      'denominator': 112,
      'average': 1.3,
    },
    'leaderboardViewsPerCapableRacer': {
      'numerator': 181,
      'denominator': 74,
      'average': 2.4,
    },
    'powerupsPerRace': {'numerator': 61, 'denominator': 18, 'average': 3.4},
    'coinBalance': {
      'populationCount': 722,
      'total': 208640,
      'average': 289.0,
      'median': 127.5,
      'p90': 672.8,
      'asOf': '2026-08-18T15:04:05.000Z',
    },
    'featuredParticipation': {
      'daily': {
        'activeOverlapUsers': 210,
        'activeOverlapMemberships': 294,
        'joinedWindowUsers': 98,
        'joinedWindowMemberships': 121,
      },
      'weekly': {
        'activeOverlapUsers': 155,
        'activeOverlapMemberships': 168,
        'joinedWindowUsers': 67,
        'joinedWindowMemberships': 72,
      },
    },
    'rankedParticipationUsers': 74,
    'notificationOpenRate': {
      'windowDays': 7,
      'numerator': 23,
      'denominator': 140,
      'percent': 16.4,
      'breakdown': [
        {
          'notificationType': 'RACE_INVITE',
          'ratio': {'numerator': 8, 'denominator': 40, 'percent': 20.0},
        },
      ],
    },
  }),
  'dashboard-virality': _dashboard('virality', {
    'shareCompletions': null,
    'sharingUsers': null,
    'attributedSignups': 32,
    'attributedSignupsPerWau': null,
    'linkOpenToSignup': {'numerator': 32, 'denominator': 151, 'percent': 21.2},
  }),
  'dashboard-revenue': _dashboard('revenue', {
    'daily': [
      {
        'date': '2026-08-17',
        'impressions': null,
        'ssvGrants': 423,
        'uniqueSsvWatchers': 116,
        'ssvByRewardKind': [
          {'rewardKind': 'coin_reward', 'grants': 102, 'uniqueWatchers': 29},
        ],
        'estimatedEarnings': null,
        'matchRate': null,
        'showRate': null,
      },
      {
        'date': '2026-08-18',
        'impressions': null,
        'ssvGrants': 11,
        'uniqueSsvWatchers': 9,
        'ssvByRewardKind': <Map<String, dynamic>>[],
        'estimatedEarnings': null,
        'matchRate': null,
        'showRate': null,
      },
    ],
    'adRevenuePerDau': null,
    'ssvGrantsPerRewardedImpression': {
      'numerator': 423,
      'denominator': null,
      'percent': null,
    },
    'byNetwork': <Map<String, dynamic>>[],
    'realMoneyPurchases': {'available': false, 'reason': 'NO_IAP_PRODUCT'},
  }),
  'dashboard-release-adoption': _dashboard('releaseAdoption', {
    'windowDays': 30,
    'versions': [
      {'version': '2.4.0', 'accountsSeen': 412},
    ],
  }),
};

Future<void> _pump(
  WidgetTester tester,
  _DashboardApi api, {
  Size logicalSize = const Size(390, 1200),
  bool ios = true,
}) async {
  tester.view.physicalSize = logicalSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: AdminScreen(
        key: UniqueKey(),
        authService: await _auth(),
        backendApiService: api,
        isIosForTesting: ios,
      ),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _expand(WidgetTester tester, String title) async {
  final header = find.byKey(Key('admin-section-header-$title'));
  await tester.ensureVisible(header);
  await tester.pump();
  await tester.tap(header, warnIfMissed: false);
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.4.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  test('parser defaults every missing/null/malformed/unknown leaf safely', () {
    final envelope = AdminMetricsEnvelope.fromStats({
      'metricsDashboard': {
        'schemaVersion': 'two',
        'status': 'future_status',
        'window': {'days': null, 'start': 7, 'timeZone': []},
        'sources': {
          'productDb': {'status': 'future_source', 'asOf': 42},
        },
        'summary': {
          'growth': {'totalSignups': '1234', 'signupsToday': null},
          'retention': {
            'd1': {'numerator': [], 'denominator': 0, 'percent': '0'},
          },
        },
      },
    });

    expect(envelope.status, AdminDashboardStatus.unavailable);
    expect(envelope.window.days, isNull);
    expect(envelope.window.start, isNull);
    expect(envelope.sources.productDb.status, AdminSourceStatus.unavailable);
    expect(envelope.summary?.map('growth')?.integer('totalSignups'), isNull);
    expect(envelope.summary?.map('growth')?.integer('signupsToday'), isNull);
    expect(envelope.summary?.map('retention')?.ratio('d1').numerator, isNull);
    expect(envelope.summary?.map('retention')?.ratio('d1').denominator, 0);
    expect(envelope.summary?.map('retention')?.ratio('d1').percent, isNull);
  });

  testWidgets('iOS shows expanded Summary then ordered lazy boards', (
    tester,
  ) async {
    final api = _DashboardApi(responses: _completeResponses());
    await _pump(tester, api);

    const order = [
      'SUMMARY',
      'USER GROWTH',
      'INVITE FUNNEL',
      'ONBOARDING FUNNEL',
      'ACTIVATION',
      'RETENTION',
      'RACE + ENGAGEMENT',
      'VIRALITY',
      'REVENUE',
      'CONFIG',
      'INBOX',
      'DEBUG',
    ];
    for (final title in order) {
      expect(find.byKey(Key('admin-section-$title')), findsOneWidget);
    }
    expect(find.text('Total accounts'), findsOneWidget);
    expect(find.text('1,234'), findsOneWidget);
    expect(find.text('Engaged box openers today'), findsOneWidget);
    expect(find.text('COLLECTING SINCE 2026-08-08'), findsWidgets);
    expect(find.text('DAU (stepped today)'), findsNothing);
    expect(api.calls, ['dashboard-summary']);

    await _expand(tester, 'USER GROWTH');
    expect(api.calls.last, 'dashboard-growth');
    await _expand(tester, 'INVITE FUNNEL');
    expect(api.calls.last, 'dashboard-funnels');
    await _expand(tester, 'ONBOARDING FUNNEL');
    expect(api.calls.where((c) => c == 'dashboard-funnels').length, 1);
    expect(find.text('IOS'), findsOneWidget);
    expect(find.text('ANDROID'), findsNothing);
    expect(api.maxInFlight, 1);
  });

  testWidgets('provider-only Phase A rows are hidden, DB revenue remains', (
    tester,
  ) async {
    final api = _DashboardApi(responses: _completeResponses());
    await _pump(tester, api);
    await _expand(tester, 'REVENUE');

    expect(find.textContaining('Signed rewarded grants'), findsNWidgets(2));
    expect(find.textContaining('Unique rewarded watchers'), findsNWidgets(2));
    expect(find.text('SIGNED REWARDED ADS'), findsOneWidget);
    expect(find.text('Ad revenue'), findsNothing);
    expect(find.text('Ad impressions'), findsNothing);
    expect(find.text('Match rate'), findsNothing);
    expect(find.text('Real-money purchases'), findsNothing);
    expect(find.textContaining('retained-account history'), findsWidgets);
  });

  testWidgets('Admin onboarding shows tutorial skip as a start-share exit', (
    tester,
  ) async {
    await _pump(tester, _DashboardApi(responses: _completeResponses()));
    await _expand(tester, 'ONBOARDING FUNNEL');

    expect(find.text('Tutorial skipped'), findsOneWidget);
    expect(find.text('7 · 8.8% of start'), findsOneWidget);
    final openedY = tester.getTopLeft(find.text('Tutorial opened')).dy;
    final skippedY = tester.getTopLeft(find.text('Tutorial skipped')).dy;
    final boxY = tester.getTopLeft(find.text('Box opened')).dy;
    expect(openedY, lessThan(skippedY));
    expect(skippedY, lessThan(boxY));
  });

  testWidgets('disabled and old-backend states preserve Config Inbox Debug', (
    tester,
  ) async {
    final disabled = _dashboard(
      'summary',
      null,
      status: 'disabled',
      sources: {
        'productDb': {
          'status': 'available',
          'asOf': '2026-08-18T15:04:05.000Z',
        },
        'foregroundActivity': {'status': 'disabled', 'asOf': null},
        'appStoreConnect': {'status': 'not_configured', 'asOf': null},
        'admob': {'status': 'not_configured', 'asOf': null},
      },
    );
    final api = _DashboardApi(responses: {'dashboard-summary': disabled});
    await _pump(tester, api);

    expect(find.text('Dashboard temporarily disabled'), findsOneWidget);
    expect(find.byKey(const Key('admin-section-CONFIG')), findsOneWidget);
    expect(find.byKey(const Key('admin-section-INBOX')), findsOneWidget);
    expect(find.byKey(const Key('admin-section-DEBUG')), findsOneWidget);

    final legacyApi = _DashboardApi(
      responses: {
        'dashboard-summary': {
          'users': {'total': 8},
          'versionsSince': '2026-07-20',
          'versions': [
            {'version': '2.3.8', 'platform': 'ios', 'users': 7},
          ],
        },
      },
    );
    await _pump(tester, legacyApi);
    expect(find.text('Dashboard requires a server update'), findsOneWidget);
    expect(find.byKey(const Key('admin-section-USER GROWTH')), findsNothing);
    await _expand(tester, 'DEBUG');
    expect(find.text('RELEASE ADOPTION'), findsOneWidget);
    await tester.tap(find.text('RELEASE ADOPTION'));
    await tester.pump();
    expect(find.text('2.3.8 (ios)'), findsOneWidget);
    expect(find.text('Accounts seen by backend in last 30d'), findsOneWidget);
  });

  testWidgets('section error stays inside its board and retry succeeds', (
    tester,
  ) async {
    final responses = _completeResponses();
    final api = _DashboardApi(
      responses: responses,
      failuresRemaining: const {'dashboard-activation': 1},
    );
    await _pump(tester, api);
    await _expand(tester, 'ACTIVATION');

    expect(find.text('Couldn’t load this section.'), findsOneWidget);
    expect(
      find.byKey(const Key('admin-dashboard-retry-dashboard-activation')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('admin-section-RETENTION')), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('admin-dashboard-retry-dashboard-activation')),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Health connected within 24h'), findsOneWidget);
    expect(
      api.calls.where((call) => call == 'dashboard-activation'),
      hasLength(2),
    );
  });

  testWidgets(
    'rapid refresh coalesces and reloads only opened blocks serially',
    (tester) async {
      final blocker = Completer<void>();
      final api = _DashboardApi(
        responses: _completeResponses(),
        blocker: blocker,
      );
      await _pump(tester, api);
      expect(api.calls, ['dashboard-summary']);
      blocker.complete();
      await tester.pump();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await _expand(tester, 'USER GROWTH');
      expect(api.calls, ['dashboard-summary', 'dashboard-growth']);

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.tap(find.byIcon(Icons.refresh));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(api.calls, [
        'dashboard-summary',
        'dashboard-growth',
        'dashboard-summary',
        'dashboard-growth',
      ]);
      expect(api.maxInFlight, 1);
    },
  );

  testWidgets('malformed leaves render unavailable and never zero or crash', (
    tester,
  ) async {
    final api = _DashboardApi(
      responses: {
        'dashboard-summary': _dashboard('summary', {
          'growth': {
            'totalSignups': null,
            'signupsToday': 'nine',
            'signupsLast7Days': [],
            'engagedBoxOpenersToday': {},
            'observedForegroundDau': false,
          },
          'retention': 'broken',
          'races': null,
        }),
      },
    );
    await _pump(tester, api);

    expect(find.text('UNAVAILABLE'), findsWidgets);
    expect(find.text('0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'valid empty DB results render zero while null stays unavailable',
    (tester) async {
      final api = _DashboardApi(
        responses: {
          'dashboard-summary': _dashboard('summary', {
            'growth': {
              'totalSignups': 0,
              'signupsToday': 0,
              'signupsLast7Days': 0,
              'engagedBoxOpenersToday': 0,
              'observedForegroundDau': null,
              'observedForegroundWau': null,
            },
            'retention': {
              'd1': {'numerator': 0, 'denominator': 0, 'percent': null},
            },
            'races': {
              'usersInActiveNonFeaturedRaces': 0,
              'activeNonFeaturedRaces': 0,
              'activeDailyRaces': 0,
              'nonFeaturedRacesCreatedToday': 0,
            },
          }),
        },
      );
      await _pump(tester, api);

      expect(find.text('0'), findsWidgets);
      expect(find.text('0 / 0 · —'), findsOneWidget);
      expect(find.text('UNAVAILABLE'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('stale source stays visible with as-of provenance', (
    tester,
  ) async {
    final response = _summary();
    final dashboard = response['metricsDashboard'] as Map<String, dynamic>;
    dashboard['sources'] = {
      'productDb': {'status': 'stale', 'asOf': '2026-08-17T15:04:05.000Z'},
    };
    final api = _DashboardApi(responses: {'dashboard-summary': response});
    await _pump(tester, api);

    expect(find.text('STALE'), findsOneWidget);
    expect(find.textContaining('AS OF 2026-08-17'), findsOneWidget);
    expect(find.text('1,234'), findsOneWidget);
  });

  testWidgets('metric info affordance opens its definition and source note', (
    tester,
  ) async {
    final api = _DashboardApi(responses: _completeResponses());
    await _pump(tester, api);

    await tester.tap(find.bySemanticsLabel('Definition for Total accounts'));
    await tester.pump();
    expect(
      find.text('Retained non-review iOS accounts; this is not installs.'),
      findsOneWidget,
    );
    expect(find.text('SOURCE · PRODUCT DB'), findsOneWidget);
    expect(
      find.text('WINDOW · CURRENT RETAINED-ACCOUNT SNAPSHOT'),
      findsOneWidget,
    );
    expect(find.text('COVERAGE · NOT APPLICABLE'), findsOneWidget);
  });

  testWidgets('nested and onboarding metrics show exact provenance', (
    tester,
  ) async {
    final api = _DashboardApi(responses: _completeResponses());
    await _pump(tester, api);

    await _expand(tester, 'USER GROWTH');
    final dailyForegroundInfo = find.bySemanticsLabel(
      'Definition for 2026-08-17 · observed foreground',
    );
    await tester.ensureVisible(dailyForegroundInfo);
    await tester.tap(dailyForegroundInfo);
    await tester.pump();
    expect(find.text('SOURCE · FOREGROUND TELEMETRY'), findsOneWidget);
    expect(find.text('WINDOW · 2026-08-17 · ET DAY'), findsOneWidget);
    expect(find.text('COVERAGE · UNAVAILABLE'), findsOneWidget);
    expect(find.text('COVERAGE · NOT APPLICABLE'), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();

    await _expand(tester, 'RACE + ENGAGEMENT');
    final pushInfo = find.bySemanticsLabel('Definition for Push · RACE_INVITE');
    await tester.ensureVisible(pushInfo);
    await tester.tap(pushInfo);
    await tester.pump();
    expect(
      find.text('SOURCE · NOTIFICATION RECEIPTS + PRODUCT DB'),
      findsOneWidget,
    );
    expect(find.text('WINDOW · TRAILING 7D · ET'), findsOneWidget);
    expect(find.text('COVERAGE · UNAVAILABLE'), findsOneWidget);
    expect(find.text('COVERAGE · NOT APPLICABLE'), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();

    await _expand(tester, 'RETENTION');
    final cohortInfo = find.bySemanticsLabel('Definition for 2026-08-10');
    await tester.ensureVisible(cohortInfo);
    await tester.tap(cohortInfo);
    await tester.pump();
    expect(
      find.text('SOURCE · FOREGROUND TELEMETRY + PRODUCT DB'),
      findsOneWidget,
    );
    expect(find.text('WINDOW · 2026-08-10 COHORT · D1/D7/D30'), findsOneWidget);
    expect(find.textContaining('COVERAGE · D1 UNAVAILABLE'), findsOneWidget);
    expect(find.text('COVERAGE · NOT APPLICABLE'), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();

    await _expand(tester, 'ONBOARDING FUNNEL');
    final onboardingInfo = find.bySemanticsLabel('Definition for Started');
    await tester.ensureVisible(onboardingInfo);
    await tester.tap(onboardingInfo);
    await tester.pump();
    expect(find.text('SOURCE · ACTIVATION TELEMETRY'), findsOneWidget);
    expect(
      find.text('WINDOW · 30D START COHORT · FIRST 24 ELAPSED HOURS'),
      findsOneWidget,
    );
    expect(
      find.text('COVERAGE · CAPABILITY-SCOPED IOS COHORT'),
      findsOneWidget,
    );
  });

  testWidgets('missing section-specific windows render unavailable', (
    tester,
  ) async {
    final responses = _completeResponses();
    final onboardingEnvelope =
        responses['dashboard-funnels']!['metricsDashboard']
            as Map<String, dynamic>;
    final onboarding =
        onboardingEnvelope['onboardingFunnel'] as Map<String, dynamic>;
    onboarding.remove('cohortWindowDays');
    final releaseEnvelope =
        responses['dashboard-release-adoption']!['metricsDashboard']
            as Map<String, dynamic>;
    final release = releaseEnvelope['releaseAdoption'] as Map<String, dynamic>;
    release.remove('windowDays');

    await _pump(tester, _DashboardApi(responses: responses));
    await _expand(tester, 'ONBOARDING FUNNEL');
    expect(find.text('WINDOW UNAVAILABLE START COHORT · 24H'), findsOneWidget);

    await _expand(tester, 'DEBUG');
    final releaseHeader = find.byKey(
      const Key('admin-section-header-RELEASE ADOPTION'),
    );
    await tester.ensureVisible(releaseHeader);
    await tester.tap(releaseHeader);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      find.text('Accounts seen by backend · window unavailable'),
      findsOneWidget,
    );
  });

  testWidgets('compact and wide iPhones keep long rows inside their boards', (
    tester,
  ) async {
    for (final size in const [Size(320, 1000), Size(430, 1000)]) {
      final api = _DashboardApi(responses: _completeResponses());
      await _pump(tester, api, logicalSize: size);
      await _expand(tester, 'RACE + ENGAGEMENT');
      expect(tester.takeException(), isNull, reason: 'overflow at $size');
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
    'non-iOS keeps the legacy Admin surface and emits no v2 request',
    (tester) async {
      final api = _DashboardApi(
        responses: {
          'legacy': {
            'users': {'total': 3},
          },
        },
      );
      await _pump(tester, api, ios: false);

      expect(api.calls, ['legacy']);
      expect(find.byKey(const Key('admin-section-GROWTH')), findsOneWidget);
      expect(find.byKey(const Key('admin-section-SUMMARY')), findsNothing);
    },
  );
}
