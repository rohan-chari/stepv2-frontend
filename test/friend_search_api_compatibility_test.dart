import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _Scripted {
  const _Scripted(this.status, this.body);
  final int status;
  final String body;
}

class _CapturedRequest {
  _CapturedRequest(this.method, this.uri);
  final String method;
  final Uri uri;
  final StringBuffer body = StringBuffer();
}

class _FakeHeaders implements HttpHeaders {
  @override
  ContentType? contentType;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse(this._script);
  final _Scripted _script;

  @override
  int get statusCode => _script.status;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.fromIterable([utf8.encode(_script.body)]).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this.captured, this.script);
  final _CapturedRequest captured;
  final _Scripted script;

  @override
  final HttpHeaders headers = _FakeHeaders();

  @override
  void write(Object? object) => captured.body.write(object);

  @override
  Future<HttpClientResponse> close() async => _FakeResponse(script);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this.scripts);
  final List<_Scripted> scripts;
  final List<_CapturedRequest> requests = [];
  int _index = 0;

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final captured = _CapturedRequest(method, url);
    requests.add(captured);
    final script =
        scripts[_index < scripts.length ? _index : scripts.length - 1];
    _index++;
    return _FakeRequest(captured, script);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _body(_CapturedRequest request) =>
    jsonDecode(request.body.toString()) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (_) async => 'America/New_York',
        );
  });

  test(
    'capable friend search uses POST body and reads rows defensively',
    () async {
      final http = _FakeHttpClient([
        const _Scripted(
          200,
          '{"users":[{"id":"u1","displayName":"RaceName",'
          '"discoverableName":"Nathan Chari"},"malformed"]}',
        ),
      ]);
      final api = BackendApiService(httpClient: http);

      final rows = await api.searchUsers(
        identityToken: 'token',
        query: 'Nathan Chari',
      );

      expect(http.requests, hasLength(1));
      expect(http.requests.single.method, 'POST');
      expect(http.requests.single.uri.path, endsWith('/friends/search'));
      expect(http.requests.single.uri.query, isEmpty);
      expect(_body(http.requests.single), {'q': 'Nathan Chari'});
      expect(rows, hasLength(1));
      expect(rows.single['discoverableName'], 'Nathan Chari');
    },
  );

  test(
    'POST 404 does not replay the name and the next query uses GET',
    () async {
      final http = _FakeHttpClient([
        const _Scripted(404, '{"error":"not found"}'),
        const _Scripted(
          200,
          '{"users":[{"id":"u2","displayName":"SecondHandle"}]}',
        ),
      ]);
      final api = BackendApiService(httpClient: http);

      await expectLater(
        api.searchUsers(identityToken: 'token', query: 'Private Real Name'),
        throwsA(isA<LegacyFriendSearchRequired>()),
      );
      expect(http.requests, hasLength(1));
      expect(http.requests.single.method, 'POST');
      expect(http.requests.single.uri.query, isEmpty);

      final rows = await api.searchUsers(
        identityToken: 'token',
        query: 'SecondHandle',
      );
      expect(http.requests, hasLength(2));
      expect(http.requests.last.method, 'GET');
      expect(http.requests.last.uri.queryParameters['q'], 'SecondHandle');
      expect(rows.single['displayName'], 'SecondHandle');
    },
  );

  for (final status in [400, 401, 429, 500]) {
    test('POST $status never downgrades to URL search', () async {
      final http = _FakeHttpClient([
        _Scripted(status, '{"error":"no","code":"E$status"}'),
        const _Scripted(200, '{"users":[]}'),
      ]);
      final api = BackendApiService(httpClient: http);

      await expectLater(
        api.searchUsers(identityToken: 'token', query: 'First Name'),
        throwsA(
          isA<ApiException>().having(
            (error) => error.statusCode,
            'statusCode',
            status,
          ),
        ),
      );
      await api.searchUsers(identityToken: 'token', query: 'Second Name');

      expect(http.requests, hasLength(2));
      expect(
        http.requests.every((request) => request.method == 'POST'),
        isTrue,
      );
      expect(
        http.requests.every((request) => request.uri.query.isEmpty),
        isTrue,
      );
    });
  }

  test('identity writes use the locked additive request fields', () async {
    final http = _FakeHttpClient([
      const _Scripted(200, '{"user":{},"suggestedDisplayName":"NathanC"}'),
      const _Scripted(200, '{"user":{}}'),
    ]);
    final api = BackendApiService(httpClient: http);

    await api.updateDiscoverableName(
      identityToken: 'token',
      firstName: 'Nathan',
      lastName: null,
    );
    await api.updateDisplayName(
      identityToken: 'token',
      displayName: 'NathanC',
      completeDiscoverableNameSetup: true,
    );

    expect(http.requests[0].method, 'PUT');
    expect(http.requests[0].uri.path, endsWith('/auth/me/discoverable-name'));
    expect(_body(http.requests[0]), {'firstName': 'Nathan', 'lastName': null});
    expect(http.requests[1].method, 'PUT');
    expect(http.requests[1].uri.path, endsWith('/auth/me/display-name'));
    expect(_body(http.requests[1]), {
      'displayName': 'NathanC',
      'completeDiscoverableNameSetup': true,
    });
  });
}
