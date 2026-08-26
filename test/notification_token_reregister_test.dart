import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/notification_service.dart';

/// Regression tests for the silent push-token registration failure: a user
/// whose OS permission is granted but whose app never re-registers the APNs
/// token with the backend (stale prefs cache, missed didRegister callback,
/// or a registration error that was swallowed). The service must now key off
/// the real OS permission and ask APNs for a current callback every session,
/// without reposting a token persisted by an earlier launch.
class _RecordingApi extends BackendApiService {
  final registered = <Map<String, String>>[];
  Object? throwOnRegister;
  int registerAttempts = 0;

  @override
  Future<DeviceTokenRegistrationResult> registerDeviceToken({
    required String identityToken,
    required String deviceToken,
    required String platform,
    String? installationId,
    String? providerEnvironment,
  }) async {
    registerAttempts++;
    if (throwOnRegister != null) throw throwOnRegister!;
    registered.add({
      'identityToken': identityToken,
      'deviceToken': deviceToken,
      'platform': platform,
      'installationId': ?installationId,
    });
    return const DeviceTokenRegistrationResult(
      registrationVersion: 2,
      installationAccepted: true,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.steptracker/notifications');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late _RecordingApi api;
  late NotificationService service;
  late List<String> nativeCalls;
  String permissionStatus = 'authorized';

  Future<void> simulateNativeCall(String method, Object? arguments) async {
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(method, arguments),
      ),
      (_) {},
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    api = _RecordingApi();
    service = NotificationService(
      backendApiService: api,
      isIosForTesting: true,
    );
    nativeCalls = [];
    permissionStatus = 'authorized';
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call.method);
      switch (call.method) {
        case 'getPermissionStatus':
          return permissionStatus;
        case 'registerForRemoteNotifications':
          return true;
        case 'getNotificationInstallationId':
          return 'installation-1';
        case 'requestPermission':
          return true;
      }
      return null;
    });
    await service.initialize();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('getSystemPermissionState', () {
    test('maps authorized/provisional to true', () async {
      permissionStatus = 'authorized';
      expect(await service.getSystemPermissionState(), isTrue);
      permissionStatus = 'provisional';
      expect(await service.getSystemPermissionState(), isTrue);
    });

    test('maps denied to false and notDetermined to null', () async {
      permissionStatus = 'denied';
      expect(await service.getSystemPermissionState(), isFalse);
      permissionStatus = 'notDetermined';
      expect(await service.getSystemPermissionState(), isNull);
    });

    test('falls back to the cached pref when the channel fails', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'unavailable');
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notif_permission_granted', true);
      expect(await service.getSystemPermissionState(), isTrue);
    });
  });

  group('ensureTokenRegistered', () {
    test(
      'never re-posts a cached token when no fresh APNs callback fires',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('notif_device_token', 'cached-apns-token');

        final outcome = await service.ensureTokenRegistered('auth-123');

        expect(outcome, 'registration_requested');
        expect(nativeCalls, contains('registerForRemoteNotifications'));
        expect(api.registered, isEmpty);
        expect(prefs.getString('notif_device_token'), isNull);
      },
    );

    test(
      'marks the cached permission granted so the settings UI agrees',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('notif_device_token', 'cached-apns-token');

        await service.ensureTokenRegistered('auth-123');

        expect(await service.getPermissionState(), isTrue);
      },
    );

    test(
      'still asks the OS to register when no token is cached, and a later '
      'native token delivery reaches the backend with the pending auth',
      () async {
        final outcome = await service.ensureTokenRegistered('auth-456');

        expect(outcome, 'registration_requested');
        expect(nativeCalls, contains('registerForRemoteNotifications'));
        expect(api.registered, isEmpty);

        await simulateNativeCall('onDeviceToken', 'fresh-apns-token');

        expect(api.registered, hasLength(1));
        expect(api.registered.single['deviceToken'], 'fresh-apns-token');
        expect(api.registered.single['identityToken'], 'auth-456');
        expect(api.registered.single['installationId'], 'installation-1');
      },
    );

    test('skips without auth', () async {
      final outcome = await service.ensureTokenRegistered(null);
      expect(outcome, 'no_auth');
      expect(api.registered, isEmpty);
    });

    test('contains an async APNs callback backend failure', () async {
      api.throwOnRegister = Exception('boom');

      final outcome = await service.ensureTokenRegistered('auth-123');
      await simulateNativeCall('onDeviceToken', 'fresh-apns-token');

      expect(outcome, 'registration_requested');
      expect(api.registerAttempts, 1);
      expect(api.registered, isEmpty);
    });

    test(
      'surfaces the last native registration error when no token exists',
      () async {
        await simulateNativeCall('onDeviceTokenError', 'no APNs connection');

        final outcome = await service.ensureTokenRegistered('auth-123');

        expect(outcome, 'register_failed:no APNs connection');
      },
    );

    test(
      'a successful token delivery clears the stored native error',
      () async {
        await simulateNativeCall('onDeviceTokenError', 'transient');
        await simulateNativeCall('onDeviceToken', 'fresh-apns-token');
        await service.ensureTokenRegistered('auth-123');

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('notif_last_register_error'), isNull);
      },
    );
  });

  group('clearCachedPermission', () {
    test('resets the cache so a reinstalled app re-prompts', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notif_permission_granted', true);

      await service.clearCachedPermission();

      expect(await service.getPermissionState(), isNull);
    });
  });
}
