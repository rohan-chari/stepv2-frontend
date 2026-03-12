import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/step_data.dart';

class HealthService {
  final Health _health = Health();

  static const _keyHealthAuthorized = 'health_authorized';

  bool _authorized = false;
  bool get isAuthorized => _authorized;

  /// Loads persisted health auth state. Returns true if previously authorized.
  Future<bool> restoreHealthAuthState() async {
    final prefs = await SharedPreferences.getInstance();
    _authorized = prefs.getBool(_keyHealthAuthorized) ?? false;
    return _authorized;
  }

  Future<bool> requestAuthorization() async {
    final types = [HealthDataType.STEPS];
    final permissions = [HealthDataAccess.READ];

    bool requested = await _health.requestAuthorization(
      types,
      permissions: permissions,
    );

    if (!requested) return false;

    // Persist that the user has gone through the authorization flow.
    // Note: iOS always returns true here regardless of what the user chose,
    // and hides read-permission status for privacy. We cannot detect revocation.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHealthAuthorized, true);
    _authorized = true;
    return true;
  }

  Future<StepData> getStepsToday() async {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);

    final steps = await _health.getTotalStepsInInterval(midnight, now);

    return StepData(
      steps: steps ?? 0,
      date: now,
    );
  }
}
