import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/backend_config.dart';

class BackgroundSyncBootstrapService {
  BackgroundSyncBootstrapService();

  static const channel = MethodChannel('com.steptracker/background_sync');
  static const backendBaseUrlKey = 'background_sync_backend_base_url';
  static const iosPendingV2Key = 'ios_background_sync_v2_pending';
  static const iosPendingLegacyKey = 'ios_background_sync_legacy_pending';
  static const iosNegativeCapabilityKey =
      'ios_background_sync_negative_capability';
  static const androidPendingV2Key = 'android_background_sync_v2_pending';
  static const androidPendingLegacyKey =
      'android_background_sync_legacy_pending';
  static const androidNegativeCapabilityKey =
      'android_background_sync_negative_capability';

  static const nativeRecoveryKeys = <String>[
    iosPendingV2Key,
    iosPendingLegacyKey,
    iosNegativeCapabilityKey,
    androidPendingV2Key,
    androidPendingLegacyKey,
    androidNegativeCapabilityKey,
  ];

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
