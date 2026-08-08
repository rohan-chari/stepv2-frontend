import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/notification_service.dart';

/// Regression tests for the silent push-token registration failure: a user
/// whose OS permission is granted but whose app never re-registers the APNs
/// token with the backend (stale prefs cache, missed didRegister callback,
/// or a registration error that was swallowed). The service must now key off
/// the real OS permission and re-post the last known token every session.
class _RecordingApi extends BackendApiService {
  final registered = <Map<String, String>>[];
  Object? throwOnRegister;

  @override
  Future<void> registerDeviceToken({
    required String identityToken,
    required String deviceToken,
    required String platform,
  }) async {
    if (throwOnRegister != null) throw throwOnRegister!;
    registered.add({
      'identityToken': identityToken,
      'deviceToken': deviceToken,
      'platform': platform,
    });
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
    service = NotificationService(backendApiService: api);
    nativeCalls = [];
    permissionStatus = 'authorized';
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call.method);
      switch (call.method) {
        case 'getPermissionStatus':
          return permissionStatus;
        case 'registerForRemoteNotifications':
          return true;
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
    test('re-posts the cached token even when no fresh APNs callback fires',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('notif_device_token', 'cached-apns-token');

      final outcome = await service.ensureTokenRegistered('auth-123');

      expect(outcome, 'registered_cached');
      expect(nativeCalls, contains('registerForRemoteNotifications'));
      expect(api.registered, hasLength(1));
      expect(api.registered.single['deviceToken'], 'cached-apns-token');
      expect(api.registered.single['identityToken'], 'auth-123');
      expect(api.registered.single['platform'], 'ios');
    });

    test('marks the cached permission granted so the settings UI agrees',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('notif_device_token', 'cached-apns-token');

      await service.ensureTokenRegistered('auth-123');

      expect(await service.getPermissionState(), isTrue);
    });

    test(
        'still asks the OS to register when no token is cached, and a later '
        'native token delivery reaches the backend with the pending auth',
        () async {
      final outcome = await service.ensureTokenRegistered('auth-456');

      expect(outcome, 'no_cached_token');
      expect(nativeCalls, contains('registerForRemoteNotifications'));
      expect(api.registered, isEmpty);

      await simulateNativeCall('onDeviceToken', 'fresh-apns-token');

      expect(api.registered, hasLength(1));
      expect(api.registered.single['deviceToken'], 'fresh-apns-token');
      expect(api.registered.single['identityToken'], 'auth-456');
    });

    test('skips without auth', () async {
      final outcome = await service.ensureTokenRegistered(null);
      expect(outcome, 'no_auth');
      expect(api.registered, isEmpty);
    });

    test('reports a backend failure instead of swallowing it', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('notif_device_token', 'cached-apns-token');
      api.throwOnRegister = Exception('boom');

      final outcome = await service.ensureTokenRegistered('auth-123');

      expect(outcome, startsWith('failed'));
    });

    test('surfaces the last native registration error when no token exists',
        () async {
      await simulateNativeCall('onDeviceTokenError', 'no APNs connection');

      final outcome = await service.ensureTokenRegistered('auth-123');

      expect(outcome, 'register_failed:no APNs connection');
    });

    test('a successful token delivery clears the stored native error',
        () async {
      await simulateNativeCall('onDeviceTokenError', 'transient');
      await simulateNativeCall('onDeviceToken', 'fresh-apns-token');
      await service.ensureTokenRegistered('auth-123');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('notif_last_register_error'), isNull);
    });
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
