import 'dart:io' show Platform;

import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/step_data.dart';
import '../models/step_sample_data.dart';

/// Outcome of [HealthService.setUpHealthAccess]. [needsHealthConnect] is
/// Android-only: Health Connect isn't installed/updated, and the user has been
/// sent to the Play Store — the caller should ask them to retry.
enum HealthSetupResult { authorized, denied, needsHealthConnect }

class HealthService {
  HealthService({Health? health}) : _health = health ?? Health();

  final Health _health;

  static const _keyHealthAuthorized = 'health_authorized';

  /// Whether to include manually-entered steps in [getTotalStepsInInterval].
  ///
  /// Platform-critical, NOT cosmetic — and intentionally keyed on `isAndroid`
  /// (not `!isIOS`): the only platforms that are neither iOS nor Android are the
  /// host test runner and web, where this should keep the iOS-style `false`.
  ///
  /// iOS: the call is HKStatisticsQuery/cumulativeSum, which de-duplicates across
  /// sources even with manual entries excluded — so we exclude them (`false`).
  ///
  /// Android: the `health` plugin uses Health Connect's de-duplicated
  /// `aggregate()` (StepsRecord.COUNT_TOTAL) ONLY when no recording method is
  /// filtered. Passing `false` flips it to a raw `readRecords` + plain sum across
  /// ALL step-writing apps with NO cross-source dedup, double-counting phone +
  /// watch (or Google Fit + Samsung Health). So on Android we pass `true` to stay
  /// on the aggregate path. See ANDROID.md §C-5.
  bool get _includeManualEntry => Platform.isAndroid;

  bool _authorized = false;
  bool get isAuthorized => _authorized;

  /// Loads persisted health auth state. Returns true if previously authorized.
  Future<bool> restoreHealthAuthState() async {
    final prefs = await SharedPreferences.getInstance();
    _authorized = prefs.getBool(_keyHealthAuthorized) ?? false;
    return _authorized;
  }

  /// Ensures the platform health store is ready, then requests READ access to
  /// steps. On iOS this is just [requestAuthorization]. On Android it first
  /// verifies Health Connect is installed/updated — if not, it sends the user to
  /// the Play Store (via the plugin) and returns
  /// [HealthSetupResult.needsHealthConnect] so the caller can prompt a retry.
  /// See ANDROID.md §C.
  Future<HealthSetupResult> setUpHealthAccess() async {
    if (Platform.isAndroid) {
      final status = await _health.getHealthConnectSdkStatus();
      if (status != HealthConnectSdkStatus.sdkAvailable) {
        // sdkUnavailable / sdkUnavailableProviderUpdateRequired (or null):
        // open the Play Store so the user can install/update Health Connect.
        await _health.installHealthConnect();
        return HealthSetupResult.needsHealthConnect;
      }
    }
    final authorized = await requestAuthorization();
    return authorized ? HealthSetupResult.authorized : HealthSetupResult.denied;
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
        includeManualEntry: _includeManualEntry,
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
    // Bucket per hour and ask the platform for the aggregated total in each
    // bucket. On iOS getTotalStepsInInterval is backed by HKStatisticsQuery with
    // cumulativeSum, which is Apple's own cross-source merge — the same value
    // the Health app shows (iPhone + Watch + other wearables reconciled via
    // source priority, not summed). On Android it maps to Health Connect's
    // de-duplicated aggregate(). Manual-entry handling is platform-dependent —
    // see [_includeManualEntry].
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
        includeManualEntry: _includeManualEntry,
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
