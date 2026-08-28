import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_app_installations/firebase_app_installations.dart';
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

enum NotificationRoute {
  home,
  friends,
  raceDetail,
  races,
  tournamentDetail,
  dailyReward,
}

class NotificationAction {
  final NotificationRoute route;
  final Map<String, String> params;

  const NotificationAction({required this.route, this.params = const {}});
}

class NotificationService {
  NotificationService({
    BackendApiService? backendApiService,
    bool? isIosForTesting,
    bool? isAndroidForTesting,
    Future<String?> Function()? androidTokenProvider,
    Future<String?> Function()? installationIdProvider,
  }) : _backendApiService = backendApiService ?? BackendApiService(),
       _isIos = isIosForTesting ?? Platform.isIOS,
       _isAndroid =
           isAndroidForTesting ??
           (isIosForTesting == false ? true : Platform.isAndroid),
       _androidTokenProvider = androidTokenProvider,
       _installationIdProvider = installationIdProvider;

  static const _channel = MethodChannel('com.steptracker/notifications');
  static const _keyDeviceToken = 'notif_device_token';
  static const _keyPermissionGranted = 'notif_permission_granted';
  static const _keyLastRegisterError = 'notif_last_register_error';
  static const _keyPendingOpenReceipts = 'admin_metrics_notification_opens_v1';
  static const _maxPendingOpenReceipts = 20;

  // Android-only foreground display channel for FCM. Mirrors a typical
  // high-importance channel; ignored on iOS.
  static const _androidChannel = AndroidNotificationChannel(
    'bara_default',
    'Notifications',
    description: 'Race, friend, and reward notifications',
    importance: Importance.high,
  );

  final BackendApiService _backendApiService;
  final bool _isIos;
  final bool _isAndroid;
  final Future<String?> Function()? _androidTokenProvider;
  final Future<String?> Function()? _installationIdProvider;
  final ValueNotifier<NotificationAction?> pendingAction = ValueNotifier(null);

  String? _pendingAuthToken;
  String? _currentDeviceToken;
  String? _currentInstallationId;
  String? _installationV2AuthToken;
  int _notificationAccountGeneration = 0;
  Future<void> _notificationMutationTail = Future<void>.value();
  String? _pendingUserId;
  int _openReceiptAccountGeneration = 0;
  Future<void>? _openReceiptFlushInFlight;
  FlutterLocalNotificationsPlugin? _localNotifications;

  Future<void> initialize() async {
    // Migration cleanup only. APNs/FCM tokens are OS-owned and may rotate, so
    // a persisted token is never treated as current or reposted.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyDeviceToken);
    } catch (_) {
      // Local preference failure cannot block notification initialization.
    }
    // iOS device token + tap routing flow over the native APNs bridge.
    _channel.setMethodCallHandler(_handleMethodCall);
    // Android uses FCM instead; iOS never touches Firebase.
    if (_isAndroid) {
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
        _backgroundSyncChannel
            .invokeMethod('enqueueExpeditedSync')
            .catchError((_) {});
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
        final token = call.arguments;
        if (token is String && token.isNotEmpty) {
          await _onDeviceToken(token, _pendingAuthToken);
        }
        break;
      case 'onDeviceTokenError':
        // A failed current registration callback means no APNs token is known
        // to be current. Keep only installation identity for a capability-
        // gated same-session logout.
        _currentDeviceToken = null;
        // APNs registration failed natively. Persist the reason so the next
        // ensureTokenRegistered() can surface it to analytics instead of the
        // failure staying invisible (this is how a user silently loses ALL
        // pushes for months).
        final message = call.arguments is String
            ? call.arguments as String
            : 'unknown';
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyLastRegisterError, message);
        break;
      case 'onNotificationTap':
        final arguments = call.arguments;
        final payload = arguments is Map
            ? <String, dynamic>{
                for (final entry in arguments.entries)
                  if (entry.key is String) entry.key as String: entry.value,
              }
            : <String, dynamic>{};
        _handleIosNotificationTap(payload);
        break;
    }
  }

  Future<bool> requestPermission(String? authToken) async {
    _setPendingAuthToken(authToken);
    if (_isAndroid) {
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
        final token = await _getAndroidToken();
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
  ///
  /// This is the CACHED (SharedPreferences) answer, kept for opt-in-screen
  /// gating. It can be stale — wiped by sign-out or a reinstall while the OS
  /// permission lives on, or `true` from a previous install whose OS
  /// permission no longer exists. For anything that decides whether pushes
  /// actually work, use [getSystemPermissionState].
  Future<bool?> getPermissionState() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_keyPermissionGranted)) return null;
    return prefs.getBool(_keyPermissionGranted);
  }

  /// The REAL OS-level permission: true if authorized (incl. provisional),
  /// false if denied, null if never determined. Falls back to the cached
  /// value if the platform query fails.
  Future<bool?> getSystemPermissionState() async {
    try {
      if (_isAndroid) {
        final settings = await FirebaseMessaging.instance
            .getNotificationSettings();
        switch (settings.authorizationStatus) {
          case AuthorizationStatus.authorized:
          case AuthorizationStatus.provisional:
            return true;
          case AuthorizationStatus.denied:
            return false;
          case AuthorizationStatus.notDetermined:
            return null;
        }
      }
      final status = await _channel.invokeMethod<String>('getPermissionStatus');
      switch (status) {
        case 'authorized':
        case 'provisional':
        case 'ephemeral':
          return true;
        case 'denied':
          return false;
        case 'notDetermined':
          return null;
      }
    } catch (_) {
      // Fall through to the cached answer.
    }
    return getPermissionState();
  }

  /// Drops the cached permission flag (NOT the OS permission). Called when the
  /// cache is provably stale — e.g. it says granted but the OS says the user
  /// was never even asked (reinstall) — so the opt-in flow can run again.
  Future<void> clearCachedPermission() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPermissionGranted);
  }

  /// Re-registers the push token with the backend. Call every session when the
  /// OS permission is granted: tokens rotate (reinstall, restore, new phone)
  /// and a registration that failed once used to fail silently forever.
  ///
  /// iOS: asks the OS to re-deliver the APNs token and uploads only the token
  /// supplied by that current callback. A persisted token is never reposted.
  /// Android: fetches the FCM token and posts it directly.
  ///
  /// Returns a short outcome label for activation analytics.
  Future<String> ensureTokenRegistered(String? authToken) async {
    _setPendingAuthToken(authToken);
    if (authToken == null || authToken.isEmpty) return 'no_auth';
    final prefs = await SharedPreferences.getInstance();
    // Remove the legacy cache even when this service was created before the
    // migration cleanup in initialize() completed.
    await prefs.remove(_keyDeviceToken);
    // The OS said granted — keep the cached flag in agreement so the settings
    // toggle and opt-in gating don't contradict reality.
    await prefs.setBool(_keyPermissionGranted, true);
    try {
      if (_isAndroid) {
        final token = await _getAndroidToken();
        if (token == null || token.isEmpty) return 'no_token';
        final registered = await _onDeviceToken(token, authToken);
        return registered ? 'registered' : 'failed:registration';
      }
      // The fresh token arrives asynchronously via onDeviceToken. Never fill
      // this gap with a token persisted by an earlier launch.
      final started = await _channel.invokeMethod<bool>(
        'registerForRemoteNotifications',
      );
      final lastError = prefs.getString(_keyLastRegisterError);
      if (lastError != null && lastError.isNotEmpty) {
        return 'register_failed:$lastError';
      }
      return started == true
          ? 'registration_requested'
          : 'registration_not_started';
    } catch (e) {
      return 'failed:${e.runtimeType}';
    }
  }

  Future<String?> _getAndroidToken() {
    final provider = _androidTokenProvider;
    return provider != null
        ? provider()
        : FirebaseMessaging.instance.getToken();
  }

  Future<String?> _getInstallationId() async {
    try {
      final provider = _installationIdProvider;
      final value = provider != null
          ? await provider()
          : _isAndroid
          ? await FirebaseInstallations.instance.getId()
          : await _channel.invokeMethod<String>(
              'getNotificationInstallationId',
            );
      if (value == null ||
          value.isEmpty ||
          value.length > 128 ||
          !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value)) {
        return null;
      }
      _currentInstallationId = value;
      return value;
    } catch (error) {
      debugPrint(
        'Notification installation ID unavailable: ${error.runtimeType}',
      );
      return null;
    }
  }

  Future<bool> _onDeviceToken(String token, String? authToken) async {
    final accountGeneration = _notificationAccountGeneration;
    _currentDeviceToken = token;
    final prefs = await SharedPreferences.getInstance();
    // The OS handed us a token, so any stored registration error is stale.
    await prefs.remove(_keyLastRegisterError);

    if (authToken == null || authToken.isEmpty) return false;

    final installationId = await _getInstallationId();
    // Logout or account switching may have happened while secure/Firebase
    // identity lookup was in flight. Never register against a stale session.
    if (!_isCurrentNotificationAccount(authToken, accountGeneration)) {
      return false;
    }

    return _enqueueNotificationMutation(() async {
      // The account can change while this registration waits behind an older
      // notification mutation. Skip it if no request has started yet.
      if (!_isCurrentNotificationAccount(authToken, accountGeneration)) {
        return false;
      }
      try {
        final result = await _backendApiService.registerDeviceToken(
          identityToken: authToken,
          deviceToken: token,
          // The backend routes APNs vs FCM by this label (see ANDROID.md §G2).
          platform: _isAndroid ? 'android' : 'ios',
          installationId: installationId,
        );
        // A POST can reach the backend before logout/account switching changes
        // the local session, yet return after that session's DELETE. Compensate
        // inside this serialized mutation. Any newer registration waits behind
        // the cleanup, so re-login to the same account also finishes correctly.
        if (!_isCurrentNotificationAccount(authToken, accountGeneration)) {
          await _unregisterStaleRegistration(
            authToken: authToken,
            deviceToken: token,
            installationId: installationId,
          );
          return false;
        }
        _installationV2AuthToken =
            result.registrationVersion >= 2 && result.installationAccepted
            ? authToken
            : null;
        return true;
      } catch (e) {
        if (!_isCurrentNotificationAccount(authToken, accountGeneration)) {
          await _unregisterStaleRegistration(
            authToken: authToken,
            deviceToken: token,
            installationId: installationId,
          );
        }
        debugPrint('Failed to register device token: $e');
        return false;
      }
    });
  }

  bool _isCurrentNotificationAccount(String authToken, int generation) =>
      _pendingAuthToken == authToken &&
      _notificationAccountGeneration == generation;

  Future<void> _unregisterStaleRegistration({
    required String authToken,
    required String deviceToken,
    required String? installationId,
  }) async {
    try {
      await _backendApiService.unregisterDeviceToken(
        identityToken: authToken,
        deviceToken: deviceToken,
        installationId: installationId,
      );
    } catch (error) {
      debugPrint(
        'Failed to compensate stale notification registration: '
        '${error.runtimeType}',
      );
    }
  }

  Future<T> _enqueueNotificationMutation<T>(Future<T> Function() mutation) {
    final completer = Completer<T>();
    _notificationMutationTail = _notificationMutationTail.then((_) async {
      try {
        completer.complete(await mutation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> unregisterDeviceToken(String? authToken) async {
    final prefsFuture = SharedPreferences.getInstance();
    final token = _currentDeviceToken;
    final supportsInstallationDelete =
        authToken != null && _installationV2AuthToken == authToken;

    // Clear session state before installation lookup or network I/O so a
    // concurrent APNs callback or FCM refresh cannot re-register the account
    // being logged out.
    _setPendingAuthToken(null);
    _currentDeviceToken = null;
    final remoteCleanup = _enqueueNotificationMutation(() async {
      final installationId =
          _currentInstallationId ?? await _getInstallationId();

      if (authToken != null && authToken.isNotEmpty) {
        final canDeleteByToken = token != null && token.isNotEmpty;
        final canDeleteByInstallation =
            installationId != null && installationId.isNotEmpty;
        if (canDeleteByToken ||
            (supportsInstallationDelete && canDeleteByInstallation)) {
          try {
            await _backendApiService.unregisterDeviceToken(
              identityToken: authToken,
              deviceToken: canDeleteByToken ? token : null,
              installationId: canDeleteByInstallation ? installationId : null,
            );
          } catch (e) {
            debugPrint('Failed to unregister device token: $e');
          }
        }
      }
    });

    final prefs = await prefsFuture;
    await remoteCleanup;
    await prefs.remove(_keyDeviceToken);
    await prefs.remove(_keyPermissionGranted);
  }

  void _setPendingAuthToken(String? authToken) {
    if (_pendingAuthToken != authToken) {
      _installationV2AuthToken = null;
      _notificationAccountGeneration++;
    }
    _pendingAuthToken = authToken;
  }

  void _handleIosNotificationTap(Map<String, dynamic> payload) {
    // Route synchronously. Analytics persistence and network work are guarded
    // best effort, so even a local-storage failure can never swallow a tap.
    _routeIosNotificationTap(payload);
    unawaited(_persistAndFlushOpenReceipt(payload['notificationId']));
  }

  @visibleForTesting
  Future<void> handleNotificationTapForTesting(
    Map<String, dynamic> payload,
  ) async {
    if (!_isIos) {
      _onNotificationTapFromData(payload);
      return;
    }
    _routeIosNotificationTap(payload);
    await _persistAndFlushOpenReceipt(payload['notificationId']);
  }

  Future<void> _persistAndFlushOpenReceipt(Object? notificationId) async {
    try {
      await _queueOpenReceipt(notificationId, ownerUserId: _pendingUserId);
      await flushPendingOpenReceipts(_pendingAuthToken, userId: _pendingUserId);
    } catch (_) {
      // Navigation has already happened; analytics can be lost safely.
    }
  }

  void _routeIosNotificationTap(Map<String, dynamic> payload) {
    final typeValue = payload['type'];
    final type = typeValue is String ? typeValue : null;

    final params = _normalizedTapParams(payload);

    final route = resolveRoute(type, params);
    if (route == null) return;

    pendingAction.value = NotificationAction(route: route, params: params);
  }

  /// Android/FCM equivalent of [_onNotificationTap]. FCM `data` values are all
  /// strings; `raceId` may be top-level or nested in a stringified `params`
  /// object (see backend G2). Reuses the same [_routeFromType] map.
  void _onNotificationTapFromData(Map<String, dynamic> data) {
    final rawType = data['type'];
    final type = rawType is String ? rawType : null;

    final params = _normalizedTapParams(data);

    final route = resolveRoute(type, params);
    if (route == null) return;

    pendingAction.value = NotificationAction(route: route, params: params);
  }

  Map<String, String> _normalizedTapParams(Map<String, dynamic> payload) {
    final params = <String, String>{};

    void copyKnown(Map<dynamic, dynamic> source) {
      for (final key in const ['raceId', 'tournamentId']) {
        final raw = source[key];
        if (raw is String && raw.trim().isNotEmpty) {
          params[key] = raw.trim();
        }
      }
    }

    // Legacy provider payloads carried IDs at the top level.
    copyKnown(payload);
    final rawNested = payload['params'];
    if (rawNested is Map) {
      copyKnown(rawNested);
    } else if (rawNested is String && rawNested.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawNested);
        if (decoded is Map) copyKnown(decoded);
      } catch (_) {
        // A malformed nested value cannot prevent a compatible top-level ID
        // from routing, and never throws into notification initialization.
      }
    }
    return params;
  }

  Future<void> _queueOpenReceipt(
    Object? rawId, {
    required String? ownerUserId,
  }) async {
    if (!_isIos || rawId is! String || rawId.isEmpty || rawId.length > 128) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final queue = _readOpenReceiptQueue(prefs);
    final existing = queue.indexWhere((row) => row['notificationId'] == rawId);
    if (existing < 0) {
      queue.add({
        'notificationId': rawId,
        if (ownerUserId != null && ownerUserId.isNotEmpty)
          'ownerUserId': ownerUserId,
      });
    } else if (ownerUserId != null &&
        ownerUserId.isNotEmpty &&
        queue[existing]['ownerUserId'] == null) {
      queue[existing]['ownerUserId'] = ownerUserId;
    }
    if (queue.length > _maxPendingOpenReceipts) {
      queue.removeRange(0, queue.length - _maxPendingOpenReceipts);
    }
    await prefs.setString(_keyPendingOpenReceipts, jsonEncode(queue));
  }

  /// Flushes cold-start taps after authentication. Calls coalesce and old
  /// 404/405 endpoints are treated as permanent best-effort loss.
  Future<void> flushPendingOpenReceipts(
    String? authToken, {
    String? userId,
  }) async {
    _setPendingAuthToken(authToken);
    if (!_isIos) return;
    if (authToken == null ||
        authToken.isEmpty ||
        userId == null ||
        userId.isEmpty) {
      if (_pendingUserId != null) {
        _pendingUserId = null;
        _openReceiptAccountGeneration++;
      }
      return;
    }
    if (_pendingUserId != userId) {
      _pendingUserId = userId;
      _openReceiptAccountGeneration++;
    }
    final running = _openReceiptFlushInFlight;
    if (running != null) {
      await running;
      return flushPendingOpenReceipts(authToken, userId: userId);
    }
    final generation = _openReceiptAccountGeneration;
    late final Future<void> tracked;
    tracked =
        _flushPendingOpenReceipts(
          authToken,
          userId: userId,
          generation: generation,
        ).whenComplete(() {
          if (identical(_openReceiptFlushInFlight, tracked)) {
            _openReceiptFlushInFlight = null;
          }
        });
    _openReceiptFlushInFlight = tracked;
    await tracked;
  }

  Future<void> _flushPendingOpenReceipts(
    String authToken, {
    required String userId,
    required int generation,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    while (true) {
      final queue = _readOpenReceiptQueue(prefs);
      if (generation != _openReceiptAccountGeneration) return;
      for (final row in queue) {
        if (row['ownerUserId'] == null) row['ownerUserId'] = userId;
      }
      queue.removeWhere((row) => row['ownerUserId'] != userId);
      await prefs.setString(_keyPendingOpenReceipts, jsonEncode(queue));
      if (queue.isEmpty) return;
      final id = queue.first['notificationId'];
      if (id == null || id.isEmpty) {
        queue.removeAt(0);
        await prefs.setString(_keyPendingOpenReceipts, jsonEncode(queue));
        continue;
      }
      try {
        await _backendApiService.sendAdminMetricsNotificationOpen(
          identityToken: authToken,
          notificationId: id,
        );
        if (generation != _openReceiptAccountGeneration) return;
        final current = _readOpenReceiptQueue(prefs)
          ..removeWhere(
            (row) =>
                row['notificationId'] == id && row['ownerUserId'] == userId,
          );
        await prefs.setString(_keyPendingOpenReceipts, jsonEncode(current));
      } on ApiException catch (error) {
        if (generation != _openReceiptAccountGeneration) return;
        if (error.statusCode == 404 || error.statusCode == 405) {
          final current = _readOpenReceiptQueue(prefs)
            ..removeWhere((row) => row['ownerUserId'] == userId);
          await prefs.setString(_keyPendingOpenReceipts, jsonEncode(current));
        } else if (error.statusCode == 400) {
          // A malformed or permanently expired opaque id must not block later
          // valid receipts in the bounded FIFO.
          final current = _readOpenReceiptQueue(prefs)
            ..removeWhere(
              (row) =>
                  row['notificationId'] == id && row['ownerUserId'] == userId,
            );
          await prefs.setString(_keyPendingOpenReceipts, jsonEncode(current));
          continue;
        }
        return;
      } catch (_) {
        return;
      }
    }
  }

  List<Map<String, String>> _readOpenReceiptQueue(SharedPreferences prefs) {
    final raw = prefs.getString(_keyPendingOpenReceipts);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final queue = <Map<String, String>>[];
      for (final item in decoded) {
        // Migrate the previous on-device string list as unowned. The next
        // authenticated flush binds those receipts before any network send.
        if (item is String && item.isNotEmpty) {
          queue.add({'notificationId': item});
          continue;
        }
        if (item is! Map) continue;
        final id = item['notificationId'];
        final owner = item['ownerUserId'];
        if (id is! String || id.isEmpty) continue;
        queue.add({
          'notificationId': id,
          if (owner is String && owner.isNotEmpty) 'ownerUserId': owner,
        });
      }
      return queue;
    } catch (_) {
      return [];
    }
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
      // Both spellings route, forever. The backend historically sent
      // TEAM_LEAD_CHANGED while every shipped client matched the D-less
      // string, so the alert showed but the tap went nowhere. Accepting both
      // makes the two deploys order-independent and survives any future
      // re-flip of the spelling.
      case 'TEAM_LEAD_CHANGE':
      case 'TEAM_LEAD_CHANGED':
      case 'TEAM_SLACKER_NUDGE':
      case 'TEAM_FINAL_STRETCH':
      // One-time creator nudge when a scheduled team race can't auto-start
      // because the teams are uneven (TR-304) — opens the lobby to fix it.
      case 'TEAM_RACE_SCHEDULED_UNEVEN':
      // Race-ending-soon reminder (spec §8): a ~2h-out "final push" nudge on a
      // timed race. Opens the race so the user can react. Additive type —
      // older apps fall through to null and just show the alert. raceId rides
      // in params, so [resolveRoute]'s param extraction already deep-links it.
      case 'RACE_ENDING_SOON':
        return NotificationRoute.raceDetail;
      // Daily-reward reminders (spec §7): the 5 PM and 9 PM nudges both open
      // the daily-reward screen. No params. Additive types — older apps fall
      // through to null and just show the alert without deep-linking.
      case 'DAILY_REWARD_REMINDER_17':
      case 'DAILY_REWARD_REMINDER_21':
        return NotificationRoute.dailyReward;
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
