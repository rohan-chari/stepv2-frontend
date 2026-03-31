import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend_api_service.dart';

enum NotificationRoute { home, friends, challengeDetail, raceDetail, races }

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

  final BackendApiService _backendApiService;
  final ValueNotifier<NotificationAction?> pendingAction = ValueNotifier(null);

  String? _pendingAuthToken;

  Future<void> initialize() async {
    _channel.setMethodCallHandler(_handleMethodCall);
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
    try {
      final granted = await _channel.invokeMethod<bool>('requestPermission');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyPermissionGranted, granted ?? false);
      return granted ?? false;
    } on PlatformException {
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
        platform: 'ios',
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
    final route = _routeFromType(type);
    if (route == null) return;

    final nested = payload['params'] is Map
        ? Map<String, dynamic>.from(payload['params'] as Map)
        : <String, dynamic>{};
    final params = <String, String>{};
    if (nested['instanceId'] is String) {
      params['challengeInstanceId'] = nested['instanceId'] as String;
    }
    if (nested['raceId'] is String) {
      params['raceId'] = nested['raceId'] as String;
    }

    pendingAction.value = NotificationAction(route: route, params: params);
  }

  NotificationRoute? _routeFromType(String? type) {
    switch (type) {
      case 'CHALLENGE_INITIATED':
        return NotificationRoute.challengeDetail;
      case 'RACE_INVITE_SENT':
      case 'RACE_INVITE_ACCEPTED':
      case 'RACE_STARTED':
      case 'RACE_COMPLETED':
      case 'POWERUP_USED':
        return NotificationRoute.raceDetail;
      case 'RACE_CANCELLED':
        return NotificationRoute.races;
      case 'FRIEND_REQUEST_SENT':
      case 'FRIEND_REQUEST_ACCEPTED':
        return NotificationRoute.friends;
      case 'STAKE_ACCEPTED':
        return NotificationRoute.challengeDetail;
      case 'CHALLENGE_DROPPED':
        return NotificationRoute.home;
      default:
        return null;
    }
  }
}
