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

  /// Drops the persisted authorization flag.
  ///
  /// This is device-scoped state that must not outlive the account that
  /// granted it. Account deletion is server-side only, so without this a
  /// re-signup on the same device restores `_authorized = true` before the
  /// first frame and the onboarding health gate becomes unreachable — the new
  /// user is never asked, and on Android (where the OS grant is revocable
  /// independently) may never be connected at all.
  static Future<void> clearPersistedAuthState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyHealthAuthorized);
  }

  /// Instance form of [clearPersistedAuthState] that also resets the in-memory
  /// flag, for callers holding a live service.
  Future<void> clearAuthState() async {
    await clearPersistedAuthState();
    _authorized = false;
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

  /// Hourly step read (the legacy granularity). Buckets `[startTime, endTime)`
  /// per hour, reads the accurate total in each via [_stepsInInterval], and
  /// emits one UTC [StepSampleData] per non-zero hour — byte-for-byte identical
  /// to the pre-`getStepSamples` behavior.
  ///
  /// This is the real hourly implementation (not a wrapper) on purpose:
  /// [getStepSamples] delegates its 60-minute path here, so a subclass fake that
  /// overrides `getHourlySteps` still intercepts the hourly path taken when the
  /// backend flag is absent/60. Existing callers and tests keep working.
  Future<List<StepSampleData>> getHourlySteps({
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    final hourWindows = buildBucketWindows(startTime, endTime, 60);
    final hourTotals = await _mapWithConcurrency<_Window, int?>(
      hourWindows,
      _hourlyConcurrency,
      (w) => _stepsInInterval(w.start, w.end),
    );
    return _emitSamples(hourWindows, hourTotals);
  }

  /// Reads step totals bucketed at [bucketMinutes] granularity over
  /// `[startTime, endTime)`. Emits one [StepSampleData] per non-zero bucket, in
  /// chronological order, in UTC. Payload shape is identical at every
  /// granularity — finer buckets just mean more, shorter samples.
  ///
  /// Two-pass read to bound platform calls (§5.1):
  ///   * Pass 1 reads the hourly windows (≤24 aggregate calls).
  ///   * Pass 2 subdivides ONLY hours with steps > 0 into [bucketMinutes]
  ///     windows and re-reads those. Zero/null hours are never subdivided and
  ///     contribute nothing. Only pass-2 (fine) buckets are emitted for active
  ///     hours — never both granularities for the same hour.
  ///
  /// At [bucketMinutes] == 60 there is no second pass and the result is
  /// byte-for-byte identical to the legacy hourly read (the degradation path
  /// when the backend flag is absent/invalid).
  ///
  /// Accurate totals per bucket come from [_stepsInInterval] (iOS: HealthKit's
  /// deduped, manual-excluded cumulativeSum; Android: deduped aggregate minus
  /// manually-entered steps) — EXCEPT that on Android the fine (pass-2) buckets
  /// read manual-tagged records ONCE for the whole range and subtract per bucket
  /// (see [_fineTotals]) rather than issuing a manual read per bucket.
  Future<List<StepSampleData>> getStepSamples({
    required DateTime startTime,
    required DateTime endTime,
    int bucketMinutes = 60,
  }) async {
    // Hourly granularity (or coarser): delegate to [getHourlySteps] so this is
    // bit-identical to the legacy path AND a subclass fake overriding
    // getHourlySteps still intercepts it.
    if (bucketMinutes >= 60) {
      return getHourlySteps(startTime: startTime, endTime: endTime);
    }

    // Pass 1: hourly windows. Built chronologically, evaluated with bounded
    // concurrency, re-assembled BY INDEX. Read here (not via getHourlySteps)
    // because the fine path needs the per-hour totals AND window boundaries to
    // decide which hours to subdivide — getHourlySteps drops zero hours.
    final hourWindows = buildBucketWindows(startTime, endTime, 60);
    final hourTotals = await _mapWithConcurrency<_Window, int?>(
      hourWindows,
      _hourlyConcurrency,
      (w) => _stepsInInterval(w.start, w.end),
    );

    // Pass 2: subdivide only the active hours into fine buckets.
    final fineWindows = <_Window>[];
    // Each active hour keeps its window, its trusted total, and the index
    // range of its fine buckets inside the batched fineWindows list, so the
    // normalization below can slice per hour after ONE batched read.
    final activeHours = <({_Window hour, int total, int fineStart, int fineCount})>[];
    for (var i = 0; i < hourWindows.length; i++) {
      final total = hourTotals[i];
      if (total != null && total > 0) {
        final buckets = buildBucketWindows(
          hourWindows[i].start,
          hourWindows[i].end,
          bucketMinutes,
        );
        activeHours.add((
          hour: hourWindows[i],
          total: total,
          fineStart: fineWindows.length,
          fineCount: buckets.length,
        ));
        fineWindows.addAll(buckets);
      }
    }
    if (fineWindows.isEmpty) return <StepSampleData>[];

    final fineTotals = await _fineTotals(fineWindows, startTime, endTime);

    // Fine reads are trusted for SHAPE only, never for magnitude: a raw
    // HealthKit recording chunk that straddles a bucket boundary is counted in
    // full by every fine window it touches, so fine buckets can sum well past
    // the (deduped, correct) hourly aggregate — the 2026-07-23 incident
    // inflated an hour by ~60% and race scores by ~47%. Normalize each hour's
    // buckets to sum exactly to its pass-1 aggregate; an hour whose fine reads
    // all came back 0/null still ships as one hourly sample so no steps vanish.
    final samples = <StepSampleData>[];
    for (final h in activeHours) {
      final windows = fineWindows.sublist(h.fineStart, h.fineStart + h.fineCount);
      final raw = fineTotals
          .sublist(h.fineStart, h.fineStart + h.fineCount)
          .map((v) => (v == null || v < 0) ? 0 : v)
          .toList();
      final rawSum = raw.fold<int>(0, (a, v) => a + v);
      if (rawSum <= 0) {
        samples.addAll(_emitSamples([h.hour], [h.total]));
        continue;
      }
      final scaled = rawSum == h.total ? raw : scaleToTotal(raw, h.total);
      samples.addAll(_emitSamples(windows, scaled));
    }
    return samples;
  }

  /// Scales [values] (non-negative, not all zero) so they sum exactly to
  /// [total], preserving proportions. Largest-remainder rounding: floor each
  /// scaled value, then hand the leftover units to the largest fractional
  /// remainders, so the sum is exact without any value going negative.
  @visibleForTesting
  static List<int> scaleToTotal(List<int> values, int total) {
    final sum = values.fold<int>(0, (a, v) => a + v);
    final floors = List<int>.filled(values.length, 0);
    final remainders = List<({int index, double frac})>.generate(values.length, (i) {
      final exact = values[i] * total / sum;
      floors[i] = exact.floor();
      return (index: i, frac: exact - exact.floor());
    });
    var leftover = total - floors.fold<int>(0, (a, v) => a + v);
    remainders.sort((a, b) => b.frac.compareTo(a.frac));
    for (var i = 0; leftover > 0 && i < remainders.length; i++, leftover--) {
      floors[remainders[i].index]++;
    }
    return floors;
  }

  /// Reads accurate step totals for the pass-2 fine [windows]. On iOS this is
  /// one deduped, manual-excluded aggregate per window. On Android it reads the
  /// manually-entered records ONCE across `[rangeStart, rangeEnd)`, buckets them
  /// client-side by timestamp, and subtracts them from each window's deduped
  /// aggregate with the per-bucket [accurateAndroidTotal] clamp — so a single
  /// day-wide manual read serves every fine bucket instead of one read each.
  ///
  /// NOTE (by design): the clamp is applied PER BUCKET, so if one bucket's
  /// manual entries exceed its deduped aggregate it floors at 0 without
  /// "borrowing" from neighbours. The summed clamped total can therefore exceed
  /// what the old single hourly clamp produced. This is intentional and only
  /// affects the (rare) case of manual entries concentrated in one fine bucket.
  Future<List<int?>> _fineTotals(
    List<_Window> windows,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) async {
    if (!Platform.isAndroid) {
      return _mapWithConcurrency<_Window, int?>(
        windows,
        _hourlyConcurrency,
        (w) => _health.getTotalStepsInInterval(
          w.start,
          w.end,
          includeManualEntry: false,
        ),
      );
    }

    // Android: one day-wide manual read, bucketed client-side.
    final manualByWindow = await _manualStepsPerWindow(
      windows,
      rangeStart,
      rangeEnd,
    );
    final aggregates = await _mapWithConcurrency<_Window, int?>(
      windows,
      _hourlyConcurrency,
      (w) => _health.getTotalStepsInInterval(
        w.start,
        w.end,
        includeManualEntry: true,
      ),
    );
    final totals = List<int?>.filled(windows.length, null);
    for (var i = 0; i < windows.length; i++) {
      final agg = aggregates[i];
      if (agg == null) continue; // read error — omit this bucket
      totals[i] = accurateAndroidTotal(agg, manualByWindow[i]);
    }
    return totals;
  }

  /// Android only: reads manual-tagged step records ONCE across
  /// `[rangeStart, rangeEnd)` and buckets their step counts into [windows] by
  /// record start timestamp, returning a per-window manual sum aligned to
  /// [windows]. See [bucketManualStepsIntoWindows] for the pure bucketing.
  Future<List<int>> _manualStepsPerWindow(
    List<_Window> windows,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) async {
    final points = await _health.getHealthDataFromTypes(
      types: const [HealthDataType.STEPS],
      startTime: rangeStart,
      endTime: rangeEnd,
      recordingMethodsToFilter: const [
        RecordingMethod.automatic,
        RecordingMethod.active,
        RecordingMethod.unknown,
      ],
    );
    final manualEntries = <MapEntry<DateTime, int>>[];
    for (final point in points) {
      if (point.recordingMethod != RecordingMethod.manual) continue;
      final value = point.value;
      if (value is NumericHealthValue) {
        manualEntries.add(MapEntry(point.dateFrom, value.numericValue.round()));
      }
    }
    return bucketManualStepsIntoWindows(windows, manualEntries);
  }

  /// Pure bucketing: sums each manual entry's steps into the [windows] bucket
  /// whose half-open `[start, end)` contains the entry's timestamp. Entries
  /// outside every window (or exactly on a window's exclusive end with no next
  /// window) are dropped. Returned list is aligned to [windows].
  @visibleForTesting
  static List<int> bucketManualStepsIntoWindows(
    List<({DateTime start, DateTime end})> windows,
    List<MapEntry<DateTime, int>> manualEntries,
  ) {
    final manual = List<int>.filled(windows.length, 0);
    for (final entry in manualEntries) {
      final ts = entry.key;
      for (var i = 0; i < windows.length; i++) {
        if (!ts.isBefore(windows[i].start) && ts.isBefore(windows[i].end)) {
          manual[i] += entry.value;
          break;
        }
      }
    }
    return manual;
  }

  /// Builds contiguous, chronological buckets over `[start, end)`. The first
  /// bucket is aligned to the top of [start]'s hour (clamped up to [start]),
  /// then each subsequent bucket steps by an ABSOLUTE `Duration(minutes:
  /// bucketMinutes)` — never reconstructed from wall-clock fields — so a DST
  /// transition still yields gap-free, equal-width UTC windows. The final
  /// bucket is left partial (`bucketStart → end`).
  @visibleForTesting
  static List<({DateTime start, DateTime end})> buildBucketWindows(
    DateTime start,
    DateTime end,
    int bucketMinutes,
  ) {
    final windows = <_Window>[];
    var bucketStart = DateTime(start.year, start.month, start.day, start.hour);
    if (bucketStart.isBefore(start)) {
      bucketStart = start;
    }
    final step = Duration(minutes: bucketMinutes);
    while (bucketStart.isBefore(end)) {
      var bucketEnd = bucketStart.add(step);
      if (bucketEnd.isAfter(end)) {
        bucketEnd = end;
      }
      windows.add((start: bucketStart, end: bucketEnd));
      bucketStart = bucketEnd;
    }
    return windows;
  }

  /// Emits one UTC [StepSampleData] per window with a positive total, aligned
  /// by index to [totals]. Null/zero totals are dropped.
  List<StepSampleData> _emitSamples(List<_Window> windows, List<int?> totals) {
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

/// A half-open `[start, end)` bucket. A record alias so the public
/// [HealthService.buildBucketWindows] does not leak a private class type.
typedef _Window = ({DateTime start, DateTime end});
