import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('GLOBAL_EVENT_STARTED tap routes the iOS APNs payload to Home', () async {
    final notifications = NotificationService(isIosForTesting: true);

    await notifications.handleNotificationTapForTesting({
      'type': 'GLOBAL_EVENT_STARTED',
      'title': '2x STEPS EVENT',
      'body':
          'Double steps are LIVE for 30 minutes. Every step counts 2x in your races! Go!',
      'params': <String, dynamic>{},
    });

    expect(notifications.pendingAction.value?.route, NotificationRoute.home);
    expect(notifications.pendingAction.value?.params, isEmpty);
  });

  test(
    'GLOBAL_EVENT_STARTED tap routes the Android FCM payload to Home',
    () async {
      final notifications = NotificationService(isIosForTesting: false);

      await notifications.handleNotificationTapForTesting({
        'type': 'GLOBAL_EVENT_STARTED',
        'title': '2x STEPS EVENT',
        'body':
            'Double steps are LIVE for 30 minutes. Every step counts 2x in your races! Go!',
      });

      expect(notifications.pendingAction.value?.route, NotificationRoute.home);
      expect(notifications.pendingAction.value?.params, isEmpty);
    },
  );
}
