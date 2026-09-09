import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show AppLifecycleState;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _RealHttpOverrides extends HttpOverrides {}

// Use the real HTTP transport and response decoding against a loopback server;
// only redirect the destination so no configured backend is contacted.
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
  const timezoneChannel = MethodChannel('flutter_timezone');
  const appInfoChannel = MethodChannel('com.steptracker/app_info');
  final messenger = binding.defaultBinaryMessenger;
  late HttpServer server;
  late HttpClient client;
  late BackendApiService api;
  late List<Map<String, String?>> requests;
  late String timezone;
  late bool timezoneUnavailable;
  late int nativeLookups;
  Completer<String>? lookupGate;

  setUp(() async {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.3.8',
      buildNumber: '1',
      buildSignature: '',
    );
    timezone = 'America/New_York';
    timezoneUnavailable = false;
    nativeLookups = 0;
    lookupGate = null;
    requests = [];
    messenger.setMockMethodCallHandler(timezoneChannel, (call) async {
      expect(call.method, 'getLocalTimezone');
      nativeLookups++;
      if (timezoneUnavailable) throw PlatformException(code: 'unavailable');
      return lookupGate == null ? timezone : await lookupGate!.future;
    });
    messenger.setMockMethodCallHandler(appInfoChannel, (_) async => false);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      requests.add({
        'method': request.method,
        'path': request.uri.path,
        'timezone': request.headers.value('X-Timezone'),
        'platform': request.headers.value('X-Platform'),
        'auth': request.headers.value(HttpHeaders.authorizationHeader),
      });
      request.response.headers.contentType = ContentType.json;
      // Existing backend shapes, with no new timezone response fields.
      request.response.write(
        jsonEncode({
          'user': {'id': 'user-1'},
          'ok': true,
        }),
      );
      await request.response.close();
    });
    client = HttpOverrides.runWithHttpOverrides(
      () => HttpClient(),
      _RealHttpOverrides(),
    );
    api = BackendApiService(httpClient: _LocalClient(client, server.port));
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(timezoneChannel, null);
    messenger.setMockMethodCallHandler(appInfoChannel, null);
    client.close(force: true);
    await server.close(force: true);
  });

  Future<void> readUser() async {
    expect(await api.fetchMe(identityToken: 'test-token'), {'id': 'user-1'});
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    test(
      '$platform reports launch, resumed, and return-travel timezones',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        await readUser();
        // The same service survives backgrounding. The first resumed request
        // must consult the device again, without an advisory caller priming it.
        binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        timezone = 'America/Los_Angeles';
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await readUser();
        timezone = 'America/New_York';
        await api.registerDeviceToken(
          identityToken: 'test-token',
          deviceToken: 'test-device',
          platform: platform == TargetPlatform.iOS ? 'ios' : 'android',
        );
        expect(requests.map((r) => r['timezone']), [
          'America/New_York',
          'America/Los_Angeles',
          'America/New_York',
        ]);
        expect(requests.map((r) => r['method']), ['GET', 'GET', 'POST']);
        expect(requests.every((r) => r['auth'] == 'Bearer test-token'), isTrue);
        expect(requests.map((r) => r['platform']).toSet(), {
          platform == TargetPlatform.iOS ? 'ios' : 'android',
        });
      },
    );
  }

  test(
    'JSON requests refresh without a preceding GET or lifecycle callback',
    () async {
      Future<void> register() => api.unregisterDeviceToken(
        identityToken: 'test-token',
        deviceToken: 'test-device',
      );
      await register();
      timezone = 'Europe/London';
      await register();
      expect(requests.map((r) => r['timezone']), [
        'America/New_York',
        'Europe/London',
      ]);
    },
  );

  test(
    'native failure without cached timezone omits header and later recovers',
    () async {
      timezoneUnavailable = true;
      await readUser();
      timezoneUnavailable = false;
      await readUser();
      expect(requests.map((r) => r['timezone']), [null, 'America/New_York']);
    },
  );

  test('empty native timezone never sends an empty header', () async {
    timezone = '';
    await readUser();
    timezone = 'Europe/London';
    await readUser();
    expect(requests.map((r) => r['timezone']), [null, 'Europe/London']);
  });

  test(
    'temporary native failures retain usable timezone but cannot pin it',
    () async {
      await readUser();
      timezoneUnavailable = true;
      await readUser();
      timezoneUnavailable = false;
      timezone = 'Europe/London';
      await readUser();
      expect(requests.map((r) => r['timezone']), [
        'America/New_York',
        'America/New_York',
        'Europe/London',
      ]);
    },
  );

  test(
    'concurrent requests and advisory lookup share only the in-flight read',
    () async {
      final gate = Completer<String>();
      lookupGate = gate;
      final advisory = api.getEffectiveTimeZone();
      final reads = List.generate(12, (_) => readUser());
      // Allow the actual loopback connection setup to reach header resolution.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final lookupsBeforeRelease = nativeLookups;
      gate.complete('America/Los_Angeles');
      await Future.wait(reads);
      expect(await advisory, 'America/Los_Angeles');
      expect(lookupsBeforeRelease, 1);
      expect(
        requests.every((r) => r['timezone'] == 'America/Los_Angeles'),
        isTrue,
      );
      lookupGate = null;
      timezone = 'America/New_York';
      await readUser();
      expect(requests.last['timezone'], 'America/New_York');
      expect(nativeLookups, 2);
    },
  );
}
