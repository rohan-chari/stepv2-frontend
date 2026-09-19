import 'dart:async';

import 'package:flutter/material.dart';
import 'package:step_tracker/screens/admin_dashboard_controller.dart';
import 'package:step_tracker/screens/admin_dashboard_detail.dart';
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
  final Completer<void>? blocker;
  final calls = <String>[];
  final attempts = <String, int>{};
  int inFlight = 0, maxInFlight = 0;
  @override
  Future<Map<String, dynamic>> fetchAdminStatsView({
    required String identityToken,
    required String view,
    required String window,
    required String section,
  }) async {
    calls.add(view);
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      if (blocker != null) await blocker!.future;
      final attempt = attempts.update(view, (v) => v + 1, ifAbsent: () => 1);
      if (attempt <= (failuresRemaining[view] ?? 0)) {
        throw const ApiException('Unavailable', statusCode: 503);
      }
      return {
        'view': view,
        'sections': {
          for (final name
              in AdminView.values.firstWhere((v) => v.apiName == view).sections)
            name:
                responses[name] ??
                {
                  'metricsDashboard': {
                    'schemaVersion': 2,
                    'status': 'available',
                  },
                },
        },
      };
    } finally {
      inFlight--;
    }
  }

  @override
  Future<Map<String, dynamic>> fetchAdminSettings({
    required String identityToken,
  }) async => {'bannerAdsEnabled': true};
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

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _open(WidgetTester tester, String title) async {
  final link = find.text(title);
  await tester.scrollUntilVisible(
    link,
    350,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(link);
  await _frames(tester);
  expect(find.byType(AdminDashboardDetail), findsOneWidget);
}

Future<void> _show(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
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

  testWidgets('overview shows account values and seven ordered detail links', (
    tester,
  ) async {
    final api = _DashboardApi(responses: _completeResponses());
    await _pump(tester, api);
    expect(find.text('1,234 total accounts'), findsOneWidget);
    expect(find.text('61'), findsOneWidget);
    expect(api.calls, ['overview']);
    for (final title in [
      'Growth',
      'Activity',
      'Retention',
      'Races & friends',
      'Invites & onboarding',
      'Ads & shop',
      'System health',
    ]) {
      await _show(tester, find.text(title));
      expect(find.text(title).hitTestable(), findsOneWidget);
    }
    await _show(tester, find.text('Growth'));
    await tester.tap(find.text('Growth'));
    await _frames(tester);
    expect(api.calls, ['overview', 'growth']);
    expect(api.maxInFlight, 1);
  });

  testWidgets(
    'provider-only and retired panels stay absent while Ads remains reachable',
    (tester) async {
      final api = _DashboardApi(responses: _completeResponses());
      await _pump(tester, api);
      await _open(tester, 'Ads & shop');
      expect(api.calls.last, 'ads');
      expect(find.text('Ads'), findsOneWidget);
      expect(find.text('Shop'), findsOneWidget);
      for (final removed in [
        'Ad revenue',
        'Ad impressions',
        'Match rate',
        'Real-money purchases',
        'RELEASE ADOPTION',
        'ACTIVATION',
      ]) {
        expect(find.text(removed), findsNothing);
      }
      expect(api.calls, isNot(contains('dashboard-release-adoption')));
    },
  );

  testWidgets('onboarding skip remains a side branch with start denominator', (
    tester,
  ) async {
    await _pump(tester, _DashboardApi(responses: _completeResponses()));
    await _open(tester, 'Invites & onboarding');
    await tester.tap(find.text('Onboarding'));
    await _frames(tester);
    await _show(tester, find.text('↳ Tutorial skipped'));
    expect(find.text('7'), findsWidgets);
    expect(find.textContaining('8.8% of starts'), findsOneWidget);
    final opened = find.text('Tutorial opened');
    final skipped = find.text('↳ Tutorial skipped');
    final box = find.text('Box opened');
    expect(
      tester.getTopLeft(opened).dy,
      lessThan(tester.getTopLeft(skipped).dy),
    );
    expect(tester.getTopLeft(skipped).dy, lessThan(tester.getTopLeft(box).dy));
  });

  testWidgets(
    'disabled and old-backend data preserve Tools without restoring retired panels',
    (tester) async {
      for (final response in [
        _dashboard('summary', null, status: 'disabled'),
        <String, dynamic>{
          'users': {'total': 8},
        },
      ]) {
        await _pump(
          tester,
          _DashboardApi(responses: {'dashboard-summary': response}),
        );
        expect(find.text('Couldn’t update this section.'), findsOneWidget);
        await tester.tap(find.text('Tools'));
        await _frames(tester);
        for (final label in ['Configuration', 'Inbox', 'Debugging']) {
          expect(find.text(label), findsOneWidget);
        }
        expect(find.text('RELEASE ADOPTION'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'detail failure remains retryable and successful retry restores content',
    (tester) async {
      final api = _DashboardApi(
        responses: _completeResponses(),
        failuresRemaining: {'growth': 1},
      );
      await _pump(tester, api);
      await _open(tester, 'Growth');
      expect(find.text('Couldn’t update this section.'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await _frames(tester);
      expect(find.text('Couldn’t update this section.'), findsNothing);
      expect(api.calls.where((v) => v == 'growth'), hasLength(2));
      expect(find.text('310'), findsWidgets);
    },
  );

  testWidgets('rapid refresh coalesces and refreshes only the visible page', (
    tester,
  ) async {
    final blocker = Completer<void>();
    final api = _DashboardApi(
      responses: _completeResponses(),
      blocker: blocker,
    );
    await _pump(tester, api);
    expect(api.calls, ['overview']);
    blocker.complete();
    await _frames(tester);
    await _open(tester, 'Growth');
    final refresh = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.refresh),
    );
    refresh.onPressed!();
    refresh.onPressed!();
    await _frames(tester);
    expect(api.calls, ['overview', 'growth', 'growth']);
    expect(api.maxInFlight, 1);
  });

  testWidgets('malformed leaves render unavailable and never zero or crash', (
    tester,
  ) async {
    await _pump(
      tester,
      _DashboardApi(
        responses: {
          'dashboard-summary': _dashboard('summary', {
            'growth': {
              'totalSignups': null,
              'signupsToday': 'nine',
              'signupsLast7Days': [],
            },
            'retention': 'broken',
            'races': null,
          }),
        },
      ),
    );
    expect(find.text('Unavailable total accounts'), findsOneWidget);
    expect(find.text('Unavailable'), findsWidgets);
    expect(find.text('0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('valid zero values remain distinct from missing activity', (
    tester,
  ) async {
    await _pump(
      tester,
      _DashboardApi(
        responses: {
          'dashboard-summary': _dashboard('summary', {
            'growth': {'totalSignups': 0, 'signupsLast7Days': 0},
            'races': {'usersInActiveNonFeaturedRaces': 0},
          }),
        },
      ),
    );
    expect(find.text('0 total accounts'), findsOneWidget);
    expect(find.text('0'), findsNWidgets(2));
    expect(find.text('Unavailable'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stale source retains values with timestamp provenance', (
    tester,
  ) async {
    final response = _summary();
    (response['metricsDashboard'] as Map)['sources'] = {
      'productDb': {'status': 'stale', 'asOf': '2026-08-17T15:04:05.000Z'},
    };
    await _pump(
      tester,
      _DashboardApi(responses: {'dashboard-summary': response}),
    );
    expect(find.text('1,234 total accounts'), findsOneWidget);
    final stale = find.textContaining('Product data: STALE');
    await _show(tester, stale);
    expect(stale, findsOneWidget);
    await tester.tap(stale);
    await _frames(tester);
    expect(find.textContaining('2026-08-17T15:04:05.000Z'), findsOneWidget);
  });

  testWidgets('metric definition explains source and account exclusions', (
    tester,
  ) async {
    await _pump(tester, _DashboardApi(responses: _completeResponses()));
    await tester.tap(find.byTooltip('About total accounts'));
    await _frames(tester);
    expect(find.textContaining('accounts, not installs'), findsOneWidget);
    expect(find.textContaining('Source: product database'), findsOneWidget);
    expect(
      find.textContaining('Deleted accounts are excluded'),
      findsOneWidget,
    );
  });

  testWidgets('activity definition preserves source, time scope and coverage', (
    tester,
  ) async {
    await _pump(tester, _DashboardApi(responses: _completeResponses()));
    final info = find.byTooltip('About App opens');
    await _show(tester, info);
    await tester.tap(info);
    await _frames(tester);
    expect(find.textContaining('WAU'), findsOneWidget);
    expect(find.textContaining('never a sum of daily users'), findsOneWidget);
    expect(
      find.textContaining(
        'Older clients without foreground telemetry are missing',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'onboarding without its cohort window never invents a time range',
    (tester) async {
      final responses = _completeResponses();
      ((responses['dashboard-funnels']!['metricsDashboard']
                  as Map)['onboardingFunnel']
              as Map)
          .remove('cohortWindowDays');
      await _pump(tester, _DashboardApi(responses: responses));
      await _open(tester, 'Invites & onboarding');
      await tester.tap(find.text('Onboarding'));
      await _frames(tester);
      await _show(tester, find.textContaining('Unknown-day start cohort'));
      expect(find.textContaining('Unknown-day start cohort'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact and wide iPhones keep current detail rows contained', (
    tester,
  ) async {
    for (final size in [const Size(320, 1000), const Size(430, 1000)]) {
      await _pump(
        tester,
        _DashboardApi(responses: _completeResponses()),
        logicalSize: size,
      );
      await _open(tester, 'Races & friends');
      expect(tester.takeException(), isNull, reason: 'overflow at $size');
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('Android renders the shared overview and fetches the same page', (
    tester,
  ) async {
    final api = _DashboardApi(responses: _completeResponses());
    await _pump(tester, api, ios: false);
    expect(api.calls, ['overview']);
    expect(find.text('1,234 total accounts'), findsOneWidget);
    await _open(tester, 'Growth');
    expect(api.calls, ['overview', 'growth']);
  });
  testWidgets(
    'Ads shows exact daily viewers, grants and recorded reward totals',
    (tester) async {
      await _pump(tester, _DashboardApi(responses: _completeResponses()));
      await _open(tester, 'Ads & shop');
      await _show(tester, find.text('Daily values'));
      await tester.tap(find.text('Daily values'));
      await _frames(tester);
      expect(find.text('116'), findsNWidgets(2));
      await _show(tester, find.text('Ad watches'));
      await tester.tap(find.text('Ad watches'));
      await _frames(tester);
      expect(find.text('423'), findsNWidgets(2));
      await _show(tester, find.text('Coins'));
      expect(find.text('102'), findsOneWidget);
      await tester.tap(find.text('Coins'));
      await _frames(tester);
      expect(
        find.textContaining('Source: rewarded-ad callbacks'),
        findsOneWidget,
      );
      expect(
        find.textContaining('not ad impressions or revenue'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Retention keeps zero denominator unavailable and explains mature cohort provenance',
    (tester) async {
      final responses = _completeResponses();
      final summary =
          (responses['dashboard-summary']!['metricsDashboard']
                  as Map)['summary']
              as Map;
      (summary['retention'] as Map)['d1'] = {
        'numerator': 0,
        'denominator': 0,
        'percent': null,
      };
      await _pump(tester, _DashboardApi(responses: responses));
      await _open(tester, 'Retention');
      expect(
        find.textContaining('0 of 0 · Pooled mature cohorts'),
        findsOneWidget,
      );
      expect(find.text('Unavailable'), findsWidgets);
      expect(find.text('0.0%'), findsNothing);
      await tester.tap(find.text('Day 1 return'));
      await _frames(tester);
      expect(
        find.textContaining(
          'Source: foreground telemetry and product database',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Numerator: 0. Denominator: 0.'),
        findsOneWidget,
      );
      expect(find.descendant(of: find.byType(BottomSheet), matching: find.textContaining('exact signup + 1 ET days')), findsOneWidget);
      await tester.tap(find.byTooltip('Close definition'));
      await _frames(tester);
      await _show(tester, find.text('View daily cohorts'));
      await tester.tap(find.text('View daily cohorts'));
      await _frames(tester);
      await _show(tester, find.text('2026-08-10'));
      await tester.tap(find.text('2026-08-10'));
      await _frames(tester);
      expect(find.textContaining('this ET signup date'), findsOneWidget);
      expect(
        find.textContaining('exact-day foreground return'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'onboarding side-branch definition retains activation source and start denominator',
    (tester) async {
      await _pump(tester, _DashboardApi(responses: _completeResponses()));
      await _open(tester, 'Invites & onboarding');
      await tester.tap(find.text('Onboarding'));
      await _frames(tester);
      await _show(tester, find.text('↳ Tutorial skipped'));
      await tester.tap(find.text('↳ Tutorial skipped'));
      await _frames(tester);
      expect(
        find.textContaining('Source: activation telemetry'),
        findsOneWidget,
      );
      expect(find.textContaining('Start conversion: 7 / 80.'), findsOneWidget);
      expect(find.textContaining('within 24 elapsed hours'), findsOneWidget);
      expect(find.textContaining('Previous-spine conversion'), findsNothing);
    },
  );
}
