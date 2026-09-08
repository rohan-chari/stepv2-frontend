import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:step_tracker/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test(
    'local notification cold launch retains race destination exactly once',
    () async {
      var reads = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getNotificationAppLaunchDetails') {
              reads++;
              return {
                'notificationLaunchedApp': true,
                'notificationResponse': {
                  'notificationResponseType': 0,
                  'id': 12,
                  'payload': jsonEncode({
                    'type': 'RACE_STARTED',
                    'raceId': 'race-123',
                  }),
                },
              };
            }
            return true;
          });
      final service = NotificationService(
        isAndroidForTesting: true,
        isIosForTesting: false,
      );
      await service.initializeLocalNotifications();
      expect(service.pendingAction.value?.route, NotificationRoute.raceDetail);
      expect(service.pendingAction.value?.params['raceId'], 'race-123');
      service.pendingAction.value = null;
      await service.initializeLocalNotifications();
      expect(service.pendingAction.value, isNull);
      expect(reads, 1);
    },
  );
}
