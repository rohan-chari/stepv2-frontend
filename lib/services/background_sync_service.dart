import 'dart:convert';
import 'dart:io';

import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../config/backend_config.dart';
import 'background_sync_manager.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName == BackgroundSyncManager.taskName) {
      final result = await _performBackgroundSync();
      // Keep the next one-off sync queued because iOS does not expose strict
      // periodic scheduling through the installed workmanager plugin.
      await BackgroundSyncManager.scheduleNextSync();
      return result;
    }
    return true;
  });
}

Future<bool> _performBackgroundSync() async {
  try {
    final prefs = await SharedPreferences.getInstance();

    // Check for session token
    final sessionToken = prefs.getString('auth_session_token');
    if (sessionToken == null || sessionToken.isEmpty) {
      return true; // Nothing to do — not signed in
    }

    // Check health authorization
    final healthAuthorized = prefs.getBool('health_authorized') ?? false;
    if (!healthAuthorized) {
      return true; // Not authorized to read health data
    }

    // Fetch today's steps
    final health = Health();
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    final steps = await health.getTotalStepsInInterval(midnight, now);

    if (steps == null) {
      return true; // No step data available
    }

    // Format date
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final date = '${now.year}-$month-$day';

    // POST to /steps
    final client = HttpClient();
    try {
      final request = await client.openUrl(
        'POST',
        Uri.parse('${BackendConfig.baseUrl}/steps'),
      );
      request.headers.contentType = ContentType.json;
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $sessionToken',
      );
      request.write(jsonEncode({'steps': steps, 'date': date}));

      final response = await request.close();

      if (response.statusCode == 401) {
        return true; // Token expired — don't retry
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true; // Success
      }

      return false; // Server error — retry with backoff
    } finally {
      client.close();
    }
  } on SocketException {
    return false; // Network error — retry with backoff
  } catch (_) {
    return true; // Unknown error — don't retry
  }
}
