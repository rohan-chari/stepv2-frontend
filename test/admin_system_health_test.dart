import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/admin_system_health.dart';
import 'package:step_tracker/screens/admin_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/spinning_crate.dart';

class _SystemHealthApi extends BackendApiService {
  _SystemHealthApi({List<Object>? results, this.blocker})
    : results =
          results ??
          <Object>[AdminSystemHealthFetchResult.available(_health())];

  final List<Object> results;
  final Completer<void>? blocker;
  final List<String> calls = [];
  int _resultIndex = 0;

  @override
  Future<Map<String, dynamic>> fetchAdminStats({
    required String identityToken,
    List<String> sections = const [],
    String? window,
  }) async {
    calls.add('stats:${sections.isEmpty ? 'legacy' : sections.single}');
    if (sections.contains('dashboard-summary')) {
      return {
        'metricsDashboard': {
          'schemaVersion': 2,
          'status': 'available',
          'window': {
            'days': 30,
            'start': '2026-07-31',
            'end': '2026-08-29',
            'timeZone': 'America/New_York',
          },
          'sources': {
            'productDb': {
              'status': 'available',
              'asOf': '2026-08-29T19:30:00.000Z',
            },
            'foregroundActivity': {
              'status': 'available',
              'asOf': '2026-08-29T19:30:00.000Z',
            },
            'appStoreConnect': {'status': 'not_configured', 'asOf': null},
            'admob': {'status': 'not_configured', 'asOf': null},
          },
          'summary': {
            'growth': {'totalSignups': 10},
          },
        },
      };
    }
    return {
      'users': {'total': 10},
    };
  }

  @override
  Future<Map<String, dynamic>> fetchAdminSettings({
    required String identityToken,
  }) async => const {'bannerAdsEnabled': true};

  @override
  Future<AdminSystemHealthFetchResult> fetchAdminSystemHealth({
    required String identityToken,
  }) async {
    calls.add('system-health');
    if (blocker != null) await blocker!.future;
    final index = _resultIndex < results.length
        ? _resultIndex++
        : results.length - 1;
    final result = results[index];
    if (result is Exception) throw result;
    return result as AdminSystemHealthFetchResult;
  }
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

Map<String, dynamic> _pool({int checkedOut = 5, int waiting = 0}) => {
  'max': 20,
  'total': 12,
  'idle': 7,
  'nonIdle': 5,
  'checkedOut': checkedOut,
  'waiting': waiting,
};

Map<String, dynamic> _last60m() => {
  'acquisitions': 4100,
  'releases': 4100,
  'queuedCheckouts': 3,
  'queuedTimeouts': 0,
  'queuedWaitP95Ms': 12,
  'queuedWaitMaxMs': 44,
  'physicalAttempts': 2,
  'physicalTimeouts': 0,
  'physicalErrors': 0,
};

Map<String, dynamic> _process(String role, String instance) => {
  'role': role,
  'instance': instance,
  'status': 'healthy',
  'capturedAt': '2026-08-29T19:29:40.000Z',
  'coverageMinutes': 60,
  'oldestBucketAt': '2026-08-29T18:30:00.000Z',
  'newestBucketAt': '2026-08-29T19:29:00.000Z',
  'pool': _pool(),
  'last60m': _last60m(),
  'process': {
    'rssBytes': 410000000,
    'cpuOneCorePercent': 18.2,
    'eventLoopP99Ms': 8.4,
  },
};

Map<String, dynamic> _endpoint(
  String endpoint, {
  int requests = 10,
  int successes = 9,
  int requestFailures = 1,
  int serverFailures = 0,
}) => {
  'endpoint': endpoint,
  'requests': requests,
  'successes': successes,
  'requestFailures': requestFailures,
  'serverFailures': serverFailures,
};

Map<String, dynamic> _failureWindow(
  String window,
  int windowMinutes, {
  String collectionStatus = 'complete',
  int? completeCoverageMinutes,
  int partialCoverageMinutes = 0,
  int requests = 30,
  int successes = 27,
  int requestFailures = 3,
  int serverFailures = 1,
}) => {
  'window': window,
  'windowMinutes': windowMinutes,
  'collectionStatus': collectionStatus,
  'completeCoverageMinutes':
      completeCoverageMinutes ??
      (collectionStatus == 'complete' ? windowMinutes : 17),
  'partialCoverageMinutes': partialCoverageMinutes,
  'requests': requests,
  'successes': successes,
  'requestFailures': requestFailures,
  'serverFailures': serverFailures,
  'endpoints': [
    _endpoint('steps', serverFailures: 1),
    _endpoint('samples'),
    _endpoint('sync-v2'),
  ],
};

Map<String, dynamic> _health({
  String status = 'available',
  String overall = 'healthy',
  String historyStatus = 'available',
  int windowCoverageMinutes = 60,
}) => {
  'schema': 'admin-system-health-v1',
  'status': status,
  'overall': overall,
  'historyStatus': historyStatus,
  'generatedAt': '2026-08-29T19:30:00.000Z',
  'windowMinutes': 60,
  'windowCoverageMinutes': windowCoverageMinutes,
  'expectedProcesses': 4,
  'freshProcesses': 4,
  'missingProcesses': <Map<String, dynamic>>[],
  'processes': [
    _process('http', '0'),
    _process('http', '1'),
    _process('resolution', '0'),
    _process('cron', '0'),
  ],
  'stepIngestion': {
    'contributingHttpProcesses': 2,
    'requests': 30,
    'successes': 27,
    'failures': 3,
    'queuedTimeouts': 0,
    'latencyP95Ms': 640,
    'transactionP95Ms': 310,
    'phases': [
      {
        'phase': 'transaction_total',
        'observations': 30,
        'samplingRate': 1.0,
        'p95Ms': 310,
        'maxMs': 910,
      },
    ],
    'endpoints': [
      {
        ..._endpoint('steps'),
        'failures': 1,
        'queuedTimeouts': 0,
        'latencyP95Ms': 710,
        'transactionP95Ms': 340,
      },
      {
        ..._endpoint('samples'),
        'failures': 1,
        'queuedTimeouts': 0,
        'latencyP95Ms': 620,
        'transactionP95Ms': 300,
      },
      {
        ..._endpoint('sync-v2'),
        'failures': 1,
        'queuedTimeouts': 0,
        'latencyP95Ms': 590,
        'transactionP95Ms': 280,
      },
    ],
  },
  'failureWindows': [
    _failureWindow('60m', 60),
    _failureWindow(
      '24h',
      1440,
      collectionStatus: 'collecting',
      completeCoverageMinutes: 377,
      partialCoverageMinutes: 2,
    ),
    _failureWindow(
      '7d',
      10080,
      collectionStatus: 'collecting',
      completeCoverageMinutes: 377,
      partialCoverageMinutes: 2,
    ),
  ],
};

Future<void> _pump(
  WidgetTester tester,
  _SystemHealthApi api, {
  bool ios = true,
  Size size = const Size(390, 1200),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: AdminScreen(
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

Future<void> _expand(WidgetTester tester) async {
  final header = find.byKey(const Key('admin-section-header-SYSTEM HEALTH'));
  await tester.ensureVisible(header);
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

  group('AdminSystemHealthEnvelope parser', () {
    test('reads the complete contract and derives rates', () {
      final parsed = AdminSystemHealthEnvelope.tryParse(
        _health(),
        now: DateTime.utc(2026, 8, 29, 19, 30),
      );

      expect(parsed, isNotNull);
      expect(parsed!.processes, hasLength(4));
      expect(parsed.failureWindows, hasLength(3));
      expect(parsed.failureWindows[0].requestFailureRate, 0.1);
      expect(
        parsed.failureWindows[0].serverFailureRate,
        closeTo(1 / 30, 0.001),
      );
      expect(parsed.stepIngestion!.endpoints.map((e) => e.endpoint), [
        'steps',
        'samples',
        'sync-v2',
      ]);
    });

    test('ignores additive fields', () {
      final raw = _health()..['future'] = {'anything': true};
      expect(
        AdminSystemHealthEnvelope.tryParse(
          raw,
          now: DateTime.utc(2026, 8, 29, 19, 30),
        ),
        isNotNull,
      );
    });

    test(
      'rejects missing, null, malformed, duplicate, and unknown identities',
      () {
        final cases = <Map<String, dynamic>>[
          {..._health()}..remove('status'),
          {..._health(), 'status': null},
          {..._health(), 'overall': 'future'},
          {..._health(), 'windowCoverageMinutes': -1},
          {..._health(), 'expectedProcesses': 9007199254740992},
          {
            ..._health(),
            'processes': [_process('http', '0'), _process('http', '0')],
          },
          {
            ..._health(),
            'processes': [_process('future', '0')],
          },
        ];
        for (final raw in cases) {
          expect(
            AdminSystemHealthEnvelope.tryParse(
              raw,
              now: DateTime.utc(2026, 8, 29, 19, 30),
            ),
            isNull,
            reason: raw.toString(),
          );
        }
      },
    );

    test('zero-request window exposes null percentages', () {
      final raw = _health();
      raw['failureWindows'] = [
        _failureWindow(
            '60m',
            60,
            requests: 0,
            successes: 0,
            requestFailures: 0,
            serverFailures: 0,
          )
          ..['endpoints'] = [
            _endpoint('steps', requests: 0, successes: 0, requestFailures: 0),
            _endpoint('samples', requests: 0, successes: 0, requestFailures: 0),
            _endpoint('sync-v2', requests: 0, successes: 0, requestFailures: 0),
          ],
        _failureWindow('24h', 1440),
        _failureWindow('7d', 10080),
      ];
      final parsed = AdminSystemHealthEnvelope.tryParse(
        raw,
        now: DateTime.utc(2026, 8, 29, 19, 30),
      );
      expect(parsed!.failureWindows.first.requestFailureRate, isNull);
      expect(parsed.failureWindows.first.serverFailureRate, isNull);
    });

    test('zero pool coverage accepts only two null bucket timestamps', () {
      final zeroCoverage = _health(
        overall: 'unknown',
        windowCoverageMinutes: 0,
      );
      for (final process in zeroCoverage['processes']! as List) {
        final row = process as Map<String, dynamic>;
        row
          ..['coverageMinutes'] = 0
          ..['oldestBucketAt'] = null
          ..['newestBucketAt'] = null;
      }

      final parsed = AdminSystemHealthEnvelope.tryParse(
        zeroCoverage,
        now: DateTime.utc(2026, 8, 29, 19, 30),
      );
      expect(parsed, isNotNull);
      expect(parsed!.processes.first.oldestBucketAt, isNull);
      expect(parsed.processes.first.newestBucketAt, isNull);

      for (final key in ['oldestBucketAt', 'newestBucketAt']) {
        final inconsistent = _health(
          overall: 'unknown',
          windowCoverageMinutes: 0,
        );
        for (final process in inconsistent['processes']! as List) {
          final row = process as Map<String, dynamic>;
          row
            ..['coverageMinutes'] = 0
            ..['oldestBucketAt'] = null
            ..['newestBucketAt'] = null;
        }
        (inconsistent['processes']! as List)
                .cast<Map<String, dynamic>>()
                .first[key] =
            '2026-08-29T19:29:00.000Z';
        expect(
          AdminSystemHealthEnvelope.tryParse(
            inconsistent,
            now: DateTime.utc(2026, 8, 29, 19, 30),
          ),
          isNull,
          reason: 'zero coverage cannot carry $key',
        );
      }

      for (final key in ['oldestBucketAt', 'newestBucketAt']) {
        final positiveCoverage = _health();
        (positiveCoverage['processes']! as List)
                .cast<Map<String, dynamic>>()
                .first[key] =
            null;
        expect(
          AdminSystemHealthEnvelope.tryParse(
            positiveCoverage,
            now: DateTime.utc(2026, 8, 29, 19, 30),
          ),
          isNull,
          reason: 'positive coverage requires $key',
        );
      }
    });
  });

  testWidgets(
    'both branches place one lazy section immediately before CONFIG',
    (tester) async {
      for (final ios in [true, false]) {
        final api = _SystemHealthApi();
        await _pump(tester, api, ios: ios);
        expect(
          find.byKey(const Key('admin-section-SYSTEM HEALTH')),
          findsOneWidget,
        );
        expect(api.calls.where((call) => call == 'system-health'), isEmpty);
        expect(find.text('POOL NOW'), findsNothing);
        final systemY = tester
            .getTopLeft(find.byKey(const Key('admin-section-SYSTEM HEALTH')))
            .dy;
        final configY = tester
            .getTopLeft(find.byKey(const Key('admin-section-CONFIG')))
            .dy;
        expect(systemY, lessThan(configY));

        await _expand(tester);
        expect(
          api.calls.where((call) => call == 'system-health'),
          hasLength(1),
        );
        expect(find.text('POOL NOW'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'renders process rows and exact complete/collecting failure cards',
    (tester) async {
      await _pump(tester, _SystemHealthApi());
      await _expand(tester);

      expect(find.text('HEALTHY'), findsOneWidget);
      expect(find.text('HTTP 0'), findsOneWidget);
      expect(find.text('HTTP 1'), findsOneWidget);
      expect(find.text('RESOLUTION 0'), findsOneWidget);
      expect(find.text('CRON 0'), findsOneWidget);
      expect(find.text('REQUEST FAILURE RATE'), findsOneWidget);
      expect(find.text('60 MIN'), findsOneWidget);
      expect(find.text('24 HOURS'), findsOneWidget);
      expect(find.text('7 DAYS'), findsOneWidget);
      expect(find.text('10.0% · 3 / 30'), findsNWidgets(3));
      expect(find.text('3.3% · 1 / 30'), findsNWidgets(3));
      expect(find.text('TELEMETRY COMPLETE'), findsOneWidget);
      expect(
        find.text('TELEMETRY COLLECTING — 377 OF 1,440 MINUTES'),
        findsOneWidget,
      );
      expect(find.text('+2 PARTIAL'), findsNWidgets(2));
      expect(find.text('OBSERVED TELEMETRY'), findsNWidgets(3));
    },
  );

  testWidgets('first expansion shows an in-section loader until data arrives', (
    tester,
  ) async {
    final blocker = Completer<void>();
    final api = _SystemHealthApi(blocker: blocker);
    await _pump(tester, api);
    final header = find.byKey(const Key('admin-section-header-SYSTEM HEALTH'));
    await tester.ensureVisible(header);
    await tester.tap(header, warnIfMissed: false);
    await tester.pump();
    await tester.pump();

    expect(find.byType(SpinningCrate), findsOneWidget);
    expect(find.text('Couldn’t load system health.'), findsNothing);

    blocker.complete();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('HEALTHY'), findsOneWidget);
  });

  testWidgets(
    'status plate distinguishes pressure, degraded, and pool collection',
    (tester) async {
      for (final state in const [
        ('pressure', 'PRESSURE'),
        ('degraded', 'DEGRADED'),
      ]) {
        await _pump(
          tester,
          _SystemHealthApi(
            results: [
              AdminSystemHealthFetchResult.available(
                _health(overall: state.$1),
              ),
            ],
          ),
        );
        await _expand(tester);
        expect(find.text(state.$2), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      }

      final collecting = _health(overall: 'unknown', windowCoverageMinutes: 17);
      for (final process in collecting['processes']! as List) {
        (process as Map<String, dynamic>)['coverageMinutes'] = 17;
      }
      await _pump(
        tester,
        _SystemHealthApi(
          results: [AdminSystemHealthFetchResult.available(collecting)],
        ),
      );
      await _expand(tester);
      expect(find.text('COLLECTING — LAST 17 MINUTES'), findsOneWidget);
      expect(find.text('LAST 17 MINUTES'), findsOneWidget);
    },
  );

  testWidgets(
    'partial pool keeps four fixed positions and marks the missing row',
    (tester) async {
      final partial = _health(
        status: 'partial',
        overall: 'degraded',
        windowCoverageMinutes: 60,
      );
      partial
        ..['freshProcesses'] = 3
        ..['processes'] = (partial['processes']! as List).take(3).toList()
        ..['missingProcesses'] = [
          {'role': 'cron', 'instance': '0', 'reason': 'stale'},
        ];
      await _pump(
        tester,
        _SystemHealthApi(
          results: [AdminSystemHealthFetchResult.available(partial)],
        ),
      );
      await _expand(tester);

      expect(find.text('DEGRADED'), findsOneWidget);
      expect(find.text('HTTP 0'), findsOneWidget);
      expect(find.text('HTTP 1'), findsOneWidget);
      expect(find.text('RESOLUTION 0'), findsOneWidget);
      expect(find.text('CRON 0'), findsOneWidget);
      expect(find.text('MISSING · STALE'), findsOneWidget);
    },
  );

  testWidgets(
    'valid pool remains visible when failure history is unavailable',
    (tester) async {
      final raw = _health(historyStatus: 'unavailable')
        ..['failureWindows'] = null;
      await _pump(
        tester,
        _SystemHealthApi(
          results: [AdminSystemHealthFetchResult.available(raw)],
        ),
      );
      await _expand(tester);

      expect(find.text('POOL NOW'), findsOneWidget);
      expect(find.text('HTTP 0'), findsOneWidget);
      expect(find.text('FAILURE HISTORY UNAVAILABLE'), findsOneWidget);
    },
  );

  testWidgets(
    'old route, malformed data, and transport errors remain retryable',
    (tester) async {
      for (final entry in <(AdminSystemHealthFetchResult, String)>[
        (
          const AdminSystemHealthFetchResult.routeUnavailable(),
          'Requires server update',
        ),
        (
          const AdminSystemHealthFetchResult.malformed(),
          'Telemetry response malformed',
        ),
      ]) {
        await _pump(tester, _SystemHealthApi(results: [entry.$1]));
        await _expand(tester);
        expect(find.text(entry.$2), findsOneWidget);
        expect(
          find.byKey(const Key('admin-system-health-retry')),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      }

      await _pump(tester, _SystemHealthApi(results: [Exception('transport')]));
      await _expand(tester);
      expect(find.text('Couldn’t load system health.'), findsOneWidget);
      expect(
        find.byKey(const Key('admin-system-health-retry')),
        findsOneWidget,
      );
    },
  );

  testWidgets('refresh failure retains good data and marks it stale', (
    tester,
  ) async {
    final api = _SystemHealthApi(
      results: [
        AdminSystemHealthFetchResult.available(_health()),
        Exception('refresh failed'),
      ],
    );
    await _pump(tester, api);
    await _expand(tester);
    final refresh = find.byKey(const Key('admin-system-health-refresh'));
    await tester.ensureVisible(refresh);
    await tester.tap(refresh);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('HEALTHY'), findsOneWidget);
    expect(find.text('STALE — REFRESH FAILED'), findsOneWidget);
    expect(api.calls.where((call) => call == 'system-health'), hasLength(2));
  });

  testWidgets('screen refresh fetches health only after it has been opened', (
    tester,
  ) async {
    final unopenedApi = _SystemHealthApi();
    await _pump(tester, unopenedApi);
    await tester.tap(find.byKey(const Key('admin-screen-refresh')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(unopenedApi.calls.where((call) => call == 'system-health'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());

    final openedApi = _SystemHealthApi();
    await _pump(tester, openedApi);
    await _expand(tester);
    await tester.tap(find.byKey(const Key('admin-screen-refresh')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      openedApi.calls.where((call) => call == 'system-health'),
      hasLength(2),
    );
  });

  testWidgets(
    'zero requests and independent pool/history availability render honestly',
    (tester) async {
      final raw = _health(
        status: 'unavailable',
        overall: 'unknown',
        historyStatus: 'available',
        windowCoverageMinutes: 0,
      );
      raw
        ..['freshProcesses'] = 0
        ..['processes'] = <Object>[]
        ..['stepIngestion'] = null
        ..['missingProcesses'] = [
          for (final identity in const [
            ('http', '0'),
            ('http', '1'),
            ('resolution', '0'),
            ('cron', '0'),
          ])
            {
              'role': identity.$1,
              'instance': identity.$2,
              'reason': 'unavailable',
            },
        ]
        ..['failureWindows'] = [
          for (final item in const [('60m', 60), ('24h', 1440), ('7d', 10080)])
            _failureWindow(
                item.$1,
                item.$2,
                requests: 0,
                successes: 0,
                requestFailures: 0,
                serverFailures: 0,
              )
              ..['endpoints'] = [
                for (final endpoint in const ['steps', 'samples', 'sync-v2'])
                  _endpoint(
                    endpoint,
                    requests: 0,
                    successes: 0,
                    requestFailures: 0,
                  ),
              ],
        ];
      await _pump(
        tester,
        _SystemHealthApi(
          results: [AdminSystemHealthFetchResult.available(raw)],
        ),
      );
      await _expand(tester);

      expect(find.text('POOL TELEMETRY UNAVAILABLE'), findsOneWidget);
      expect(find.text('HTTP 0'), findsOneWidget);
      expect(find.text('HTTP 1'), findsOneWidget);
      expect(find.text('RESOLUTION 0'), findsOneWidget);
      expect(find.text('CRON 0'), findsOneWidget);
      expect(find.text('MISSING · UNAVAILABLE'), findsNWidgets(4));
      expect(find.text('NO REQUESTS'), findsNWidgets(6));
      expect(find.text('REQUEST FAILURE RATE'), findsOneWidget);
    },
  );

  testWidgets('narrow large-text layout has no overflow or horizontal scroll', (
    tester,
  ) async {
    await _pump(
      tester,
      _SystemHealthApi(),
      ios: false,
      size: const Size(320, 1000),
      textScale: 2,
    );
    await _expand(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
}
