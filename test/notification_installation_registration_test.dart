import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/notification_service.dart';

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.statusCode, Object? body)
    : _bytes = body == null ? const [] : utf8.encode(jsonEncode(body));

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
  final values = <String, Object>{};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = value;
  }

  @override
  set contentType(ContentType? value) {
    if (value != null) values[HttpHeaders.contentTypeHeader] = value.toString();
  }
}

class _Request extends Fake implements HttpClientRequest {
  _Request(this.method, this.uri, this.response, {this.responseGate});

  @override
  final String method;
  @override
  final Uri uri;
  final HttpClientResponse response;
  final Future<void>? responseGate;
  final body = StringBuffer();

  @override
  final _Headers headers = _Headers();

  @override
  void write(Object? object) => body.write(object);

  @override
  Future<HttpClientResponse> close() async {
    await responseGate;
    return response;
  }
}

class _Http extends Fake implements HttpClient {
  _Http(List<_Response> responses, {this.responseGateForRequest})
    : _responses = List.of(responses);

  final List<_Response> _responses;
  final Future<void>? Function(int requestIndex)? responseGateForRequest;
  final requests = <_Request>[];

  @override
  set connectionTimeout(Duration? value) {}

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final requestIndex = requests.length;
    final request = _Request(
      method,
      url,
      _responses.removeAt(0),
      responseGate: responseGateForRequest?.call(requestIndex),
    );
    requests.add(request);
    return request;
  }
}

Map<String, dynamic> _body(_Request request) =>
    jsonDecode(request.body.toString()) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const notificationsChannel = MethodChannel('com.steptracker/notifications');
  const timezoneChannel = MethodChannel('flutter_timezone');
  const appInfoChannel = MethodChannel('com.steptracker/app_info');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<String> nativeCalls;
  String? iosInstallationId;

  Future<void> simulateIosCallback(String method, Object? arguments) async {
    await messenger.handlePlatformMessage(
      notificationsChannel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(method, arguments),
      ),
      (_) {},
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.3.8',
      buildNumber: '1',
      buildSignature: '',
    );
    nativeCalls = [];
    iosInstallationId = '9f106e79-dfcc-4986-b8a6-11c5d35c3372';
    messenger.setMockMethodCallHandler(timezoneChannel, (_) async => 'UTC');
    messenger.setMockMethodCallHandler(appInfoChannel, (_) async => false);
    messenger.setMockMethodCallHandler(notificationsChannel, (call) async {
      nativeCalls.add(call.method);
      switch (call.method) {
        case 'registerForRemoteNotifications':
          return true;
        case 'getNotificationInstallationId':
          return iosInstallationId;
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(timezoneChannel, null);
    messenger.setMockMethodCallHandler(appInfoChannel, null);
    messenger.setMockMethodCallHandler(notificationsChannel, null);
  });

  group('BackendApiService installation-aware contract', () {
    test('POST sends additive identifiers and parses v2 capability', () async {
      final http = _Http([
        _Response(200, {
          'success': true,
          'registrationVersion': 2,
          'installationAccepted': true,
        }),
      ]);

      final result = await BackendApiService(httpClient: http)
          .registerDeviceToken(
            identityToken: 'auth-token',
            deviceToken: 'apns-token',
            platform: 'ios',
            installationId: 'install-1',
            providerEnvironment: 'production',
          );

      expect(result.registrationVersion, 2);
      expect(result.installationAccepted, isTrue);
      expect(http.requests.single.method, 'POST');
      expect(http.requests.single.uri.path, '/notifications/device-token');
      expect(_body(http.requests.single), {
        'deviceToken': 'apns-token',
        'platform': 'ios',
        'installationId': 'install-1',
        'providerEnvironment': 'production',
      });
    });

    test('POST omits optional fields for the exact legacy request', () async {
      final http = _Http([
        _Response(200, {'success': true}),
      ]);

      final result = await BackendApiService(httpClient: http)
          .registerDeviceToken(
            identityToken: 'auth-token',
            deviceToken: 'legacy-token',
            platform: 'android',
          );

      expect(result.registrationVersion, 1);
      expect(result.installationAccepted, isFalse);
      expect(_body(http.requests.single), {
        'deviceToken': 'legacy-token',
        'platform': 'android',
      });
    });

    test(
      'POST defaults wrong-typed or malformed capability fields safely',
      () async {
        final http = _Http([
          _Response(200, {
            'success': true,
            'registrationVersion': '2',
            'installationAccepted': 1,
          }),
          _Response(200, ['newer', 'unexpected', 'shape']),
        ]);
        final api = BackendApiService(httpClient: http);

        final wrongTyped = await api.registerDeviceToken(
          identityToken: 'auth-token',
          deviceToken: 'token-1',
          platform: 'ios',
          installationId: 'install-1',
        );
        final malformed = await api.registerDeviceToken(
          identityToken: 'auth-token',
          deviceToken: 'token-2',
          platform: 'ios',
          installationId: 'install-1',
        );

        expect(wrongTyped.registrationVersion, 1);
        expect(wrongTyped.installationAccepted, isFalse);
        expect(malformed.registrationVersion, 1);
        expect(malformed.installationAccepted, isFalse);
      },
    );

    test(
      'DELETE sends both identifiers and installation-only additively',
      () async {
        final http = _Http([
          _Response(200, {'success': true, 'removed': 1}),
          _Response(200, {'success': true, 'removed': 1}),
        ]);
        final api = BackendApiService(httpClient: http);

        await api.unregisterDeviceToken(
          identityToken: 'auth-token',
          deviceToken: 'current-token',
          installationId: 'install-1',
        );
        await api.unregisterDeviceToken(
          identityToken: 'auth-token',
          installationId: 'install-1',
        );

        expect(http.requests.map((request) => request.method), [
          'DELETE',
          'DELETE',
        ]);
        expect(_body(http.requests[0]), {
          'deviceToken': 'current-token',
          'installationId': 'install-1',
        });
        expect(_body(http.requests[1]), {'installationId': 'install-1'});
      },
    );
  });

  group('NotificationService iOS installation lifecycle', () {
    test(
      'uses only a fresh APNs callback and clears the legacy cached token',
      () async {
        SharedPreferences.setMockInitialValues({
          'notif_device_token': 'stale-cached-token',
        });
        final http = _Http([
          _Response(200, {
            'success': true,
            'registrationVersion': 2,
            'installationAccepted': true,
          }),
        ]);
        final service = NotificationService(
          backendApiService: BackendApiService(httpClient: http),
          isIosForTesting: true,
        );
        await service.initialize();

        final outcome = await service.ensureTokenRegistered('auth-token');

        expect(outcome, 'registration_requested');
        expect(nativeCalls, contains('registerForRemoteNotifications'));
        expect(http.requests, isEmpty);
        expect(
          (await SharedPreferences.getInstance()).getString(
            'notif_device_token',
          ),
          isNull,
        );

        await simulateIosCallback('onDeviceToken', 'fresh-apns-token');

        expect(http.requests, hasLength(1));
        expect(_body(http.requests.single), {
          'deviceToken': 'fresh-apns-token',
          'platform': 'ios',
          'installationId': iosInstallationId,
        });
        expect(
          (await SharedPreferences.getInstance()).getString(
            'notif_device_token',
          ),
          isNull,
        );
      },
    );

    test(
      'falls back to the legacy POST when Keychain is unavailable',
      () async {
        iosInstallationId = null;
        final http = _Http([
          _Response(200, {
            'success': true,
            'registrationVersion': 2,
            'installationAccepted': false,
          }),
        ]);
        final service = NotificationService(
          backendApiService: BackendApiService(httpClient: http),
          isIosForTesting: true,
        );
        await service.initialize();
        await service.ensureTokenRegistered('auth-token');

        await simulateIosCallback('onDeviceToken', 'fresh-apns-token');

        expect(_body(http.requests.single), {
          'deviceToken': 'fresh-apns-token',
          'platform': 'ios',
        });
      },
    );

    test(
      'logout sends the current token and installation whenever possible',
      () async {
        final http = _Http([
          _Response(200, {
            'success': true,
            'registrationVersion': 1,
            'installationAccepted': false,
          }),
          _Response(200, {'success': true, 'removed': 1}),
        ]);
        final service = NotificationService(
          backendApiService: BackendApiService(httpClient: http),
          isIosForTesting: true,
        );
        await service.initialize();
        await service.ensureTokenRegistered('old-backend-auth');
        await simulateIosCallback('onDeviceToken', 'fresh-apns-token');

        await service.unregisterDeviceToken('old-backend-auth');

        expect(http.requests, hasLength(2));
        expect(_body(http.requests.last), {
          'deviceToken': 'fresh-apns-token',
          'installationId': iosInstallationId,
        });
      },
    );

    test(
      'logout uses installation-only only after observing v2 capability',
      () async {
        final http = _Http([
          _Response(200, {
            'success': true,
            'registrationVersion': 2,
            'installationAccepted': true,
          }),
          _Response(200, {'success': true, 'removed': 1}),
        ]);
        final service = NotificationService(
          backendApiService: BackendApiService(httpClient: http),
          isIosForTesting: true,
        );
        await service.initialize();
        await service.ensureTokenRegistered('v2-auth');
        await simulateIosCallback('onDeviceToken', 'fresh-apns-token');
        await simulateIosCallback('onDeviceTokenError', 'token unavailable');

        await service.unregisterDeviceToken('v2-auth');

        expect(http.requests, hasLength(2));
        expect(_body(http.requests.last), {
          'installationId': iosInstallationId,
        });
      },
    );

    test(
      'logout skips installation-only when v2 rejected the binding',
      () async {
        final http = _Http([
          _Response(200, {
            'success': true,
            'registrationVersion': 2,
            'installationAccepted': false,
          }),
          _Response(200, {'success': true, 'removed': 1}),
        ]);
        final service = NotificationService(
          backendApiService: BackendApiService(httpClient: http),
          isIosForTesting: true,
        );
        await service.initialize();
        await service.ensureTokenRegistered('v2-unbound-auth');
        await simulateIosCallback('onDeviceToken', 'fresh-apns-token');
        await simulateIosCallback('onDeviceTokenError', 'token unavailable');

        await service.unregisterDeviceToken('v2-unbound-auth');

        expect(http.requests, hasLength(1));
        expect(http.requests.single.method, 'POST');
      },
    );

    test(
      'logout skips installation-only cleanup against an old backend',
      () async {
        final http = _Http([
          _Response(200, {'success': true}),
        ]);
        final service = NotificationService(
          backendApiService: BackendApiService(httpClient: http),
          isIosForTesting: true,
        );
        await service.initialize();
        await service.ensureTokenRegistered('v1-auth');
        await simulateIosCallback('onDeviceToken', 'fresh-apns-token');
        await simulateIosCallback('onDeviceTokenError', 'token unavailable');

        await service.unregisterDeviceToken('v1-auth');

        expect(http.requests, hasLength(1));
      },
    );

    test(
      'logout compensates for a registration POST that completes late',
      () async {
        final registrationResponse = Completer<void>();
        final http = _Http(
          [
            _Response(200, {
              'success': true,
              'registrationVersion': 2,
              'installationAccepted': true,
            }),
            _Response(200, {'success': true, 'removed': 1}),
            _Response(200, {'success': true, 'removed': 1}),
          ],
          responseGateForRequest: (index) =>
              index == 0 ? registrationResponse.future : null,
        );
        final service = NotificationService(
          backendApiService: BackendApiService(httpClient: http),
          isIosForTesting: true,
        );
        await service.initialize();
        await service.ensureTokenRegistered('auth-a');

        final registration = simulateIosCallback(
          'onDeviceToken',
          'fresh-apns-token',
        );
        await Future<void>.delayed(Duration.zero);
        expect(http.requests, hasLength(1));

        final logout = service.unregisterDeviceToken('auth-a');
        await Future<void>.delayed(Duration.zero);
        expect(http.requests, hasLength(1));

        registrationResponse.complete();
        await Future.wait([registration, logout]);

        expect(http.requests.map((request) => request.method), [
          'POST',
          'DELETE',
          'DELETE',
        ]);
        expect(_body(http.requests.last), {
          'deviceToken': 'fresh-apns-token',
          'installationId': iosInstallationId,
        });
      },
    );

    test(
      'account switch removes an old registration that completes late',
      () async {
        final accountAResponse = Completer<void>();
        final http = _Http(
          [
            _Response(200, {
              'success': true,
              'registrationVersion': 2,
              'installationAccepted': true,
            }),
            _Response(200, {
              'success': true,
              'registrationVersion': 2,
              'installationAccepted': true,
            }),
            _Response(200, {'success': true, 'removed': 1}),
          ],
          responseGateForRequest: (index) =>
              index == 0 ? accountAResponse.future : null,
        );
        final service = NotificationService(
          backendApiService: BackendApiService(httpClient: http),
          isIosForTesting: true,
        );
        await service.initialize();
        await service.ensureTokenRegistered('auth-a');

        final accountARegistration = simulateIosCallback(
          'onDeviceToken',
          'fresh-apns-token',
        );
        await Future<void>.delayed(Duration.zero);
        expect(http.requests, hasLength(1));

        await service.ensureTokenRegistered('auth-b');
        final accountBRegistration = simulateIosCallback(
          'onDeviceToken',
          'fresh-apns-token',
        );
        await Future<void>.delayed(Duration.zero);
        expect(http.requests, hasLength(1));

        accountAResponse.complete();
        await Future.wait([accountARegistration, accountBRegistration]);

        expect(http.requests.map((request) => request.method), [
          'POST',
          'DELETE',
          'POST',
        ]);
        expect(
          http.requests[1].headers.values[HttpHeaders.authorizationHeader],
          'Bearer auth-a',
        );
        expect(
          http.requests.last.headers.values[HttpHeaders.authorizationHeader],
          'Bearer auth-b',
        );
        expect(_body(http.requests[1]), {
          'deviceToken': 'fresh-apns-token',
          'installationId': iosInstallationId,
        });
      },
    );

    test(
      'same-account re-login leaves the newest registration active',
      () async {
        final firstRegistrationResponse = Completer<void>();
        final http = _Http(
          [
            _Response(200, {
              'success': true,
              'registrationVersion': 2,
              'installationAccepted': true,
            }),
            _Response(200, {'success': true, 'removed': 1}),
            _Response(200, {'success': true, 'removed': 0}),
            _Response(200, {
              'success': true,
              'registrationVersion': 2,
              'installationAccepted': true,
            }),
          ],
          responseGateForRequest: (index) =>
              index == 0 ? firstRegistrationResponse.future : null,
        );
        final service = NotificationService(
          backendApiService: BackendApiService(httpClient: http),
          isIosForTesting: true,
        );
        await service.initialize();
        await service.ensureTokenRegistered('auth-a');

        final firstRegistration = simulateIosCallback(
          'onDeviceToken',
          'fresh-apns-token',
        );
        await Future<void>.delayed(Duration.zero);
        expect(http.requests, hasLength(1));

        final logout = service.unregisterDeviceToken('auth-a');
        await service.ensureTokenRegistered('auth-a');
        final newestRegistration = simulateIosCallback(
          'onDeviceToken',
          'fresh-apns-token',
        );
        await Future<void>.delayed(Duration.zero);
        expect(http.requests, hasLength(1));

        firstRegistrationResponse.complete();
        await Future.wait([firstRegistration, logout, newestRegistration]);

        expect(http.requests.map((request) => request.method), [
          'POST',
          'DELETE',
          'DELETE',
          'POST',
        ]);
        expect(
          http.requests.last.headers.values[HttpHeaders.authorizationHeader],
          'Bearer auth-a',
        );
        expect(_body(http.requests.last), {
          'deviceToken': 'fresh-apns-token',
          'platform': 'ios',
          'installationId': iosInstallationId,
        });
      },
    );
  });

  group('NotificationService Android installation lifecycle', () {
    test(
      'uploads the current Firebase token with the Firebase Installation ID',
      () async {
        final http = _Http([
          _Response(200, {
            'success': true,
            'registrationVersion': 2,
            'installationAccepted': true,
          }),
        ]);
        final service = NotificationService(
          backendApiService: BackendApiService(httpClient: http),
          isAndroidForTesting: true,
          androidTokenProvider: () async => 'current-fcm-token',
          installationIdProvider: () async => 'firebase-installation-id',
        );

        final outcome = await service.ensureTokenRegistered('auth-token');

        expect(outcome, 'registered');
        expect(_body(http.requests.single), {
          'deviceToken': 'current-fcm-token',
          'platform': 'android',
          'installationId': 'firebase-installation-id',
        });
      },
    );

    test('falls back to the legacy POST when FID lookup fails', () async {
      final http = _Http([
        _Response(200, {
          'success': true,
          'registrationVersion': 2,
          'installationAccepted': false,
        }),
      ]);
      final service = NotificationService(
        backendApiService: BackendApiService(httpClient: http),
        isAndroidForTesting: true,
        androidTokenProvider: () async => 'current-fcm-token',
        installationIdProvider: () async => throw StateError('FID offline'),
      );

      final outcome = await service.ensureTokenRegistered('auth-token');

      expect(outcome, 'registered');
      expect(_body(http.requests.single), {
        'deviceToken': 'current-fcm-token',
        'platform': 'android',
      });
    });
  });
}
