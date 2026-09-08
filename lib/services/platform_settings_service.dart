import 'package:flutter/services.dart';

/// Opens native settings actions, not ACTION_VIEW URLs containing intent text.
class PlatformSettingsService {
  static const channel = MethodChannel('com.steptracker/settings');

  Future<bool> openHealthSettings() => _open('openHealthSettings');
  Future<bool> openNotificationSettings() => _open('openNotificationSettings');

  Future<bool> _open(String method) async {
    try {
      return await channel.invokeMethod<bool>(method) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
