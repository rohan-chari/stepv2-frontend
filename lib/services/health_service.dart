import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/step_data.dart';
import '../models/step_sample_data.dart';

class HealthService {
  HealthService({Health? health}) : _health = health ?? Health();

  final Health _health;

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
    final stepData = await getStepsForDateRange(
      startDate: DateTime(now.year, now.month, now.day),
      endDate: now,
    );

    return stepData.last;
  }

  Future<List<StepData>> getStepsForDateRange({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final normalizedStartDate = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
    );
    final normalizedEndDate = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
    );
    final entries = <StepData>[];
    var currentDate = normalizedStartDate;

    while (!currentDate.isAfter(normalizedEndDate)) {
      final isCurrentDay =
          currentDate.year == normalizedEndDate.year &&
          currentDate.month == normalizedEndDate.month &&
          currentDate.day == normalizedEndDate.day;
      final intervalEnd = isCurrentDay
          ? endDate
          : currentDate.add(const Duration(days: 1));
      final steps = await _health.getTotalStepsInInterval(
        currentDate,
        intervalEnd,
        includeManualEntry: false,
      );

      entries.add(StepData(steps: steps ?? 0, date: currentDate));

      currentDate = currentDate.add(const Duration(days: 1));
    }

    return entries;
  }

  Future<List<StepSampleData>> getHourlySteps({
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    // Bucket per hour and ask HealthKit for the aggregated total in each
    // bucket. getTotalStepsInInterval is backed by HKStatisticsQuery with
    // cumulativeSum, which dedupes across sources (iPhone + Watch + Oura +
    // Garmin all reporting the same walk count once, not N times).
    final samples = <StepSampleData>[];
    var bucketStart = DateTime(
      startTime.year,
      startTime.month,
      startTime.day,
      startTime.hour,
    );
    if (bucketStart.isBefore(startTime)) {
      bucketStart = startTime;
    }

    while (bucketStart.isBefore(endTime)) {
      final nextHour = DateTime(
        bucketStart.year,
        bucketStart.month,
        bucketStart.day,
        bucketStart.hour,
      ).add(const Duration(hours: 1));
      final bucketEnd = nextHour.isBefore(endTime) ? nextHour : endTime;

      final steps = await _health.getTotalStepsInInterval(
        bucketStart,
        bucketEnd,
        includeManualEntry: false,
      );

      if (steps != null && steps > 0) {
        samples.add(
          StepSampleData(
            periodStart: bucketStart.toUtc(),
            periodEnd: bucketEnd.toUtc(),
            steps: steps,
          ),
        );
      }

      bucketStart = bucketEnd;
    }

    return samples;
  }
}
