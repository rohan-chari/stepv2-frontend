import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _RealHttp extends HttpOverrides {}

class _LocalClient extends Fake implements HttpClient {
  _LocalClient(this.client, this.port);
  final HttpClient client;
  final int port;
  @override
  set connectionTimeout(Duration? value) => client.connectionTimeout = value;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) => client.openUrl(
    method,
    url.replace(scheme: 'http', host: '127.0.0.1', port: port),
  );
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  late HttpClient client;
  late BackendApiService api;
  late List<Map<String, dynamic>> requests;
  var status = 200;
  var response = '{}';
  setUp(() async {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter_timezone'),
      (_) async => 'America/New_York',
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.steptracker/app_info'),
      (_) async => false,
    );
    requests = [];
    status = 200;
    response = '{}';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add({
        'method': request.method,
        'path': request.uri.path,
        'body': jsonDecode(await utf8.decoder.bind(request).join()),
        'auth': request.headers.value('Authorization'),
        'features': request.headers.value('X-Client-Features'),
        'platform': request.headers.value('X-Platform'),
      });
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType.json;
      request.response.write(response);
      await request.response.close();
    });
    client = HttpOverrides.runWithHttpOverrides(
      () => HttpClient(),
      _RealHttp(),
    );
    api = BackendApiService(httpClient: _LocalClient(client, server.port));
  });
  tearDown(() async {
    client.close(force: true);
    await server.close(force: true);
    debugDefaultTargetPlatformOverride = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter_timezone'),
      null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.steptracker/app_info'),
      null,
    );
  });
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    test(
      '$platform current Join POST preserves request UUID and old assign stays UPCOMING',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        const id = '550e8400-e29b-41d4-a716-446655440000';
        response = '{"joined":true,"raceId":"owned"}';
        expect(
          await api.joinCurrentSeededChallenge(
            identityToken: 'token',
            seedKind: 'DAILY_10K',
            requestId: id,
          ),
          {'joined': true, 'raceId': 'owned'},
        );
        await api.joinCurrentSeededChallenge(
          identityToken: 'token',
          seedKind: 'WEEKLY_50K',
          requestId: id,
        );
        status = 202;
        response = '{"elected":true,"raceId":null}';
        expect(
          await api.assignSeededRaceBucket(
            identityToken: 'token',
            seedKind: 'DAILY_10K',
          ),
          {'elected': true, 'raceId': null},
        );
        expect(requests.map((r) => r['path']), [
          '/races/seeded/DAILY_10K/join-current',
          '/races/seeded/WEEKLY_50K/join-current',
          '/races/seeded/DAILY_10K/assign',
        ]);
        expect(requests.map((r) => r['body']), [
          {'requestId': id},
          {'requestId': id},
          {'window': 'UPCOMING'},
        ]);
        expect(
          requests.every(
            (r) => r['method'] == 'POST' && r['auth'] == 'Bearer token',
          ),
          isTrue,
        );
        expect(requests.first['features'], contains('seeded_race_buckets'));
        expect(
          requests.first['platform'],
          platform == TargetPlatform.iOS ? 'ios' : 'android',
        );
      },
    );
  }
  test('busy response preserves typed error and retry metadata', () async {
    status = 503;
    response =
        '{"error":"Try again","code":"CHALLENGE_JOIN_BUSY","retryable":true}';
    await expectLater(
      api.joinCurrentSeededChallenge(
        identityToken: 'token',
        seedKind: 'DAILY_10K',
        requestId: '550e8400-e29b-41d4-a716-446655440000',
      ),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'CHALLENGE_JOIN_BUSY')
            .having((e) => e.statusCode, 'status', 503)
            .having((e) => e.details?['retryable'], 'retryable', true),
      ),
    );
  });
  test(
    'malformed success body becomes reconciliation input without an unchecked cast',
    () async {
      for (final body in ['null', '[]', '{broken', '']) {
        response = body;
        expect(
          await api.joinCurrentSeededChallenge(
            identityToken: 'token',
            seedKind: 'DAILY_10K',
            requestId: '550e8400-e29b-41d4-a716-446655440000',
          ),
          isEmpty,
        );
      }
    },
  );
}
