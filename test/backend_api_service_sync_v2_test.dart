import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/models/race_discovery_summary.dart';
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
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
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
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
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
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

Map<String, dynamic> _bodyOf(_CapturedRequest r) =>
    jsonDecode(r.body.toString()) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (call) async => 'America/New_York',
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
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}'
                r'-[0-9a-f]{12}$')
            .hasMatch(key),
        isTrue,
      );
    });
  });

  group('recordStepSyncV2', () {
    String successBody(String state, {String? jobId, int? generation}) =>
        jsonEncode({
          'record': {'id': 'r', 'userId': 'u', 'date': '2026-07-17T00:00:00.000Z', 'steps': 12345, 'stepGoal': 5000},
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

    test('404 -> unsupported, cached for the session, permits legacy', () async {
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
    });

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
      expect(http.requests[0].body.toString(),
          http.requests[1].body.toString());
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
        _Scripted(409,
            '{"error":"Idempotency key already used","code":"IDEMPOTENCY_CONFLICT"}'),
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
      final http = _FakeHttpClient([
        _Scripted(202, jsonencodeMinimal()),
      ]);
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
        _Scripted(200,
            '{"raceResolution":{"jobId":"j","generation":1,"state":"SUCCEEDED"}}'),
      ]);
      final api = BackendApiService(httpClient: http);
      final r = await api.fetchRaceResolutionStatus(
          identityToken: 't', jobId: 'j', generation: 1);
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
          identityToken: 't', jobId: 'j', generation: 1);
      expect(r.state, RaceResolutionState.superseded);
      expect(r.isTerminal, isTrue);
    });

    test('404 -> notFound/terminal', () async {
      final http = _FakeHttpClient([_Scripted(404, '{"error":"not found"}')]);
      final api = BackendApiService(httpClient: http);
      final r = await api.fetchRaceResolutionStatus(
          identityToken: 't', jobId: 'j', generation: 1);
      expect(r.state, RaceResolutionState.notFound);
      expect(r.isTerminal, isTrue);
    });

    test('malformed body -> unknown (not terminal)', () async {
      final http = _FakeHttpClient([_Scripted(200, 'garbage')]);
      final api = BackendApiService(httpClient: http);
      final r = await api.fetchRaceResolutionStatus(
          identityToken: 't', jobId: 'j', generation: 1);
      expect(r.state, RaceResolutionState.unknown);
      expect(r.isTerminal, isFalse);
    });
  });

  group('fetchRaceDiscoverySummary', () {
    test('fully resolved -> commits all fields', () async {
      final http = _FakeHttpClient([
        _Scripted(200, jsonEncode({
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
        })),
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

    test('partial failure: unresolved bits stay null (retain last known)',
        () async {
      final http = _FakeHttpClient([
        _Scripted(200, jsonEncode({
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
        })),
      ]);
      final api = BackendApiService(httpClient: http);
      final r = await api.fetchRaceDiscoverySummary(identityToken: 't');
      expect(r.publicRaceCount, isNull); // not committed -> keep last known
      expect(r.featuredRaces!.length, 1);
    });

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

    test('malformed body -> empty (retain last known, not unsupported)',
        () async {
      final http = _FakeHttpClient([_Scripted(200, 'not-json')]);
      final api = BackendApiService(httpClient: http);
      final r = await api.fetchRaceDiscoverySummary(identityToken: 't');
      expect(r.unsupported, isFalse);
      expect(r.publicRaceCount, isNull);
      expect(r.featuredRaces, isNull);
    });

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
      'record': {'id': 'r', 'userId': 'u', 'date': '2026-07-17T00:00:00.000Z', 'steps': 1, 'stepGoal': 0},
      'sampleCount': 0,
    });
