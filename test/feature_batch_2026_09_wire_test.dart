import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _CapturedRequest {
  _CapturedRequest(this.method, this.uri);

  final String method;
  final Uri uri;
  final StringBuffer body = StringBuffer();
  final Map<String, String> headers = <String, String>{};
}

class _Headers implements HttpHeaders {
  _Headers(this.request);

  final _CapturedRequest request;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    request.headers[name.toLowerCase()] = value.toString();
  }

  @override
  ContentType? contentType;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.body);

  final String body;

  @override
  int get statusCode => 200;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(utf8.encode(body)).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Request implements HttpClientRequest {
  _Request(this.capture, this.responseBody);

  final _CapturedRequest capture;
  final String responseBody;

  @override
  late final HttpHeaders headers = _Headers(capture);

  @override
  void write(Object? object) => capture.body.write(object);

  @override
  Future<HttpClientResponse> close() async => _Response(responseBody);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Client implements HttpClient {
  final List<_CapturedRequest> requests = <_CapturedRequest>[];

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final capture = _CapturedRequest(method, url);
    requests.add(capture);
    return _Request(capture, '{}');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Map<String, dynamic> _body(_CapturedRequest request) =>
    jsonDecode(request.body.toString()) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (call) async => 'America/New_York',
        );
  });

  test(
    'permanent recurring and team-chat client capabilities are advertised',
    () {
      final features = BackendApiService.clientFeaturesHeader.split(',');
      expect(features, contains('recurring_races_v1'));
      expect(features, contains('team_chat_v1'));
    },
  );

  test(
    'new race retention and tutorial commands match the locked contract',
    () async {
      final client = _Client();
      final api = BackendApiService(httpClient: client);

      await api.createRecurringRace(
        identityToken: 'token',
        name: 'Morning crew',
        idempotencyKey: '00000000-0000-4000-8000-000000000001',
      );
      await api.rematchRace(
        identityToken: 'token',
        raceId: 'race-1',
        idempotencyKey: '00000000-0000-4000-8000-000000000002',
      );
      await api.completeShopTutorial(identityToken: 'token');
      await api.updateRaceSeriesSubscription(
        identityToken: 'token',
        seriesId: 'series-1',
        active: false,
      );
      await api.updateRaceSeries(
        identityToken: 'token',
        seriesId: 'series-1',
        enabled: false,
      );

      expect(client.requests[0].uri.path, '/races');
      expect(_body(client.requests[0])['recurringSeries'], isTrue);
      expect(
        client.requests[0].headers['idempotency-key'],
        '00000000-0000-4000-8000-000000000001',
      );
      expect(client.requests[1].uri.path, '/races/race-1/rematch');
      expect(
        client.requests[1].headers['idempotency-key'],
        '00000000-0000-4000-8000-000000000002',
      );
      expect(client.requests[2].uri.path, '/shop/tutorial/complete');
      expect(client.requests[3].uri.path, '/race-series/series-1/subscription');
      expect(_body(client.requests[3]), <String, dynamic>{'active': false});
      expect(client.requests[4].uri.path, '/race-series/series-1');
      expect(_body(client.requests[4]), <String, dynamic>{'enabled': false});
    },
  );

  test('invite subscriptions and exact chat audience are additive', () async {
    final client = _Client();
    final api = BackendApiService(httpClient: client);

    await api.respondToRecurringRaceInvite(
      identityToken: 'token',
      raceId: 'race-1',
      accept: true,
      subscribeToSeries: true,
    );
    await api.fetchRaceMessagesForAudience(
      identityToken: 'token',
      raceId: 'race-1',
      audience: 'TEAM',
    );
    await api.sendRaceMessageToAudience(
      identityToken: 'token',
      raceId: 'race-1',
      body: 'Only us',
      audience: 'TEAM',
    );

    expect(_body(client.requests[0])['subscribeToSeries'], isTrue);
    expect(client.requests[1].uri.queryParameters['audience'], 'TEAM');
    expect(_body(client.requests[2]), <String, dynamic>{
      'body': 'Only us',
      'audience': 'TEAM',
    });
  });
}
