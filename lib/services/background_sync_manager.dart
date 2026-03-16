import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:workmanager/workmanager.dart';

class BackgroundSyncManager {
  static const Duration syncInterval = Duration(hours: 1);
  static const String taskIdentifier =
      'com.rohanchari.steptracker.periodicStepSync';
  static const String taskName = 'backgroundStepSync';

  static Future<bool> scheduleNextSync() async {
    try {
      await Workmanager().registerOneOffTask(
        taskIdentifier,
        taskName,
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingWorkPolicy.keep,
        initialDelay: syncInterval,
      );
      return true;
    } on PlatformException catch (error) {
      debugPrint('Background sync scheduling failed: ${error.message}');
      return false;
    }
  }

  static Future<void> cancelAllSync() async {
    await Workmanager().cancelByUniqueName(taskIdentifier);
  }
}
