import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// Race timeline options — the WIRE half of spec §9 test 17.
//
// The screen-level test proves the create screen passes `scheduledEndAt` only
// for a CUSTOM window. This one proves the other half of the compat promise:
// when it is null the key is **absent from the JSON body entirely**, so a
// request from this build against an OLDER backend is byte-identical to
// today's. A key present with a null value would not be — `scheduledEndAt:
// null` is a meaningful, destructive instruction on PATCH.

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.statusCode, Map<String, dynamic> body)
    : _bytes = utf8.encode(jsonEncode(body));

  @override
  final int statusCode;
  final List<int> _bytes;

  @override
  final HttpHeaders headers = _ResponseHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(_bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ResponseHeaders extends Fake implements HttpHeaders {
  @override
  String? value(String name) => null;
}

class _Headers extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  set contentType(ContentType? value) {}
}

class _Request extends Fake implements HttpClientRequest {
  _Request(this.response);

  final HttpClientResponse response;
  final StringBuffer body = StringBuffer();

  @override
  final HttpHeaders headers = _Headers();

  @override
  void write(Object? object) => body.write(object);

  @override
  Future<HttpClientResponse> close() async => response;
}

class _Http extends Fake implements HttpClient {
  final List<_Request> requests = [];

  @override
  set connectionTimeout(Duration? value) {}

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final request = _Request(
      _Response(200, const {
        'race': {'id': 'race-1'},
      }),
    );
    requests.add(request);
    return request;
  }
}

Map<String, dynamic> _body(_Http http) =>
    jsonDecode(http.requests.single.body.toString()) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (_) async => 'America/New_York',
        );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.3.7',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  test('POST /races omits scheduledEndAt entirely when it is null', () async {
    final http = _Http();
    await BackendApiService(httpClient: http).createRace(
      identityToken: 'token',
      name: 'Plain Week',
      maxDurationDays: 7,
    );

    final body = _body(http);
    expect(body.containsKey('scheduledEndAt'), isFalse);
    expect(body.containsKey('scheduledStartAt'), isFalse);
    expect(body['maxDurationDays'], 7);
  });

  test('POST /races sends a custom end as an ISO-8601 UTC instant', () async {
    final http = _Http();
    final end = DateTime.utc(2026, 8, 22, 21);
    await BackendApiService(httpClient: http).createRace(
      identityToken: 'token',
      name: 'Weekend Push',
      maxDurationDays: 5,
      scheduledEndAt: end,
    );

    expect(_body(http)['scheduledEndAt'], '2026-08-22T21:00:00.000Z');
  });

  test('a team race carries the same field', () async {
    final http = _Http();
    final end = DateTime.utc(2026, 8, 22, 21);
    await BackendApiService(httpClient: http).createTeamRace(
      identityToken: 'token',
      name: 'Squad Push',
      teamSize: 2,
      scheduledEndAt: end,
    );

    expect(_body(http)['scheduledEndAt'], '2026-08-22T21:00:00.000Z');
  });

  test('PATCH sends an explicit null only when clearing the window', () async {
    final http = _Http();
    await BackendApiService(httpClient: http).updateRace(
      identityToken: 'token',
      raceId: 'race-1',
      maxDurationDays: 7,
      clearScheduledEndAt: true,
    );

    final body = _body(http);
    expect(body.containsKey('scheduledEndAt'), isTrue);
    expect(body['scheduledEndAt'], isNull);
    expect(body['maxDurationDays'], 7);
    // `scheduledStartAt: null` is answered with 400
    // SCHEDULED_START_NOT_CLEARABLE — the client must never send it.
    expect(body.containsKey('scheduledStartAt'), isFalse);
  });

  test('PATCH moving the window sends both instants and no null', () async {
    final http = _Http();
    final start = DateTime.utc(2026, 8, 18, 12);
    final end = DateTime.utc(2026, 8, 22, 21);
    await BackendApiService(httpClient: http).updateRace(
      identityToken: 'token',
      raceId: 'race-1',
      scheduledStartAt: start,
      scheduledEndAt: end,
    );

    final body = _body(http);
    expect(body['scheduledStartAt'], '2026-08-18T12:00:00.000Z');
    expect(body['scheduledEndAt'], '2026-08-22T21:00:00.000Z');
  });

  test('a PATCH that only renames carries no timeline keys at all', () async {
    final http = _Http();
    await BackendApiService(httpClient: http).updateRace(
      identityToken: 'token',
      raceId: 'race-1',
      name: 'Renamed',
    );

    final body = _body(http);
    expect(body.keys.toList(), ['name']);
  });
}
