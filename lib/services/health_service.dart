import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show visibleForTesting;
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

  /// The accurate step total for the half-open interval [start, end) on the
  /// current platform. Returns null on a read error so callers don't persist a
  /// fabricated 0.
  ///
  /// iOS: HealthKit's HKStatisticsQuery/cumulativeSum de-duplicates across
  /// sources AND excludes manual entries in a single call
  /// (`includeManualEntry: false`) — the proven-accurate path. Kept exactly as-is.
  ///
  /// Android: Health Connect (via this plugin) exposes NO single call that both
  /// de-duplicates and excludes manual entries:
  ///   * `includeManualEntry: false` drops Health Connect's dedup → sums every
  ///     step-writing app with no reconciliation (phone + watch double-count) —
  ///     an UNBOUNDED inflation that hits even honest users.
  ///   * `includeManualEntry: true` keeps the de-duplicated aggregate but counts
  ///     manually-typed steps — an UNBOUNDED cheat vector (type 10,000,000 steps).
  /// Neither is acceptable for a step-race coin economy, so we compose the only
  /// accurate option: take the de-duplicated aggregate, then subtract the steps
  /// Health Connect tags as manually entered. See ANDROID.md §C-5.
  ///
  /// Keyed on `isAndroid` (not `!isIOS`) on purpose: the host test runner and
  /// web are neither, and keep the iOS path so existing tests stay valid.
  Future<int?> _stepsInInterval(DateTime start, DateTime end) async {
    if (!Platform.isAndroid) {
      return _health.getTotalStepsInInterval(
        start,
        end,
        includeManualEntry: false,
      );
    }
    final deduped = await _health.getTotalStepsInInterval(
      start,
      end,
      includeManualEntry: true,
    );
    if (deduped == null) return null; // read error — let caller decide
    final manual = await _manualStepsInInterval(start, end);
    return accurateAndroidTotal(deduped, manual);
  }

  /// Anti-cheat core: the reported Android total is the de-duplicated aggregate
  /// minus manually-entered steps, never below zero. Any amount of manual entry
  /// (e.g. a typed 10,000,000) is fully removed and can never inflate the total.
  @visibleForTesting
  static int accurateAndroidTotal(int dedupedTotal, int manualSteps) {
    final accurate = dedupedTotal - manualSteps;
    return accurate < 0 ? 0 : accurate;
  }

  /// Android only: sum of steps Health Connect marks as manually entered, so they
  /// can be removed from the de-duplicated aggregate. Reads manual-only records by
  /// excluding every non-manual recording method, then sums them (defensively
  /// re-checking the tag).
  Future<int> _manualStepsInInterval(DateTime start, DateTime end) async {
    final points = await _health.getHealthDataFromTypes(
      types: const [HealthDataType.STEPS],
      startTime: start,
      endTime: end,
      recordingMethodsToFilter: const [
        RecordingMethod.automatic,
        RecordingMethod.active,
        RecordingMethod.unknown,
      ],
    );
    var manual = 0;
    for (final point in points) {
      if (point.recordingMethod != RecordingMethod.manual) continue;
      final value = point.value;
      if (value is NumericHealthValue) {
        manual += value.numericValue.round();
      }
    }
    return manual;
  }

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
      final steps = await _stepsInInterval(currentDate, intervalEnd);

      entries.add(StepData(steps: steps ?? 0, date: currentDate));

      currentDate = currentDate.add(const Duration(days: 1));
    }

    return entries;
  }

  /// Maximum number of platform aggregate reads kept in flight while bucketing
  /// hourly samples. Bounded (D13) so a highly active user with many hours does
  /// not fan out an unbounded burst of HealthKit/Health Connect calls, while
  /// still overlapping I/O for a real speedup over the old one-at-a-time loop.
  /// If either platform proves unstable under concurrency, lower this to 2 — do
  /// not revert to unbounded.
  static const int _hourlyConcurrency = 4;

  Future<List<StepSampleData>> getHourlySteps({
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    // Bucket per hour and ask the platform for the accurate total in each bucket
    // via [_stepsInInterval]: iOS uses HealthKit's deduped, manual-excluded
    // cumulativeSum; Android uses Health Connect's de-duplicated aggregate minus
    // manually-entered steps. See [_stepsInInterval] / ANDROID.md §C-5.
    //
    // Windows are built in chronological order, evaluated with bounded
    // concurrency, then re-assembled BY INDEX so the emitted samples are byte-
    // for-byte identical (order + values) to the old sequential loop.
    final windows = <_HourWindow>[];
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
      windows.add(_HourWindow(bucketStart, bucketEnd));
      bucketStart = bucketEnd;
    }

    final totals = await _mapWithConcurrency<_HourWindow, int?>(
      windows,
      _hourlyConcurrency,
      (w) => _stepsInInterval(w.start, w.end),
    );

    final samples = <StepSampleData>[];
    for (var i = 0; i < windows.length; i++) {
      final steps = totals[i];
      if (steps != null && steps > 0) {
        samples.add(
          StepSampleData(
            periodStart: windows[i].start.toUtc(),
            periodEnd: windows[i].end.toUtc(),
            steps: steps,
          ),
        );
      }
    }

    return samples;
  }

  /// Runs [task] over [items] with at most [maxConcurrent] futures in flight,
  /// returning results positionally aligned to [items]. Work is dispatched in
  /// list order (each task is started before its first suspension), which keeps
  /// any order-sensitive fake/platform bookkeeping deterministic.
  static Future<List<R>> _mapWithConcurrency<T, R>(
    List<T> items,
    int maxConcurrent,
    Future<R> Function(T item) task,
  ) async {
    if (items.isEmpty) return <R>[];
    final results = List<R?>.filled(items.length, null);
    var nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        final i = nextIndex;
        if (i >= items.length) return;
        nextIndex += 1;
        results[i] = await task(items[i]);
      }
    }

    final workerCount = maxConcurrent < items.length
        ? maxConcurrent
        : items.length;
    await Future.wait([for (var k = 0; k < workerCount; k++) worker()]);
    return results.cast<R>();
  }
}

class _HourWindow {
  const _HourWindow(this.start, this.end);
  final DateTime start;
  final DateTime end;
}
