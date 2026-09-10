import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _RealHttp extends HttpOverrides {}

class _LoopbackClient extends Fake implements HttpClient {
  _LoopbackClient(this.client, this.port);
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
  var status = 201;
  Map<String, Object> body = {};
  final events = <Object?>[];
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'test',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    );
    events.clear();
    status = 201;
    body = {
      'participant': {'id': 'p', 'raceId': 'race', 'userId': 'user'},
      'raceId': 'race',
    };
    for (final name in ['flutter_timezone', 'com.steptracker/app_info']) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(name),
        (_) async => name == 'flutter_timezone'
            ? 'UTC'
            : {'version': '1', 'buildNumber': '1'},
      );
    }
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.steptracker/meta_app_events'),
      (call) async {
        events.add(call.arguments);
        return true;
      },
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(body));
      await request.response.close();
    });
    client = HttpOverrides.runWithHttpOverrides(
      () => HttpClient(),
      _RealHttp(),
    );
    api = BackendApiService(httpClient: _LoopbackClient(client, server.port));
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    for (final name in [
      'flutter_timezone',
      'com.steptracker/app_info',
      'com.steptracker/meta_app_events',
    ]) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(name),
        null,
      );
    }
    client.close(force: true);
    await server.close(force: true);
  });
  test(
    'only confirmed explicit joins emit a parameter-free conversion',
    () async {
      await api.joinPublicRace(identityToken: 'token', raceId: 'race');
      await api.joinPublicRaceOnTeam(
        identityToken: 'token',
        raceId: 'race',
        team: 'A',
      );
      await api.joinRaceByShareToken(identityToken: 'token', token: 'share');
      await api.joinRaceByShareTokenOnTeam(
        identityToken: 'token',
        token: 'share',
        team: 'B',
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, List.filled(4, {'event': 'raceJoined'}));
      status = 400;
      body = {'code': 'ALREADY_RESPONDED', 'message': 'Already joined'};
      await expectLater(
        api.joinPublicRace(identityToken: 'token', raceId: 'race'),
        throwsA(isA<ApiException>()),
      );
      expect(events, hasLength(4));
    },
  );
  test(
    'ambiguous legacy success, malformed payload and Android never emit',
    () async {
      status = 200;
      await api.joinPublicRace(identityToken: 'token', raceId: 'race');
      status = 201;
      body = {};
      await api.joinPublicRace(identityToken: 'token', raceId: 'race');
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      body = {
        'participant': {'id': 'p'},
      };
      await api.joinPublicRace(identityToken: 'token', raceId: 'race');
      expect(events, isEmpty);
    },
  );
}
