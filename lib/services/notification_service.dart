import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend_api_service.dart';

/// Channel to the native (Android) background-sync layer. On Android,
/// `enqueueExpeditedSync` schedules a WorkManager job that reads Health Connect and
/// posts steps. (On iOS the same channel name is used by AppDelegate for HealthKit
/// background delivery; this Dart side is Android-only.)
const _backgroundSyncChannel = MethodChannel('com.steptracker/background_sync');

/// Android FCM background isolate handler. Notification-type messages are shown by
/// the system tray automatically. Phase 3: a backend `STEP_SYNC_REQUEST` silent
/// data message asks the device to push fresh steps now — we try to enqueue an
/// expedited native WorkManager sync. In a fully-detached background isolate the
/// channel may have no handler; that's caught and the 15-min periodic worker
/// (Phase 2) remains the reliable baseline. Must be a top-level AOT entry point.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (message.data['type'] == 'STEP_SYNC_REQUEST') {
    try {
      await _backgroundSyncChannel.invokeMethod('enqueueExpeditedSync');
    } catch (_) {
      // No native channel handler in this isolate — periodic worker covers it.
    }
  }
}

enum NotificationRoute { home, friends, raceDetail, races, tournamentDetail }

class NotificationAction {
  final NotificationRoute route;
  final Map<String, String> params;

  const NotificationAction({required this.route, this.params = const {}});
}

class NotificationService {
  NotificationService({BackendApiService? backendApiService})
    : _backendApiService = backendApiService ?? BackendApiService();

  static const _channel = MethodChannel('com.steptracker/notifications');
  static const _keyDeviceToken = 'notif_device_token';
  static const _keyPermissionGranted = 'notif_permission_granted';

  // Android-only foreground display channel for FCM. Mirrors a typical
  // high-importance channel; ignored on iOS.
  static const _androidChannel = AndroidNotificationChannel(
    'bara_default',
    'Notifications',
    description: 'Race, friend, and reward notifications',
    importance: Importance.high,
  );

  final BackendApiService _backendApiService;
  final ValueNotifier<NotificationAction?> pendingAction = ValueNotifier(null);

  String? _pendingAuthToken;
  FlutterLocalNotificationsPlugin? _localNotifications;

  Future<void> initialize() async {
    // iOS device token + tap routing flow over the native APNs bridge.
    _channel.setMethodCallHandler(_handleMethodCall);
    // Android uses FCM instead; iOS never touches Firebase.
    if (Platform.isAndroid) {
      await _initAndroidMessaging();
    }
  }

  Future<void> _initAndroidMessaging() async {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    final local = FlutterLocalNotificationsPlugin();
    await local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          _onNotificationTapFromData(_decodeData(payload));
        }
      },
    );
    await local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_androidChannel);
    _localNotifications = local;

    // Foreground messages: the system tray does NOT show them automatically, so
    // render a local notification carrying the data payload for tap routing.
    FirebaseMessaging.onMessage.listen((message) {
      // Phase 3: a data-only STEP_SYNC_REQUEST (received while foregrounded) asks
      // us to push fresh steps now. The main-engine channel handler is registered,
      // so this enqueue path is reliable here.
      if (message.data['type'] == 'STEP_SYNC_REQUEST') {
        _backgroundSyncChannel.invokeMethod('enqueueExpeditedSync').catchError(
          (_) {},
        );
        return;
      }
      final notification = message.notification;
      if (notification == null) return;
      _localNotifications?.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _androidChannel.id,
            _androidChannel.name,
            channelDescription: _androidChannel.description,
            icon: '@mipmap/ic_launcher',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: jsonEncode(message.data),
      );
    });

    // Tap on a tray notification while backgrounded, or cold-start from one.
    FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _onNotificationTapFromData(message.data),
    );
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      _onNotificationTapFromData(initial.data);
    }

    // Re-register on token rotation (reuses the last known auth token).
    FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) => _onDeviceToken(token, _pendingAuthToken),
    );
  }

  Map<String, dynamic> _decodeData(String payload) {
    try {
      final decoded = jsonDecode(payload);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onDeviceToken':
        final token = call.arguments as String;
        await _onDeviceToken(token, _pendingAuthToken);
        break;
      case 'onNotificationTap':
        final payload = Map<String, dynamic>.from(call.arguments as Map);
        _onNotificationTap(payload);
        break;
    }
  }

  Future<bool> requestPermission(String? authToken) async {
    _pendingAuthToken = authToken;
    if (Platform.isAndroid) {
      return _requestAndroidPermission(authToken);
    }
    try {
      final granted = await _channel.invokeMethod<bool>('requestPermission');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyPermissionGranted, granted ?? false);
      return granted ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Android: requests the POST_NOTIFICATIONS runtime permission (Android 13+)
  /// via FCM, then fetches and registers the FCM token. Mirrors the iOS
  /// permission→token→backend flow but sourced from Firebase Messaging.
  Future<bool> _requestAndroidPermission(String? authToken) async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      final granted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyPermissionGranted, granted);
      if (granted) {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null && token.isNotEmpty) {
          await _onDeviceToken(token, authToken);
        }
      }
      return granted;
    } catch (e) {
      debugPrint('Android push permission/token failed: $e');
      return false;
    }
  }

  /// Returns null if never prompted, true if granted, false if denied.
  Future<bool?> getPermissionState() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_keyPermissionGranted)) return null;
    return prefs.getBool(_keyPermissionGranted);
  }

  Future<void> _onDeviceToken(String token, String? authToken) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDeviceToken, token);

    if (authToken == null || authToken.isEmpty) return;

    try {
      await _backendApiService.registerDeviceToken(
        identityToken: authToken,
        deviceToken: token,
        // The backend routes APNs vs FCM by this label (see ANDROID.md §G2).
        platform: Platform.isAndroid ? 'android' : 'ios',
      );
    } catch (e) {
      debugPrint('Failed to register device token: $e');
    }
  }

  Future<void> unregisterDeviceToken(String? authToken) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_keyDeviceToken);

    if (token == null || authToken == null || authToken.isEmpty) return;

    try {
      await _backendApiService.unregisterDeviceToken(
        identityToken: authToken,
        deviceToken: token,
      );
    } catch (e) {
      debugPrint('Failed to unregister device token: $e');
    }

    await prefs.remove(_keyDeviceToken);
    await prefs.remove(_keyPermissionGranted);
  }

  void _onNotificationTap(Map<String, dynamic> payload) {
    final type = payload['type'] as String?;

    final nested = payload['params'] is Map
        ? Map<String, dynamic>.from(payload['params'] as Map)
        : <String, dynamic>{};
    final params = <String, String>{};
    if (nested['raceId'] is String) {
      params['raceId'] = nested['raceId'] as String;
    }
    // Tournament pushes carry `tournamentId`; read defensively (older apps that
    // don't know the type fall through to a null route and just ignore it).
    if (nested['tournamentId'] is String) {
      params['tournamentId'] = nested['tournamentId'] as String;
    }

    final route = resolveRoute(type, params);
    if (route == null) return;

    pendingAction.value = NotificationAction(route: route, params: params);
  }

  /// Android/FCM equivalent of [_onNotificationTap]. FCM `data` values are all
  /// strings; `raceId` may be top-level or nested in a stringified `params`
  /// object (see backend G2). Reuses the same [_routeFromType] map.
  void _onNotificationTapFromData(Map<String, dynamic> data) {
    final type = data['type'] as String?;

    final params = <String, String>{};
    if (data['raceId'] is String) {
      params['raceId'] = data['raceId'] as String;
    }
    if (data['tournamentId'] is String) {
      params['tournamentId'] = data['tournamentId'] as String;
    }
    final rawParams = data['params'];
    if (rawParams is String && rawParams.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawParams);
        if (decoded is Map) {
          if (decoded['raceId'] is String) {
            params['raceId'] = decoded['raceId'] as String;
          }
          if (decoded['tournamentId'] is String) {
            params['tournamentId'] = decoded['tournamentId'] as String;
          }
        }
      } catch (_) {}
    }

    final route = resolveRoute(type, params);
    if (route == null) return;

    pendingAction.value = NotificationAction(route: route, params: params);
  }

  /// Resolves the final route for a push, given its already-extracted [params].
  /// Most types map straight through [routeFromType]; the tournament round/start
  /// pushes deep-link to the specific matchup race when one is carried
  /// (`raceId` present) and otherwise fall back to the bracket. Public for tests.
  @visibleForTesting
  NotificationRoute? resolveRoute(String? type, Map<String, String> params) {
    if ((type == 'TOURNAMENT_STARTED' || type == 'TOURNAMENT_ROUND_STARTED') &&
        params.containsKey('raceId')) {
      return NotificationRoute.raceDetail;
    }
    return routeFromType(type);
  }

  /// Maps a push `type` to an in-app deep-link route. Public for tests.
  @visibleForTesting
  NotificationRoute? routeFromType(String? type) {
    switch (type) {
      case 'RACE_INVITE_SENT':
      case 'RACE_INVITE_ACCEPTED':
      case 'RACE_STARTED':
      case 'RACE_COMPLETED':
      case 'POWERUP_USED':
      // Leech victim alert (item #2): "you're being leeched" opens the race so
      // the victim can react. The backend may tag it POWERUP_USED (shared
      // offensive path) or a dedicated LEECH_APPLIED — route both to the race.
      // Additive types; older apps fall through to null and just show the alert.
      case 'LEECH_APPLIED':
      case 'race_message':
      // Live placement change (Phase 0/3). Tapping the "you've been passed" alert
      // opens the race. Additive type — older apps fall through to default/null and
      // simply ignore it (the alert still shows; only deep-link routing is skipped).
      case 'PLACEMENT_CHANGED':
      // Team-race pushes (TR-681/683): lead flips and the gentle slacker
      // nudge both open the race. Additive types — older apps fall through
      // to default/null and just show the alert without deep-link routing.
      case 'TEAM_LEAD_CHANGE':
      case 'TEAM_SLACKER_NUDGE':
      case 'TEAM_FINAL_STRETCH':
      // One-time creator nudge when a scheduled team race can't auto-start
      // because the teams are uneven (TR-304) — opens the lobby to fix it.
      case 'TEAM_RACE_SCHEDULED_UNEVEN':
        return NotificationRoute.raceDetail;
      // Tournament pushes (spec §8). All land on the bracket by default;
      // TOURNAMENT_STARTED / TOURNAMENT_ROUND_STARTED are re-pointed at the
      // player's specific matchup race in [resolveRoute] when a raceId rides
      // the params. Additive types — older apps fall through to null and just
      // show the alert without deep-link routing (the #1 rule).
      case 'TOURNAMENT_INVITE_SENT':
      case 'TOURNAMENT_STARTED':
      case 'TOURNAMENT_ROUND_STARTED':
      case 'TOURNAMENT_MATCHUP_WON':
      case 'TOURNAMENT_ELIMINATED':
      case 'TOURNAMENT_CHAMPION':
      case 'TOURNAMENT_COMPLETED':
      case 'TOURNAMENT_CANCELLED':
        return NotificationRoute.tournamentDetail;
      case 'RACE_CANCELLED':
        return NotificationRoute.races;
      case 'FRIEND_REQUEST_SENT':
      case 'FRIEND_REQUEST_ACCEPTED':
        return NotificationRoute.friends;
      // Global step-multiplier event start — land on home (the event applies to
      // all the user's active races, not one in particular). Additive type;
      // older apps fall through to the default and ignore it.
      case 'GLOBAL_EVENT_STARTED':
        return NotificationRoute.home;
      // Referral payout — a referred friend finished their first race and the
      // referrer earned coins. Land on home (where the referral dashboard /
      // balance live). Additive type: older apps fall through to default/null,
      // so the alert still shows but tapping it doesn't navigate.
      case 'REFERRAL_REWARDED':
        return NotificationRoute.home;
      // Legacy challenge notifications still in user trays land on home.
      case 'CHALLENGE_INITIATED':
      case 'CHALLENGE_DROPPED':
      case 'STAKE_ACCEPTED':
        return NotificationRoute.home;
      default:
        return null;
    }
  }
}
