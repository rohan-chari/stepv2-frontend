import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/backend_config.dart';

class BackgroundSyncBootstrapService {
  BackgroundSyncBootstrapService();

  static const channel = MethodChannel('com.steptracker/background_sync');
  static const backendBaseUrlKey = 'background_sync_backend_base_url';

  Future<void> persistBackendBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(backendBaseUrlKey, BackendConfig.baseUrl);
  }

  Future<void> enableHealthKitBackgroundDelivery() async {
    try {
      await channel.invokeMethod('enableHealthKitBackgroundDelivery');
    } on PlatformException {
      // Ignore in tests and non-iOS contexts.
    }
  }
}
