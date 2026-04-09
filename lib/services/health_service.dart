import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/challenge_sync_day.dart';
import '../models/step_data.dart';
import '../models/step_sample_data.dart';

class HealthService {
  HealthService({Health? health}) : _health = health ?? Health();

  final Health _health;

  static const _keyHealthAuthorized = 'health_authorized';

  bool _authorized = false;
  bool get isAuthorized => _authorized;

  String? _nonEmptyString(String? value) {
    if (value == null || value.isEmpty) return null;
    return value;
  }

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

  Future<List<StepData>> getStepsForSyncDays({
    required List<ChallengeSyncDay> syncDays,
  }) async {
    final entries = <StepData>[];

    for (final syncDay in syncDays) {
      final steps = await _health.getTotalStepsInInterval(
        syncDay.startsAt,
        syncDay.endsAt,
        includeManualEntry: false,
      );

      entries.add(StepData(steps: steps ?? 0, date: syncDay.date));
    }

    return entries;
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
    final dataPoints = await _health.getHealthDataFromTypes(
      types: [HealthDataType.STEPS],
      startTime: startTime,
      endTime: endTime,
      recordingMethodsToFilter: const [RecordingMethod.manual],
    );

    // Remove duplicates (e.g. from multiple sources like Apple Watch + iPhone)
    final unique = _health.removeDuplicates(dataPoints);

    return unique
        .where(
          (dp) =>
              dp.value is NumericHealthValue &&
              (dp.value as NumericHealthValue).numericValue > 0,
        )
        .map(
          (dp) => StepSampleData(
            periodStart: dp.dateFrom.toUtc(),
            periodEnd: dp.dateTo.toUtc(),
            steps: (dp.value as NumericHealthValue).numericValue.toInt(),
            sourceName: _nonEmptyString(dp.sourceName),
            sourceId: _nonEmptyString(dp.sourceId),
            sourceDeviceId: _nonEmptyString(dp.sourceDeviceId),
            deviceModel: _nonEmptyString(dp.deviceModel),
            recordingMethod: dp.recordingMethod.name,
            metadata: dp.metadata == null
                ? null
                : Map<String, dynamic>.from(dp.metadata!),
          ),
        )
        .toList();
  }
}
