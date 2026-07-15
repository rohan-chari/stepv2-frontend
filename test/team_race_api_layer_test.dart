import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/services/backend_api_service.dart';

/// Captures requests sent through BackendApiService so tests can assert on
/// method, path, and JSON body (team-race wire contract, TR-101/201/203/105).
class _CapturedRequest {
  final String method;
  final Uri uri;
  final StringBuffer body = StringBuffer();
  _CapturedRequest(this.method, this.uri);

  Map<String, dynamic> get jsonBody =>
      jsonDecode(body.toString()) as Map<String, dynamic>;
}

class _FakeHttpHeaders implements HttpHeaders {
  final Map<String, String> values = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name] = value.toString();
  }

  @override
  ContentType? contentType;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  final int _statusCode;
  final String _body;
  _FakeHttpClientResponse(this._statusCode, this._body);

  @override
  int get statusCode => _statusCode;

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

class _FakeHttpClientRequest implements HttpClientRequest {
  final _CapturedRequest captured;
  final _FakeHttpClientResponse response;
  _FakeHttpClientRequest(this.captured, this.response);

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  void write(Object? object) {
    captured.body.write(object);
  }

  @override
  Future<HttpClientResponse> close() async => response;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakeHttpClient implements HttpClient {
  final List<_CapturedRequest> requests = [];
  int statusCode;
  String responseBody;
  _FakeHttpClient({this.statusCode = 200, this.responseBody = '{}'});

  @override
  Duration? connectionTimeout;

  _CapturedRequest get lastRequest => requests.last;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final captured = _CapturedRequest(method, url);
    requests.add(captured);
    return _FakeHttpClientRequest(
      captured,
      _FakeHttpClientResponse(statusCode, responseBody),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // The service resolves the device timezone for the X-Timezone header;
    // there is no platform plugin in tests, so answer the channel directly.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (call) async => 'America/New_York',
        );
  });

  group('TR-101/103/104: createRace team fields', () {
    test('team race create sends isTeamRace, teamSize, names, creator side',
        () async {
      final http = _FakeHttpClient();
      final api = BackendApiService(httpClient: http);

      await api.createTeamRace(
        identityToken: 'token',
        name: 'Capy Cup',
        teamSize: 2,
        teamAName: 'Swift Capys',
        teamBName: 'Turbo Beavers',
        creatorTeam: 'TEAM_B',
      );

      final body = http.lastRequest.jsonBody;
      expect(http.lastRequest.method, 'POST');
      expect(http.lastRequest.uri.path, endsWith('/races'));
      expect(body['isTeamRace'], isTrue);
      expect(body['teamSize'], 2);
      expect(body['teamAName'], 'Swift Capys');
      expect(body['teamBName'], 'Turbo Beavers');
      // Contract §3: the creator's side rides the `team` key.
      expect(body['team'], 'TEAM_B');
      // TR-101: field cap follows 2 x teamSize.
      expect(body['maxParticipants'], 4);
      // TR-102: payoutPreset stored as WINNER_TAKES_ALL for display compat.
      expect(body['payoutPreset'], 'WINNER_TAKES_ALL');
    });

    test('individual race create sends no team fields (wire unchanged)',
        () async {
      final http = _FakeHttpClient();
      final api = BackendApiService(httpClient: http);

      await api.createRace(identityToken: 'token', name: 'Solo Sprint');

      final body = http.lastRequest.jsonBody;
      expect(body.containsKey('isTeamRace'), isFalse);
      expect(body.containsKey('teamSize'), isFalse);
      expect(body.containsKey('teamAName'), isFalse);
      expect(body.containsKey('teamBName'), isFalse);
      expect(body.containsKey('team'), isFalse);
    });
  });

  group('TR-103/801: team-name suggestions (contract §3b)', () {
    test('fetchTeamNameSuggestion GETs the suggest route', () async {
      final http = _FakeHttpClient(
        responseBody:
            '{"teamAName":"Swift Capys","teamBName":"Turbo Beavers"}',
      );
      final api = BackendApiService(httpClient: http);

      final pair = await api.fetchTeamNameSuggestion(identityToken: 'token');

      expect(http.lastRequest.method, 'GET');
      expect(
        http.lastRequest.uri.path,
        endsWith('/races/team-names/suggest'),
      );
      expect(pair, ('Swift Capys', 'Turbo Beavers'));
    });

    test('returns null when the backend omits either name', () async {
      final http = _FakeHttpClient(responseBody: '{"teamAName":"Only One"}');
      final api = BackendApiService(httpClient: http);

      expect(
        await api.fetchTeamNameSuggestion(identityToken: 'token'),
        isNull,
      );
    });

    test('returns null on a blank name rather than an empty plaque', () async {
      final http = _FakeHttpClient(
        responseBody: '{"teamAName":"  ","teamBName":"Turbo Beavers"}',
      );
      final api = BackendApiService(httpClient: http);

      expect(
        await api.fetchTeamNameSuggestion(identityToken: 'token'),
        isNull,
      );
    });

    test('returns null on an older backend (404) instead of throwing',
        () async {
      final http = _FakeHttpClient(
        statusCode: 404,
        responseBody: '{"error":"Not found"}',
      );
      final api = BackendApiService(httpClient: http);

      // Never throws: the create screen must fall back to the local pool, not
      // break race creation.
      expect(
        await api.fetchTeamNameSuggestion(identityToken: 'token'),
        isNull,
      );
    });
  });

  group('TR-205: leaving a PENDING team lobby', () {
    test('leaveRace POSTs to the leave endpoint', () async {
      final http = _FakeHttpClient();
      final api = BackendApiService(httpClient: http);

      await api.leaveRace(identityToken: 'token', raceId: 'race-1');

      expect(http.lastRequest.method, 'POST');
      expect(http.lastRequest.uri.path, endsWith('/races/race-1/leave'));
    });
  });

  group('TR-601: mid-race forfeit', () {
    test('forfeitRace POSTs to the forfeit endpoint', () async {
      final http = _FakeHttpClient();
      final api = BackendApiService(httpClient: http);

      await api.forfeitRace(identityToken: 'token', raceId: 'race-1');

      expect(http.lastRequest.method, 'POST');
      expect(http.lastRequest.uri.path, endsWith('/races/race-1/forfeit'));
    });
  });

  group('TR-201: join channels carry the side', () {
    test('joinPublicRace sends team when picking a side', () async {
      final http = _FakeHttpClient();
      final api = BackendApiService(httpClient: http);

      await api.joinPublicRaceOnTeam(
        identityToken: 'token',
        raceId: 'race-1',
        team: 'TEAM_A',
      );

      expect(http.lastRequest.uri.path, endsWith('/races/race-1/join'));
      expect(http.lastRequest.jsonBody['team'], 'TEAM_A');
    });

    test('joinPublicRace omits team for individual races', () async {
      final http = _FakeHttpClient();
      final api = BackendApiService(httpClient: http);

      await api.joinPublicRace(identityToken: 'token', raceId: 'race-1');

      expect(http.lastRequest.jsonBody.containsKey('team'), isFalse);
    });

    test('respondToRaceInvite sends team on accept', () async {
      final http = _FakeHttpClient();
      final api = BackendApiService(httpClient: http);

      await api.acceptTeamRaceInvite(
        identityToken: 'token',
        raceId: 'race-1',
        team: 'TEAM_B',
      );

      expect(http.lastRequest.jsonBody['accept'], isTrue);
      expect(http.lastRequest.jsonBody['team'], 'TEAM_B');
    });

    test('joinRaceByShareToken sends team', () async {
      final http = _FakeHttpClient();
      final api = BackendApiService(httpClient: http);

      await api.joinRaceByShareTokenOnTeam(
        identityToken: 'token',
        token: 'share-token',
        team: 'TEAM_A',
      );

      expect(
        http.lastRequest.uri.path,
        endsWith('/races/share/share-token/join'),
      );
      expect(http.lastRequest.jsonBody['team'], 'TEAM_A');
    });
  });

  group('TR-203: side switching while PENDING', () {
    test('setRaceTeam PUTs the new side to the race team endpoint', () async {
      final http = _FakeHttpClient();
      final api = BackendApiService(httpClient: http);

      await api.setRaceTeam(
        identityToken: 'token',
        raceId: 'race-1',
        team: 'TEAM_B',
      );

      expect(http.lastRequest.method, 'PUT');
      expect(http.lastRequest.uri.path, endsWith('/races/race-1/team'));
      expect(http.lastRequest.jsonBody['team'], 'TEAM_B');
    });
  });

  group('TR-105: PENDING edits', () {
    test('updateRace can patch team names and team size', () async {
      final http = _FakeHttpClient();
      final api = BackendApiService(httpClient: http);

      await api.updateRace(
        identityToken: 'token',
        raceId: 'race-1',
        teamAName: 'Mossy Rockets',
        teamBName: 'Puddle Jumpers',
        teamSize: 3,
      );

      expect(http.lastRequest.method, 'PATCH');
      final body = http.lastRequest.jsonBody;
      expect(body['teamAName'], 'Mossy Rockets');
      expect(body['teamBName'], 'Puddle Jumpers');
      expect(body['teamSize'], 3);
    });

    test('updateRace omits team fields when not editing them', () async {
      final http = _FakeHttpClient();
      final api = BackendApiService(httpClient: http);

      await api.updateRace(
        identityToken: 'token',
        raceId: 'race-1',
        name: 'Renamed',
      );

      final body = http.lastRequest.jsonBody;
      expect(body.containsKey('teamAName'), isFalse);
      expect(body.containsKey('teamBName'), isFalse);
      expect(body.containsKey('teamSize'), isFalse);
    });
  });

  group('error code surfacing', () {
    test('ApiException carries the backend error code when present', () async {
      final http = _FakeHttpClient(
        statusCode: 409,
        responseBody: '{"error":"That side is full","code":"TEAM_FULL"}',
      );
      final api = BackendApiService(httpClient: http);

      try {
        await api.joinPublicRaceOnTeam(
          identityToken: 'token',
          raceId: 'race-1',
          team: 'TEAM_A',
        );
        fail('expected ApiException');
      } on ApiException catch (e) {
        expect(e.statusCode, 409);
        expect(e.code, 'TEAM_FULL');
        expect(e.message, 'That side is full');
      }
    });

    test('ApiException code is null when the backend omits it', () async {
      final http = _FakeHttpClient(
        statusCode: 400,
        responseBody: '{"error":"Nope"}',
      );
      final api = BackendApiService(httpClient: http);

      try {
        await api.joinPublicRace(identityToken: 'token', raceId: 'race-1');
        fail('expected ApiException');
      } on ApiException catch (e) {
        expect(e.code, isNull);
      }
    });
  });
}
