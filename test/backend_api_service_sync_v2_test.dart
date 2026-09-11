import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:step_tracker/models/race_resolution_status.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/models/step_sample_data.dart';
import 'package:step_tracker/models/step_sync_v2_result.dart';
import 'package:step_tracker/services/backend_api_service.dart';

/// A programmable fake that serves a queue of scripted responses per request and
/// records every request path + body, so tests can assert on the wire contract,
/// retries, and idempotency-key reuse.
class _Scripted {
  _Scripted(this.status, this.body, {this.throwOnSend = false});
  final int status;
  final String body;
  final bool throwOnSend;
}

class _CapturedRequest {
  _CapturedRequest(this.method, this.uri);
  final String method;
  final Uri uri;
  final StringBuffer body = StringBuffer();
  final Map<String, String> headers = {};
}

class _FakeHeaders implements HttpHeaders {
  final _CapturedRequest captured;
  _FakeHeaders(this.captured);

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    captured.headers[name] = value.toString();
  }

  @override
  ContentType? contentType;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse(this._status, this._body);
  final int _status;
  final String _body;

  @override
  int get statusCode => _status;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([utf8.encode(_body)]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this.captured, this._script);
  final _CapturedRequest captured;
  final _Scripted _script;

  @override
  late final HttpHeaders headers = _FakeHeaders(captured);

  @override
  void write(Object? object) => captured.body.write(object);

  @override
  Future<HttpClientResponse> close() async {
    if (_script.throwOnSend) {
      throw const SocketException('connection reset');
    }
    return _FakeResponse(_script.status, _script.body);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this._scripts);
  final List<_Scripted> _scripts;
  final List<_CapturedRequest> requests = [];
  int _i = 0;

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final captured = _CapturedRequest(method, url);
    requests.add(captured);
    final script = _scripts[_i < _scripts.length ? _i : _scripts.length - 1];
    _i += 1;
    return _FakeRequest(captured, script);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LegacyHomeApi extends BackendApiService {
  _LegacyHomeApi(HttpClient client) : super(httpClient: client);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (call) async => 'America/New_York',
        );
  });

  group('Home sync refresh wire contract', () {
    test(
      'legacy demo/test subclass never inherits live narrow networking',
      () async {
        final http = _FakeHttpClient([_Scripted(500, '{}')]);
        final api = _LegacyHomeApi(http);
        expect(
          (await api.fetchHomeSyncRefresh(identityToken: 'demo')).unsupported,
          true,
        );
        expect(http.requests, isEmpty);
      },
    );
    final coreStates = <Map<String, dynamic>>[
      {'state': 'EMPTY', 'data': {}},
      {
        'state': 'ACTIVE_RACES',
        'data': {
          'races': [
            {'raceId': 'r'},
          ],
        },
      },
      {
        'state': 'ACTIVE_RACE',
        'data': {'raceId': 'r', 'me': null, 'leader': null, 'others': []},
      },
      {
        'state': 'PENDING_INVITE',
        'data': {'raceId': 'r'},
      },
      {
        'state': 'PUBLIC_RACE',
        'data': {'raceId': 'r'},
      },
      {
        'state': 'FRIEND_RACING',
        'data': {'raceId': 'r', 'friend': {}, 'participants': []},
      },
      {
        'state': 'FRIEND_FINISHED',
        'data': {'friend': {}, 'raceName': 'Race'},
      },
    ];
    Map<String, dynamic> envelope(Object? core) => {
      'contract': 'home-sync-refresh-v1',
      'home': core,
      'retainedSections': ['presentation', 'friends'],
    };
    setUp(() {
      PackageInfo.setMockInitialValues(
        appName: 'Bara',
        packageName: 'bara',
        version: '2.3.13',
        buildNumber: '12',
        buildSignature: '',
      );
    });
    for (final core in coreStates) {
      test(
        'accepts complete ${core['state']} and sends existing headers',
        () async {
          final http = _FakeHttpClient([
            _Scripted(200, jsonEncode(envelope(core))),
          ]);
          final api = BackendApiService(httpClient: http)
            ..onAuthenticatedUser('user');
          final result = await api.fetchHomeSyncRefresh(identityToken: 'token');
          expect(result.home, core);
          expect(result.unsupported, false);
          final request = http.requests.single;
          expect(request.method, 'GET');
          expect(request.uri.path, '/home/race-card');
          expect(request.uri.queryParameters['view'], 'sync-refresh-v1');
          expect(request.uri.queryParameters['homeActiveRaces'], '1');
          expect(
            request.uri.queryParameters['localDate'],
            matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
          );
          expect(
            request.uri.queryParameters.containsKey('homePersistedTotals'),
            false,
          );
          expect(
            request.headers[HttpHeaders.authorizationHeader],
            'Bearer token',
          );
          expect(request.headers['X-Timezone'], 'America/New_York');
          expect(request.headers['X-App-Version'], '2.3.13');
          expect(request.headers['X-Client-Features'], isNotEmpty);
        },
      );
    }
    for (final invalid in <Object?>[
      null,
      {},
      {'state': 'UNKNOWN', 'data': {}},
      {'state': 'EMPTY'},
      {'state': 'EMPTY', 'data': null},
      {
        'state': 'ACTIVE_RACES',
        'data': {
          'races': [null],
        },
      },
      {
        'state': 'ACTIVE_RACES',
        'data': {
          'races': [
            {'raceId': ''},
          ],
        },
      },
      {
        'state': 'ACTIVE_RACE',
        'data': {'raceId': 'r', 'me': 'bad', 'others': []},
      },
      {
        'state': 'ACTIVE_RACE',
        'data': {'raceId': 'r', 'others': null},
      },
      {
        'state': 'PENDING_INVITE',
        'data': {'raceId': 7},
      },
      {
        'state': 'FRIEND_RACING',
        'data': {'raceId': 'r', 'friend': null, 'participants': []},
      },
      {
        'state': 'FRIEND_FINISHED',
        'data': {'friend': {}, 'raceName': null},
      },
    ]) {
      test('rejects incomplete core $invalid', () async {
        final api = BackendApiService(
          httpClient: _FakeHttpClient([
            _Scripted(200, jsonEncode(envelope(invalid))),
          ]),
        );
        final result = await api.fetchHomeSyncRefresh(identityToken: 'token');
        expect(result.home, isNull);
        expect(result.unsupported, true);
      });
    }
    for (final retained in <Object?>[
      null,
      [],
      ['friends', 'presentation'],
      ['presentation'],
      ['presentation', 'friends', 'coins'],
    ]) {
      test('rejects unsupported retained sections $retained', () async {
        final http = _FakeHttpClient([
          _Scripted(
            200,
            jsonEncode({
              ...envelope(coreStates.first),
              'retainedSections': retained,
            }),
          ),
        ]);
        final api = BackendApiService(httpClient: http);
        expect(
          (await api.fetchHomeSyncRefresh(identityToken: 'token')).unsupported,
          true,
        );
      });
    }
    for (final status in [200, 404, 405]) {
      test('old server $status remembered until account reset', () async {
        final http = _FakeHttpClient([
          _Scripted(status, jsonEncode({'state': 'EMPTY'})),
          _Scripted(200, jsonEncode(envelope(coreStates.first))),
        ]);
        final api = BackendApiService(httpClient: http)
          ..onAuthenticatedUser('a');
        expect(
          (await api.fetchHomeSyncRefresh(identityToken: 'a')).unsupported,
          true,
        );
        api.onAuthenticatedUser('a');
        expect(
          (await api.fetchHomeSyncRefresh(
            identityToken: 'rotated-a',
          )).unsupported,
          true,
        );
        expect(http.requests, hasLength(1));
        api.onAuthenticatedUser('b');
        expect(
          (await api.fetchHomeSyncRefresh(identityToken: 'b')).home,
          coreStates.first,
        );
        expect(http.requests, hasLength(2));
        api.resetSessionCapabilities();
        await api.fetchHomeSyncRefresh(identityToken: 'b');
        expect(http.requests, hasLength(3));
      });
    }
    for (final status in [401, 403, 500, 503]) {
      test('HTTP $status does not fall back or remember unsupported', () async {
        final http = _FakeHttpClient([
          _Scripted(status, '{}'),
          _Scripted(200, jsonEncode(envelope(coreStates.first))),
        ]);
        final api = BackendApiService(httpClient: http);
        final result = await api.fetchHomeSyncRefresh(identityToken: 'token');
        expect(result.home, isNull);
        expect(result.unsupported, false);
        expect(http.requests, hasLength(1));
        expect(
          (await api.fetchHomeSyncRefresh(identityToken: 'token')).home,
          coreStates.first,
        );
      });
    }
    test(
      'socket failure retains negotiation and never retries immediately',
      () async {
        final http = _FakeHttpClient([
          _Scripted(200, '{}', throwOnSend: true),
          _Scripted(200, jsonEncode(envelope(coreStates.first))),
        ]);
        final api = BackendApiService(httpClient: http);
        expect(
          (await api.fetchHomeSyncRefresh(identityToken: 'token')).unsupported,
          false,
        );
        expect(http.requests, hasLength(1));
        expect(
          (await api.fetchHomeSyncRefresh(identityToken: 'token')).home,
          coreStates.first,
        );
      },
    );
  });

  final stepData = StepData(steps: 12345, date: DateTime(2026, 7, 17));
  final samples = [
    StepSampleData(
      periodStart: DateTime.utc(2026, 7, 17, 13),
      periodEnd: DateTime.utc(2026, 7, 17, 14),
      steps: 731,
    ),
  ];

  Map<String, dynamic> payload() => BackendApiService.buildStepSyncV2Payload(
    stepData: stepData,
    samples: samples,
  );

  group('buildStepSyncV2Payload', () {
    test('sorts samples chronologically and uses integer steps + date', () {
      final unsorted = [
        StepSampleData(
          periodStart: DateTime.utc(2026, 7, 17, 15),
          periodEnd: DateTime.utc(2026, 7, 17, 16),
          steps: 200,
        ),
        StepSampleData(
          periodStart: DateTime.utc(2026, 7, 17, 13),
          periodEnd: DateTime.utc(2026, 7, 17, 14),
          steps: 100,
        ),
      ];
      final p = BackendApiService.buildStepSyncV2Payload(
        stepData: stepData,
        samples: unsorted,
      );
      expect(p['date'], '2026-07-17');
      expect(p['steps'], 12345);
      final s = p['samples'] as List;
      expect(s.length, 2);
      expect((s.first as Map)['periodStart'], contains('T13:'));
      expect((s.last as Map)['periodStart'], contains('T15:'));
    });
  });

  group('generateIdempotencyKey', () {
    test('is a canonical 36-char v4 UUID', () {
      final key = BackendApiService.generateIdempotencyKey();
      expect(key.length, 36);
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}'
          r'-[0-9a-f]{12}$',
        ).hasMatch(key),
        isTrue,
      );
    });
  });

  test(
    'Races-tab reads use the compact core and current background routes',
    () async {
      final http = _FakeHttpClient([
        _Scripted(
          200,
          jsonEncode({
            'contract': 'race-list-compact-v1',
            'active': <Object>[],
            'pending': <Object>[],
            'completed': <Object>[],
          }),
        ),
        _Scripted(
          200,
          jsonEncode({
            'contract': 'race-discovery-summary-v1',
            'resolved': <String, bool>{},
          }),
        ),
        _Scripted(
          200,
          jsonEncode({
            'contract': 'friends-summary-v1',
            'friends': <Object>[],
            'pending': {'incoming': <Object>[], 'outgoing': <Object>[]},
          }),
        ),
      ]);
      final api = BackendApiService(httpClient: http);

      await api.fetchRaces(identityToken: 'session-token');
      await api.fetchRaceDiscoverySummary(identityToken: 'session-token');
      await api.fetchFriends(identityToken: 'session-token');

      expect(http.requests, hasLength(3));
      expect(
        http.requests.map((request) => request.method),
        everyElement('GET'),
      );
      expect(http.requests[0].uri.path, '/races');
      expect(http.requests[0].uri.queryParameters, {'view': 'compact-v1'});
      expect(http.requests[1].uri.path, '/races/discovery-summary');
      expect(http.requests[1].uri.query, isEmpty);
      expect(http.requests[2].uri.path, '/friends');
      expect(http.requests[2].uri.queryParameters, {'view': 'summary-v1'});
      expect(
        http.requests.map((request) => request.headers['authorization']),
        everyElement('Bearer session-token'),
      );
    },
  );

  group('recordStepSyncV2', () {
    String successBody(String state, {String? jobId, int? generation}) =>
        jsonEncode({
          'record': {
            'id': 'r',
            'userId': 'u',
            'date': '2026-07-17T00:00:00.000Z',
            'steps': 12345,
            'stepGoal': 5000,
          },
          'sampleCount': 1,
          'uploaderReconciliation': {
            'state': state,
            'resolvedRaceCount': 18,
            'boxStateCurrent': state == 'CURRENT',
          },
          if (jobId != null)
            'raceResolution': {
              'jobId': jobId,
              'generation': generation,
              'state': 'QUEUED',
              'requestedAt': '2026-07-17T18:22:10.000Z',
            },
        });

    test('CURRENT success -> current, parses job + reconciliation', () async {
      final http = _FakeHttpClient([
        _Scripted(202, successBody('CURRENT', jobId: 'job-1', generation: 14)),
      ]);
      final api = BackendApiService(httpClient: http);
      final key = BackendApiService.generateIdempotencyKey();

      final r = await api.recordStepSyncV2(
        identityToken: 't',
        idempotencyKey: key,
        payload: payload(),
      );

      expect(r.kind, StepSyncV2Kind.current);
      expect(r.usePersistedHome, isTrue);
      expect(r.jobId, 'job-1');
      expect(r.generation, 14);
      expect(r.resolvedRaceCount, 18);
      expect(r.boxStateCurrent, isTrue);
      expect(r.hasJob, isTrue);
      expect(r.shouldLegacyFallback, isFalse);
      // Sent the idempotency key + posted to sync-v2.
      expect(http.requests.single.uri.path, '/steps/sync-v2');
      expect(http.requests.single.headers['Idempotency-Key'], key);
      expect(api.syncV2Support, EndpointSupport.supported);
    });

    test(
      'ignores historical work receipt without changing sync success',
      () async {
        final body =
            jsonDecode(successBody('CURRENT', jobId: 'job-1', generation: 1))
                as Map<String, dynamic>;
        body['globalEventSummaryWork'] = {
          'id': 'work-1',
          'state': 'WAITING_RACES',
          'expiresAt': '2026-08-27T04:00:00.000Z',
        };
        final api = BackendApiService(
          httpClient: _FakeHttpClient([_Scripted(202, jsonEncode(body))]),
        );

        final result = await api.recordStepSyncV2(
          identityToken: 't',
          idempotencyKey: 'work-receipt',
          payload: payload(),
        );

        expect(result.kind, StepSyncV2Kind.current);
        expect(result.hasJob, isTrue);
      },
    );

    test('ignores historical work receipt on deferred sync', () async {
      final body =
          jsonDecode(successBody('DEFERRED', jobId: 'job-1', generation: 1))
              as Map<String, dynamic>;
      body['globalEventSummaryWork'] = {
        'id': 'existing-work-1',
        'state': 'WAITING_RACES',
        'expiresAt': '2026-08-27T04:00:00.000Z',
      };
      final api = BackendApiService(
        httpClient: _FakeHttpClient([_Scripted(202, jsonEncode(body))]),
      );

      final result = await api.recordStepSyncV2(
        identityToken: 't',
        idempotencyKey: 'later-existing-work',
        payload: payload(),
        homePull: true,
      );

      expect(result.kind, StepSyncV2Kind.deferred);
      expect(result.hasJob, isTrue);
    });

    test(
      'malformed summary work receipt does not invalidate sync success',
      () async {
        final body =
            jsonDecode(successBody('CURRENT', jobId: 'job-1', generation: 1))
                as Map<String, dynamic>;
        body['globalEventSummaryWork'] = {
          'id': 'work-1',
          'state': 'A_NEW_UNKNOWN_STATE',
          'expiresAt': null,
        };
        final api = BackendApiService(
          httpClient: _FakeHttpClient([_Scripted(202, jsonEncode(body))]),
        );

        final result = await api.recordStepSyncV2(
          identityToken: 't',
          idempotencyKey: 'bad-work-receipt',
          payload: payload(),
        );

        expect(result.kind, StepSyncV2Kind.current);
        expect(result.hasJob, isTrue);
      },
    );

    test('Home pull sends the exact opt-in header and parses cooldown', () async {
      final http = _FakeHttpClient([
        _Scripted(
          429,
          '{"error":"Step sync is cooling down","code":"STEP_SYNC_COOLDOWN","retryAfterSeconds":18}',
        ),
      ]);
      final api = BackendApiService(httpClient: http);

      final result = await api.recordStepSyncV2(
        identityToken: 't',
        idempotencyKey: 'home-pull-key',
        payload: payload(),
        homePull: true,
      );

      expect(result.kind, StepSyncV2Kind.cooldown);
      expect(result.retryAfterSeconds, 18);
      expect(result.shouldLegacyFallback, isFalse);
      expect(result.hasJob, isFalse);
      expect(http.requests.single.headers['X-Step-Sync-Intent'], 'home-pull');
    });

    test('non-Home sync omits the Home-pull header', () async {
      final http = _FakeHttpClient([_Scripted(202, successBody('DEFERRED'))]);
      final api = BackendApiService(httpClient: http);

      await api.recordStepSyncV2(
        identityToken: 't',
        idempotencyKey: 'ordinary-key',
        payload: payload(),
      );

      expect(
        http.requests.single.headers.containsKey('X-Step-Sync-Intent'),
        isFalse,
      );
    });

    test(
      'malformed cooldown delay remains a no-work cooldown outcome',
      () async {
        final http = _FakeHttpClient([
          _Scripted(
            429,
            '{"code":"STEP_SYNC_COOLDOWN","retryAfterSeconds":"soon"}',
          ),
        ]);
        final api = BackendApiService(httpClient: http);

        final result = await api.recordStepSyncV2(
          identityToken: 't',
          idempotencyKey: 'malformed-cooldown',
          payload: payload(),
          homePull: true,
        );

        expect(result.kind, StepSyncV2Kind.cooldown);
        expect(result.retryAfterSeconds, isNull);
        expect(result.shouldLegacyFallback, isFalse);
      },
    );

    test('DEFERRED success -> deferred, does not use persisted home', () async {
      final http = _FakeHttpClient([
        _Scripted(202, successBody('DEFERRED', jobId: 'job-2', generation: 3)),
      ]);
      final api = BackendApiService(httpClient: http);
      final r = await api.recordStepSyncV2(
        identityToken: 't',
        idempotencyKey: 'k',
        payload: payload(),
      );
      expect(r.kind, StepSyncV2Kind.deferred);
      expect(r.usePersistedHome, isFalse);
      expect(r.hasJob, isTrue);
    });

    test(
      '404 -> unsupported, cached for the session, permits legacy',
      () async {
        final http = _FakeHttpClient([_Scripted(404, '{"error":"not found"}')]);
        final api = BackendApiService(httpClient: http);
        final r = await api.recordStepSyncV2(
          identityToken: 't',
          idempotencyKey: 'k',
          payload: payload(),
        );
        expect(r.kind, StepSyncV2Kind.unsupported);
        expect(r.shouldLegacyFallback, isTrue);
        expect(api.syncV2Support, EndpointSupport.unsupported);

        // A second call short-circuits without hitting the network again.
        final before = http.requests.length;
        final r2 = await api.recordStepSyncV2(
          identityToken: 't',
          idempotencyKey: 'k2',
          payload: payload(),
        );
        expect(r2.kind, StepSyncV2Kind.unsupported);
        expect(http.requests.length, before);
      },
    );

    test('503 ASYNC_DISABLED -> asyncDisabled, permits legacy', () async {
      final http = _FakeHttpClient([
        _Scripted(503, '{"error":"unavailable","code":"ASYNC_DISABLED"}'),
      ]);
      final api = BackendApiService(httpClient: http);
      final r = await api.recordStepSyncV2(
        identityToken: 't',
        idempotencyKey: 'k',
        payload: payload(),
      );
      expect(r.kind, StepSyncV2Kind.asyncDisabled);
      expect(r.shouldLegacyFallback, isTrue);
      // Endpoint exists, so it is NOT cached unsupported.
      expect(api.syncV2Support, EndpointSupport.supported);
    });

    test('500 retries once with the SAME key, then ambiguousFailure', () async {
      final http = _FakeHttpClient([
        _Scripted(500, '{"error":"boom"}'),
        _Scripted(500, '{"error":"boom"}'),
      ]);
      final api = BackendApiService(httpClient: http);
      final r = await api.recordStepSyncV2(
        identityToken: 't',
        idempotencyKey: 'same-key',
        payload: payload(),
      );
      expect(r.kind, StepSyncV2Kind.ambiguousFailure);
      expect(r.shouldLegacyFallback, isFalse);
      expect(http.requests.length, 2);
      expect(http.requests[0].headers['Idempotency-Key'], 'same-key');
      expect(http.requests[1].headers['Idempotency-Key'], 'same-key');
      // Both retries reused the identical immutable body.
      expect(
        http.requests[0].body.toString(),
        http.requests[1].body.toString(),
      );
    });

    test('500 then 202 -> success on retry', () async {
      final http = _FakeHttpClient([
        _Scripted(500, '{"error":"boom"}'),
        _Scripted(202, successBody('CURRENT', jobId: 'j', generation: 1)),
      ]);
      final api = BackendApiService(httpClient: http);
      final r = await api.recordStepSyncV2(
        identityToken: 't',
        idempotencyKey: 'k',
        payload: payload(),
      );
      expect(r.kind, StepSyncV2Kind.current);
      expect(http.requests.length, 2);
    });

    test('connection loss retries once, then ambiguousFailure', () async {
      final http = _FakeHttpClient([
        _Scripted(0, '', throwOnSend: true),
        _Scripted(0, '', throwOnSend: true),
      ]);
      final api = BackendApiService(httpClient: http);
      final r = await api.recordStepSyncV2(
        identityToken: 't',
        idempotencyKey: 'k',
        payload: payload(),
      );
      expect(r.kind, StepSyncV2Kind.ambiguousFailure);
      expect(r.shouldLegacyFallback, isFalse);
      // No 404 -> support state not downgraded.
      expect(api.syncV2Support, EndpointSupport.unknown);
    });

    test('malformed 2xx -> persistedStatusUnknown, no legacy write', () async {
      final http = _FakeHttpClient([_Scripted(202, 'not json at all')]);
      final api = BackendApiService(httpClient: http);
      final r = await api.recordStepSyncV2(
        identityToken: 't',
        idempotencyKey: 'k',
        payload: payload(),
      );
      expect(r.kind, StepSyncV2Kind.persistedStatusUnknown);
      expect(r.shouldLegacyFallback, isFalse);
      expect(r.persisted, isTrue);
      expect(r.diagnostic, isNotNull);
    });

    test('409 conflict -> persistedStatusUnknown, no legacy write', () async {
      final http = _FakeHttpClient([
        _Scripted(
          409,
          '{"error":"Idempotency key already used","code":"IDEMPOTENCY_CONFLICT"}',
        ),
      ]);
      final api = BackendApiService(httpClient: http);
      final r = await api.recordStepSyncV2(
        identityToken: 't',
        idempotencyKey: 'k',
        payload: payload(),
      );
      expect(r.kind, StepSyncV2Kind.persistedStatusUnknown);
      expect(r.shouldLegacyFallback, isFalse);
      expect(r.diagnostic, contains('409'));
    });

    test('400 INVALID_STEP_SYNC -> failed, no legacy write', () async {
      final http = _FakeHttpClient([
        _Scripted(400, '{"error":"bad","code":"INVALID_STEP_SYNC"}'),
      ]);
      final api = BackendApiService(httpClient: http);
      final r = await api.recordStepSyncV2(
        identityToken: 't',
        idempotencyKey: 'k',
        payload: payload(),
      );
      expect(r.kind, StepSyncV2Kind.failed);
      expect(r.shouldLegacyFallback, isFalse);
    });

    test('missing uploaderReconciliation -> deferred (safe default)', () async {
      final http = _FakeHttpClient([_Scripted(202, jsonencodeMinimal())]);
      final api = BackendApiService(httpClient: http);
      final r = await api.recordStepSyncV2(
        identityToken: 't',
        idempotencyKey: 'k',
        payload: payload(),
      );
      expect(r.kind, StepSyncV2Kind.deferred);
      expect(r.boxStateCurrent, isFalse);
      expect(r.resolvedRaceCount, 0);
      expect(r.hasJob, isFalse);
    });
  });

  group('fetchRaceResolutionStatus', () {
    test('SUCCEEDED -> succeeded/terminal', () async {
      final http = _FakeHttpClient([
        _Scripted(
          200,
          '{"raceResolution":{"jobId":"j","generation":1,"state":"SUCCEEDED"}}',
        ),
      ]);
      final api = BackendApiService(httpClient: http);
      final r = await api.fetchRaceResolutionStatus(
        identityToken: 't',
        jobId: 'j',
        generation: 1,
      );
      expect(r.state, RaceResolutionState.succeeded);
      expect(r.isSucceeded, isTrue);
      expect(r.isTerminal, isTrue);
      expect(http.requests.single.uri.query, contains('generation=1'));
    });

    test('SUPERSEDED -> terminal, stop polling', () async {
      final http = _FakeHttpClient([
        _Scripted(200, '{"raceResolution":{"state":"SUPERSEDED"}}'),
      ]);
      final api = BackendApiService(httpClient: http);
      final r = await api.fetchRaceResolutionStatus(
        identityToken: 't',
        jobId: 'j',
        generation: 1,
      );
      expect(r.state, RaceResolutionState.superseded);
      expect(r.isTerminal, isTrue);
    });

    test('404 -> notFound/terminal', () async {
      final http = _FakeHttpClient([_Scripted(404, '{"error":"not found"}')]);
      final api = BackendApiService(httpClient: http);
      final r = await api.fetchRaceResolutionStatus(
        identityToken: 't',
        jobId: 'j',
        generation: 1,
      );
      expect(r.state, RaceResolutionState.notFound);
      expect(r.isTerminal, isTrue);
    });

    test('malformed body -> unknown (not terminal)', () async {
      final http = _FakeHttpClient([_Scripted(200, 'garbage')]);
      final api = BackendApiService(httpClient: http);
      final r = await api.fetchRaceResolutionStatus(
        identityToken: 't',
        jobId: 'j',
        generation: 1,
      );
      expect(r.state, RaceResolutionState.unknown);
      expect(r.isTerminal, isFalse);
    });
  });

  group('simple event recap API', () {
    test(
      'GET and POST use locked wire contract and never retired status',
      () async {
        final http = _FakeHttpClient([
          _Scripted(200, '{"state":"pending","event":{"id":"event-1"}}'),
          _Scripted(200, '{"state":"none"}'),
        ]);
        final api = BackendApiService(httpClient: http);
        expect(
          (await api.fetchEventRecap(identityToken: 't'))?['state'],
          'pending',
        );
        expect(
          (await api.finalizeEventRecap(
            identityToken: 't',
            eventId: 'event-1',
            revision: 3,
            rawSteps: 1000,
          ))?['state'],
          'none',
        );
        expect(http.requests.map((r) => r.method), ['GET', 'POST']);
        expect(http.requests.map((r) => r.uri.path), [
          '/home/event-recap',
          '/home/event-recap',
        ]);
        expect(jsonDecode(http.requests.last.body.toString()), {
          'eventId': 'event-1',
          'revision': 3,
          'rawSteps': 1000,
        });
        expect(
          http.requests.every(
            (r) =>
                r.headers['X-Client-Features']
                    ?.split(',')
                    .contains('simple_event_recap_v1') ==
                true,
          ),
          isTrue,
        );
      },
    );
    test('both platform header branches advertise the interaction', () {
      for (final ios in [true, false]) {
        for (final ads in [true, false]) {
          expect(
            BackendApiService.clientFeaturesHeaderForPlatform(
              isIos: ios,
              adsSupported: ads,
              racePayoutDoubleSupported: false,
            ).split(','),
            contains('simple_event_recap_v1'),
          );
        }
      }
    });
    test(
      'old server, authorization, transient and malformed replies defer',
      () async {
        for (final script in [
          _Scripted(404, '{"code":"NOT_FOUND"}'),
          _Scripted(401, '{"code":"UNAUTHORIZED"}'),
          _Scripted(409, '{"code":"EVENT_CHANGED"}'),
          _Scripted(410, '{"code":"EVENT_EXPIRED"}'),
          _Scripted(500, '{}'),
          _Scripted(200, '{}'),
          _Scripted(200, '{"state":"unknown"}'),
          _Scripted(200, 'not json'),
        ]) {
          final http = _FakeHttpClient([script, script]);
          final api = BackendApiService(httpClient: http);
          expect(await api.fetchEventRecap(identityToken: 't'), isNull);
          expect(
            await api.finalizeEventRecap(
              identityToken: 't',
              eventId: 'event-1',
              revision: 3,
              rawSteps: 1000,
            ),
            isNull,
          );
          expect(http.requests.length, 2);
        }
      },
    );
  });

  group('fetchRaceDiscoverySummary', () {
    test('fully resolved -> commits all fields', () async {
      final http = _FakeHttpClient([
        _Scripted(
          200,
          jsonEncode({
            'publicRaceCount': 12,
            'featuredRaces': [
              {'raceId': 'a'},
            ],
            'featuredTournaments': [],
            'resolved': {
              'publicRaceCount': true,
              'featuredRaces': true,
              'featuredTournaments': true,
            },
          }),
        ),
      ]);
      final api = BackendApiService(httpClient: http);
      final r = await api.fetchRaceDiscoverySummary(identityToken: 't');
      expect(r.unsupported, isFalse);
      expect(r.publicRaceCount, 12);
      expect(r.featuredRaces, isNotNull);
      expect(r.featuredRaces!.length, 1);
      expect(r.featuredTournaments, isNotNull);
      expect(r.featuredTournaments, isEmpty);
    });

    test(
      'partial failure: unresolved bits stay null (retain last known)',
      () async {
        final http = _FakeHttpClient([
          _Scripted(
            200,
            jsonEncode({
              'publicRaceCount': 0,
              'featuredRaces': [
                {'raceId': 'a'},
              ],
              'featuredTournaments': [],
              'resolved': {
                'publicRaceCount': false, // failed branch
                'featuredRaces': true,
                'featuredTournaments': true,
              },
            }),
          ),
        ]);
        final api = BackendApiService(httpClient: http);
        final r = await api.fetchRaceDiscoverySummary(identityToken: 't');
        expect(r.publicRaceCount, isNull); // not committed -> keep last known
        expect(r.featuredRaces!.length, 1);
      },
    );

    test('404 -> unsupported, cached, legacy signaled', () async {
      final http = _FakeHttpClient([_Scripted(404, '{"error":"nope"}')]);
      final api = BackendApiService(httpClient: http);
      final r = await api.fetchRaceDiscoverySummary(identityToken: 't');
      expect(r.unsupported, isTrue);
      expect(api.discoverySummarySupport, EndpointSupport.unsupported);

      final before = http.requests.length;
      final r2 = await api.fetchRaceDiscoverySummary(identityToken: 't');
      expect(r2.unsupported, isTrue);
      expect(http.requests.length, before); // short-circuited
    });

    test(
      'malformed body -> empty (retain last known, not unsupported)',
      () async {
        final http = _FakeHttpClient([_Scripted(200, 'not-json')]);
        final api = BackendApiService(httpClient: http);
        final r = await api.fetchRaceDiscoverySummary(identityToken: 't');
        expect(r.unsupported, isFalse);
        expect(r.publicRaceCount, isNull);
        expect(r.featuredRaces, isNull);
      },
    );

    test('500 -> empty (retain last known), not downgraded', () async {
      final http = _FakeHttpClient([_Scripted(500, '{"error":"boom"}')]);
      final api = BackendApiService(httpClient: http);
      final r = await api.fetchRaceDiscoverySummary(identityToken: 't');
      expect(r.unsupported, isFalse);
      expect(api.discoverySummarySupport, EndpointSupport.supported);
    });
  });

  group('capability reset', () {
    test('resetSessionCapabilities clears cached unsupported', () async {
      final http = _FakeHttpClient([_Scripted(404, '{}')]);
      final api = BackendApiService(httpClient: http);
      await api.fetchRaceDiscoverySummary(identityToken: 't');
      expect(api.discoverySummarySupport, EndpointSupport.unsupported);
      api.resetSessionCapabilities();
      expect(api.discoverySummarySupport, EndpointSupport.unknown);
    });

    test('onAuthenticatedUser clears only on user change', () async {
      final http = _FakeHttpClient([_Scripted(404, '{}')]);
      final api = BackendApiService(httpClient: http);
      api.onAuthenticatedUser('user-a');
      await api.fetchRaceDiscoverySummary(identityToken: 't');
      expect(api.discoverySummarySupport, EndpointSupport.unsupported);
      // Same user again -> no clear.
      api.onAuthenticatedUser('user-a');
      expect(api.discoverySummarySupport, EndpointSupport.unsupported);
      // Different user -> clears.
      api.onAuthenticatedUser('user-b');
      expect(api.discoverySummarySupport, EndpointSupport.unknown);
    });
  });
}

String jsonencodeMinimal() => jsonEncode({
  'record': {
    'id': 'r',
    'userId': 'u',
    'date': '2026-07-17T00:00:00.000Z',
    'steps': 1,
    'stepGoal': 0,
  },
  'sampleCount': 0,
});
