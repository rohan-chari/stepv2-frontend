import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/services/activation_analytics_service.dart';
import 'package:step_tracker/services/admin_metrics_telemetry_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/notification_service.dart';

class _Api extends BackendApiService {
  final List<Map<String, dynamic>> foreground = [];
  final List<String> notificationOpens = [];
  final List<Map<String, String>> notificationOpenCalls = [];
  final List<List<Map<String, dynamic>>> activationBatches = [];
  Object? foregroundError;
  Object? openError;
  Object? activationError;
  Completer<void>? foregroundGate;
  Completer<void>? openGate;
  int openAttempts = 0;

  @override
  Future<void> sendAdminMetricsForeground({
    required String identityToken,
    required String sessionId,
    required DateTime occurredAt,
    required String appVersion,
  }) async {
    if (foregroundError case final error?) throw error;
    final gate = foregroundGate;
    foregroundGate = null;
    if (gate != null) await gate.future;
    foreground.add({
      'identityToken': identityToken,
      'sessionId': sessionId,
      'occurredAt': occurredAt.toUtc().toIso8601String(),
      'appVersion': appVersion,
    });
  }

  @override
  Future<void> sendAdminMetricsNotificationOpen({
    required String identityToken,
    required String notificationId,
  }) async {
    openAttempts++;
    final gate = openGate;
    openGate = null;
    if (gate != null) await gate.future;
    if (openError case final error?) throw error;
    notificationOpens.add(notificationId);
    notificationOpenCalls.add({
      'identityToken': identityToken,
      'notificationId': notificationId,
    });
  }

  @override
  Future<void> sendActivationEvents({
    required String identityToken,
    required List<Map<String, dynamic>> events,
  }) async {
    if (activationError case final error?) throw error;
    activationBatches.add(events);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.4.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  test('both feature-list branches add admin_metrics_v2 on iOS only', () {
    for (final adsSupported in [false, true]) {
      final ios = BackendApiService.clientFeaturesHeaderForPlatform(
        isIos: true,
        adsSupported: adsSupported,
        racePayoutDoubleSupported: false,
      ).split(',');
      final android = BackendApiService.clientFeaturesHeaderForPlatform(
        isIos: false,
        adsSupported: adsSupported,
        racePayoutDoubleSupported: false,
      ).split(',');
      expect(ios, contains('admin_metrics_v2'));
      expect(android, isNot(contains('admin_metrics_v2')));
    }
  });

  test(
    'iOS foreground emits once per authenticated session and after 30s away',
    () async {
      final api = _Api();
      var now = DateTime.utc(2026, 8, 18, 14);
      final telemetry = AdminMetricsTelemetryService(
        backendApiService: api,
        isIosForTesting: true,
        now: () => now,
      );

      await telemetry.authenticatedForeground('token', userId: 'user-a');
      await telemetry.authenticatedForeground('token', userId: 'user-a');
      expect(api.foreground, hasLength(1));

      telemetry.didEnterBackground();
      now = now.add(const Duration(seconds: 29));
      await telemetry.didResume('token', userId: 'user-a');
      expect(api.foreground, hasLength(1));

      telemetry.didEnterBackground();
      now = now.add(const Duration(seconds: 31));
      await telemetry.didResume('token', userId: 'user-a');
      expect(api.foreground, hasLength(2));
      expect(
        api.foreground.map((event) => event['sessionId']).toSet(),
        hasLength(2),
      );
    },
  );

  test(
    'Android emits no foreground, health, leaderboard, or open facts',
    () async {
      final api = _Api();
      final telemetry = AdminMetricsTelemetryService(
        backendApiService: api,
        isIosForTesting: false,
      );
      await telemetry.authenticatedForeground('token', userId: 'user-a');
      expect(api.foreground, isEmpty);

      final analytics = ActivationAnalyticsService(
        backendApiService: api,
        isIosForTesting: false,
      );
      await analytics.record(
        'health_connected',
        ownerUserId: 'user-a',
        context: const {'source': 'healthkit'},
      );
      await analytics.record(
        'race_leaderboard_viewed',
        ownerUserId: 'user-a',
        context: const {'race_id': '550e8400-e29b-41d4-a716-446655440000'},
      );
      await analytics.flush('token');
      expect(api.activationBatches, isEmpty);

      final notifications = NotificationService(
        backendApiService: api,
        isIosForTesting: false,
      );
      await notifications.handleNotificationTapForTesting({
        'notificationId': '01JABCDEFGHJKMNPQRSTVWXYZ12',
        'type': 'FRIEND_REQUEST_SENT',
        'params': <String, dynamic>{},
      });
      await notifications.flushPendingOpenReceipts('token');
      expect(api.notificationOpens, isEmpty);
    },
  );

  test(
    'new activation events enforce exact context and stay best-effort',
    () async {
      final api = _Api();
      final analytics = ActivationAnalyticsService(
        backendApiService: api,
        isIosForTesting: true,
      );
      await analytics.record('health_connected');
      await analytics.record(
        'health_connected',
        ownerUserId: 'user-a',
        context: const {'source': 'profile'},
      );
      await analytics.record(
        'health_connected',
        ownerUserId: 'user-a',
        context: const {'source': 'healthkit'},
      );
      await analytics.record(
        'race_leaderboard_viewed',
        ownerUserId: 'user-a',
        context: const {'race_id': 'not-a-uuid'},
      );
      await analytics.record(
        'race_leaderboard_viewed',
        ownerUserId: 'user-a',
        context: const {'race_id': '550e8400-e29b-41d4-a716-446655440000'},
      );
      await analytics.flush('token', userId: 'user-a');

      final events = api.activationBatches.single;
      expect(events.map((event) => event['name']), [
        'health_connected',
        'race_leaderboard_viewed',
      ]);
    },
  );

  test('account B never flushes account A activation events', () async {
    final api = _Api()..activationError = Exception('offline');
    final accountA = ActivationAnalyticsService(
      backendApiService: api,
      isIosForTesting: true,
    );
    await accountA.record(
      'health_connected',
      ownerUserId: 'user-a',
      context: const {'source': 'healthkit'},
    );
    await accountA.flush('token-a', userId: 'user-a');

    api.activationError = null;
    final accountB = ActivationAnalyticsService(
      backendApiService: api,
      isIosForTesting: true,
    );
    await accountB.record(
      'race_leaderboard_viewed',
      ownerUserId: 'user-b',
      context: const {'race_id': '550e8400-e29b-41d4-a716-446655440000'},
    );
    await accountB.flush('token-b', userId: 'user-b');

    expect(api.activationBatches, hasLength(1));
    expect(api.activationBatches.single, hasLength(1));
    expect(
      api.activationBatches.single.single['name'],
      'race_leaderboard_viewed',
    );
    expect(
      api.activationBatches.single.single.containsKey('ownerUserId'),
      isFalse,
    );
  });

  test(
    'offline foreground stays bounded and a 404 is swallowed and dropped',
    () async {
      final api = _Api()..foregroundError = Exception('offline');
      var now = DateTime.utc(2026, 8, 18, 14);
      final telemetry = AdminMetricsTelemetryService(
        backendApiService: api,
        isIosForTesting: true,
        now: () => now,
      );
      for (var i = 0; i < 30; i++) {
        await telemetry.authenticatedForeground('token', userId: 'user-a');
        telemetry.didEnterBackground();
        now = now.add(const Duration(seconds: 31));
        await telemetry.didResume('token', userId: 'user-a');
      }
      final prefs = await SharedPreferences.getInstance();
      final queued =
          jsonDecode(prefs.getString(AdminMetricsTelemetryService.storageKey)!)
              as List;
      expect(queued.length, AdminMetricsTelemetryService.maxQueuedSessions);

      api.foregroundError = const ApiException('missing', statusCode: 404);
      await telemetry.flush('token', userId: 'user-a');
      expect(prefs.getString(AdminMetricsTelemetryService.storageKey), '[]');
    },
  );

  test(
    'cold restart under account B purges account A offline foregrounds',
    () async {
      final offlineApi = _Api()..foregroundError = Exception('offline');
      final accountA = AdminMetricsTelemetryService(
        backendApiService: offlineApi,
        isIosForTesting: true,
      );
      await accountA.authenticatedForeground('token-a', userId: 'user-a');

      final prefs = await SharedPreferences.getInstance();
      final accountAQueue =
          jsonDecode(prefs.getString(AdminMetricsTelemetryService.storageKey)!)
              as List;
      expect(accountAQueue.single['ownerUserId'], 'user-a');

      // Simulate process death: the new service has no in-memory account id.
      final onlineApi = _Api();
      final accountB = AdminMetricsTelemetryService(
        backendApiService: onlineApi,
        isIosForTesting: true,
      );
      await accountB.authenticatedForeground('token-b', userId: 'user-b');

      expect(onlineApi.foreground, hasLength(1));
      expect(onlineApi.foreground.single['identityToken'], 'token-b');
      expect(prefs.getString(AdminMetricsTelemetryService.storageKey), '[]');
    },
  );

  test('account B is not deleted by account A in-flight flush', () async {
    final gate = Completer<void>();
    final api = _Api()..foregroundGate = gate;
    final telemetry = AdminMetricsTelemetryService(
      backendApiService: api,
      isIosForTesting: true,
    );

    final accountA = telemetry.authenticatedForeground(
      'token-a',
      userId: 'user-a',
    );
    while (api.foregroundGate != null) {
      await Future<void>.delayed(Duration.zero);
    }
    final accountB = telemetry.authenticatedForeground(
      'token-b',
      userId: 'user-b',
    );

    gate.complete();
    await accountA;
    await accountB;

    expect(api.foreground.map((event) => event['identityToken']), [
      'token-a',
      'token-b',
    ]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AdminMetricsTelemetryService.storageKey), '[]');
  });

  test(
    'cold-start notification id queues until auth then flushes once',
    () async {
      final api = _Api();
      final notifications = NotificationService(
        backendApiService: api,
        isIosForTesting: true,
      );
      await notifications.handleNotificationTapForTesting({
        'notificationId': '01JABCDEFGHJKMNPQRSTVWXYZ12',
        'type': 'FRIEND_REQUEST_SENT',
        'params': <String, dynamic>{},
      });
      expect(notifications.pendingAction.value, isNotNull);
      expect(api.notificationOpens, isEmpty);

      await notifications.flushPendingOpenReceipts('token', userId: 'user-a');
      await notifications.flushPendingOpenReceipts('token', userId: 'user-a');
      expect(api.notificationOpens, ['01JABCDEFGHJKMNPQRSTVWXYZ12']);
    },
  );

  test('legacy string receipt migrates to owned wire-safe receipt', () async {
    const notificationId = '01JEEEEEEEEEEEEEEEEEEEEEEEEEE';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'admin_metrics_notification_opens_v1',
      jsonEncode([notificationId]),
    );
    final api = _Api();
    final notifications = NotificationService(
      backendApiService: api,
      isIosForTesting: true,
    );

    await notifications.flushPendingOpenReceipts('token-a', userId: 'user-a');

    expect(api.notificationOpenCalls, [
      const {'identityToken': 'token-a', 'notificationId': notificationId},
    ]);
    expect(prefs.getString('admin_metrics_notification_opens_v1'), '[]');
  });

  test(
    'account B never flushes account A offline notification receipt',
    () async {
      const accountAId = '01JAAAAAAAAAAAAAAAAAAAAAAAAAA';
      const accountBId = '01JBBBBBBBBBBBBBBBBBBBBBBBBBB';
      final api = _Api()..openError = Exception('offline');
      final accountA = NotificationService(
        backendApiService: api,
        isIosForTesting: true,
      );
      await accountA.handleNotificationTapForTesting({
        'notificationId': accountAId,
        'type': 'FRIEND_REQUEST_SENT',
        'params': <String, dynamic>{},
      });
      await accountA.flushPendingOpenReceipts('token-a', userId: 'user-a');

      api.openError = null;
      final accountB = NotificationService(
        backendApiService: api,
        isIosForTesting: true,
      );
      await accountB.flushPendingOpenReceipts('token-b', userId: 'user-b');
      await accountB.handleNotificationTapForTesting({
        'notificationId': accountBId,
        'type': 'FRIEND_REQUEST_SENT',
        'params': <String, dynamic>{},
      });

      expect(api.notificationOpenCalls, [
        const {'identityToken': 'token-b', 'notificationId': accountBId},
      ]);
      expect(api.notificationOpens, isNot(contains(accountAId)));
    },
  );

  test(
    'account switch cannot relabel an in-flight notification receipt',
    () async {
      const accountAId = '01JCCCCCCCCCCCCCCCCCCCCCCCCCC';
      const accountBId = '01JDDDDDDDDDDDDDDDDDDDDDDDD';
      final gate = Completer<void>();
      final api = _Api()..openGate = gate;
      final notifications = NotificationService(
        backendApiService: api,
        isIosForTesting: true,
      );
      await notifications.flushPendingOpenReceipts('token-a', userId: 'user-a');
      final accountATap = notifications.handleNotificationTapForTesting({
        'notificationId': accountAId,
        'type': 'FRIEND_REQUEST_SENT',
        'params': <String, dynamic>{},
      });
      while (api.openGate != null) {
        await Future<void>.delayed(Duration.zero);
      }
      final switchAccount = notifications.flushPendingOpenReceipts(
        'token-b',
        userId: 'user-b',
      );

      gate.complete();
      await accountATap;
      await switchAccount;
      await notifications.handleNotificationTapForTesting({
        'notificationId': accountBId,
        'type': 'FRIEND_REQUEST_SENT',
        'params': <String, dynamic>{},
      });

      expect(api.notificationOpenCalls, [
        const {'identityToken': 'token-a', 'notificationId': accountAId},
        const {'identityToken': 'token-b', 'notificationId': accountBId},
      ]);
    },
  );

  test(
    'old pushes and old-server open endpoints never block navigation',
    () async {
      final api = _Api()
        ..openError = const ApiException('missing', statusCode: 405);
      final notifications = NotificationService(
        backendApiService: api,
        isIosForTesting: true,
      );
      await notifications.handleNotificationTapForTesting({
        'notificationId': '01JABCDEFGHJKMNPQRSTVWXYZ12',
        'type': 'FRIEND_REQUEST_SENT',
        'params': <String, dynamic>{},
      });
      expect(notifications.pendingAction.value, isNotNull);
      await notifications.flushPendingOpenReceipts('token', userId: 'user-a');
      expect(api.notificationOpens, isEmpty);
      expect(api.openAttempts, 1);
    },
  );
}
