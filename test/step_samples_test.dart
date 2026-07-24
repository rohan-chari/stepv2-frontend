import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:step_tracker/services/health_service.dart';
import 'package:step_tracker/models/step_sample_data.dart';

/// Fake keyed on the (start, end) window so a coarse hourly window and a fine
/// sub-window that share a start (e.g. 8:00-9:00 and 8:00-8:05) resolve to
/// distinct values. Records every call so tests can assert which windows the
/// two-pass read actually touched.
class _WindowFakeHealth extends Health {
  _WindowFakeHealth(this.values);

  final Map<String, int?> values;
  final List<DateTime> starts = [];
  final List<DateTime> ends = [];
  final List<bool> includeManual = [];

  static String key(DateTime s, DateTime e) =>
      '${s.toIso8601String()}|${e.toIso8601String()}';

  @override
  Future<int?> getTotalStepsInInterval(
    DateTime startTime,
    DateTime endTime, {
    bool includeManualEntry = true,
  }) async {
    starts.add(startTime);
    ends.add(endTime);
    includeManual.add(includeManualEntry);
    final k = key(startTime, endTime);
    return values.containsKey(k) ? values[k] : 0;
  }
}

void main() {
  // ---- Test 7: window construction ---------------------------------------
  group('buildBucketWindows (window construction)', () {
    test('5-min buckets tile an hour with a partial last bucket', () {
      final windows = HealthService.buildBucketWindows(
        DateTime(2026, 4, 9, 8),
        DateTime(2026, 4, 9, 9, 12),
        5,
      );

      // 12 full 5-min buckets in the hour + 3 in the partial 9:00-9:12 span.
      expect(windows.length, 15);
      expect(windows.first.start, DateTime(2026, 4, 9, 8));
      expect(windows.first.end, DateTime(2026, 4, 9, 8, 5));
      // Last bucket is partial and ends exactly at endTime.
      expect(windows.last.start, DateTime(2026, 4, 9, 9, 10));
      expect(windows.last.end, DateTime(2026, 4, 9, 9, 12));
    });

    test('first bucket is hour-aligned when start is on the hour', () {
      final windows = HealthService.buildBucketWindows(
        DateTime(2026, 4, 9, 8),
        DateTime(2026, 4, 9, 8, 30),
        60,
      );
      expect(windows.length, 1);
      expect(windows.single.start, DateTime(2026, 4, 9, 8));
      // Partial trailing hour ends at endTime, not the top of the hour.
      expect(windows.single.end, DateTime(2026, 4, 9, 8, 30));
    });

    test('steps by ABSOLUTE duration: contiguous, equal-width across DST edge',
        () {
      // The core DST guarantee: windows step by an absolute Duration, so
      // consecutive starts differ by exactly the bucket width in ELAPSED time
      // and windows are contiguous — even across a wall-clock jump. 2026-03-08
      // is US spring-forward; on a US-local test host the wall span 0:00-4:00 is
      // only 3 elapsed hours, which is precisely the case wall-clock
      // reconstruction would mis-bucket. Absolute stepping tiles it gap-free.
      final windows = HealthService.buildBucketWindows(
        DateTime(2026, 3, 8, 0),
        DateTime(2026, 3, 8, 4),
        60,
      );
      expect(windows, isNotEmpty);
      // Last window ends exactly at endTime.
      expect(windows.last.end, DateTime(2026, 3, 8, 4));
      for (var i = 0; i < windows.length; i++) {
        if (i > 0) {
          // Contiguous: each window begins exactly where the previous ended.
          expect(windows[i].start, windows[i - 1].end);
          // Absolute stepping: consecutive starts differ by one elapsed hour,
          // regardless of any wall-clock DST jump between them.
          expect(
            windows[i].start.difference(windows[i - 1].start),
            const Duration(hours: 1),
          );
          // Every non-final window is exactly one elapsed hour wide.
          expect(
            windows[i - 1].end.difference(windows[i - 1].start),
            const Duration(hours: 1),
          );
        }
      }
    });
  });

  // ---- Test 8: two-pass subdivision --------------------------------------
  test(
    'getStepSamples subdivides only active hours; zero/null hours untouched',
    () async {
      // Hour 8: 0 steps (skip). Hour 9: active. Hour 10: 0 (skip).
      final fake = _WindowFakeHealth({
        _WindowFakeHealth.key(
          DateTime(2026, 5, 1, 8),
          DateTime(2026, 5, 1, 9),
        ): 0,
        _WindowFakeHealth.key(
          DateTime(2026, 5, 1, 9),
          DateTime(2026, 5, 1, 10),
        ): 150,
        _WindowFakeHealth.key(
          DateTime(2026, 5, 1, 10),
          DateTime(2026, 5, 1, 11),
        ): 0,
        // Fine buckets inside hour 9 (only two are nonzero).
        _WindowFakeHealth.key(
          DateTime(2026, 5, 1, 9),
          DateTime(2026, 5, 1, 9, 5),
        ): 100,
        _WindowFakeHealth.key(
          DateTime(2026, 5, 1, 9, 10),
          DateTime(2026, 5, 1, 9, 15),
        ): 50,
      });
      final service = HealthService(health: fake);

      final samples = await service.getStepSamples(
        startTime: DateTime(2026, 5, 1, 8),
        endTime: DateTime(2026, 5, 1, 11),
        bucketMinutes: 5,
      );

      // Pass 1: 3 hourly reads. Pass 2: 12 fine reads for the single active hour.
      expect(fake.starts.length, 3 + 12);

      // No fine window was read inside the zero hours (8:xx or 10:xx).
      final fineReadStarts = fake.starts.where((s) => s.minute != 0).toList();
      expect(fineReadStarts, isNotEmpty);
      for (final s in fineReadStarts) {
        expect(s.hour, 9, reason: 'only hour 9 should be subdivided');
      }

      // Emitted: exactly the two nonzero fine buckets, chronological.
      expect(samples.length, 2);
      expect(samples[0].periodStart, DateTime(2026, 5, 1, 9).toUtc());
      expect(samples[0].periodEnd, DateTime(2026, 5, 1, 9, 5).toUtc());
      expect(samples[0].steps, 100);
      expect(samples[1].periodStart, DateTime(2026, 5, 1, 9, 10).toUtc());
      expect(samples[1].periodEnd, DateTime(2026, 5, 1, 9, 15).toUtc());
      expect(samples[1].steps, 50);
    },
  );

  test('getStepSamples with bucketMinutes 60 is a pure hourly single-pass read',
      () async {
    final fake = _WindowFakeHealth({
      _WindowFakeHealth.key(
        DateTime(2026, 5, 1, 8),
        DateTime(2026, 5, 1, 9),
      ): 200,
      _WindowFakeHealth.key(
        DateTime(2026, 5, 1, 9),
        DateTime(2026, 5, 1, 10),
      ): 300,
    });
    final service = HealthService(health: fake);

    final samples = await service.getStepSamples(
      startTime: DateTime(2026, 5, 1, 8),
      endTime: DateTime(2026, 5, 1, 10),
      bucketMinutes: 60,
    );

    // No second pass: exactly the two hourly reads, no subdivision.
    expect(fake.starts.length, 2);
    expect(samples.length, 2);
    expect(samples[0].steps, 200);
    expect(samples[1].steps, 300);
  });

  // ---- Test 9: Android day-wide manual bucketing -------------------------
  group('bucketManualStepsIntoWindows (Android per-bucket manual subtraction)',
      () {
    final windows = [
      (start: DateTime(2026, 6, 2, 9), end: DateTime(2026, 6, 2, 9, 5)),
      (start: DateTime(2026, 6, 2, 9, 5), end: DateTime(2026, 6, 2, 9, 10)),
      (start: DateTime(2026, 6, 2, 9, 10), end: DateTime(2026, 6, 2, 9, 15)),
    ];

    test('assigns each manual record to the window containing its timestamp',
        () {
      final manual = HealthService.bucketManualStepsIntoWindows(
        windows,
        [
          // Two records in bucket 0.
          MapEntry(DateTime(2026, 6, 2, 9, 2), 30),
          MapEntry(DateTime(2026, 6, 2, 9, 3), 20),
          // One record in bucket 2.
          MapEntry(DateTime(2026, 6, 2, 9, 12), 200),
          // Before the range -> dropped.
          MapEntry(DateTime(2026, 6, 2, 8, 59), 999),
          // On the exclusive end of the last bucket -> dropped.
          MapEntry(DateTime(2026, 6, 2, 9, 15), 5),
        ],
      );

      expect(manual, [50, 0, 200]);
    });

    test('per-bucket accurate total clamps at zero (may exceed the hourly floor)',
        () {
      // Aggregates per bucket vs manual per bucket.
      final aggregates = [40, 0, 300];
      final manual = [50, 0, 200];
      final perBucket = [
        for (var i = 0; i < aggregates.length; i++)
          HealthService.accurateAndroidTotal(aggregates[i], manual[i]),
      ];
      // Bucket 0 floors at 0 (40 - 50), bucket 2 = 100.
      expect(perBucket, [0, 0, 100]);
      // By design the clamped per-bucket sum (100) can exceed the old single
      // hourly clamp (sum agg 340 - sum manual 250 = 90).
      final perBucketSum = perBucket.reduce((a, b) => a + b);
      final hourlyFloor = HealthService.accurateAndroidTotal(340, 250);
      expect(perBucketSum, greaterThanOrEqualTo(hourlyFloor));
      expect(perBucketSum, 100);
      expect(hourlyFloor, 90);
    });
  });

  // ---- 2026-07-23 prod incident: fine buckets must sum to the hourly truth.
  //
  // Per-window HealthKit reads count a raw recording chunk IN FULL in every
  // fine bucket it straddles, so pass-2 buckets could sum to more steps than
  // the (deduped, correct) pass-1 hourly aggregate — DrAmogh's 9-10PM hour
  // read 4,456 hourly but 7,115 across its 5-min buckets, inflating race
  // scores ~47%. The fine read is only trusted for SHAPE: each active hour's
  // buckets are normalized so they sum exactly to that hour's aggregate.
  group('getStepSamples normalizes fine buckets to the hourly aggregate', () {
    Map<String, int?> hourWith(int hourTotal, Map<int, int> fineByMinute) {
      final m = <String, int?>{
        _WindowFakeHealth.key(
          DateTime(2026, 5, 1, 9),
          DateTime(2026, 5, 1, 10),
        ): hourTotal,
      };
      fineByMinute.forEach((minute, steps) {
        m[_WindowFakeHealth.key(
          DateTime(2026, 5, 1, 9, minute),
          DateTime(2026, 5, 1, 9, minute + 5),
        )] = steps;
      });
      return m;
    }

    Future<List<StepSampleData>> read(Map<String, int?> values) {
      final service = HealthService(health: _WindowFakeHealth(values));
      return service.getStepSamples(
        startTime: DateTime(2026, 5, 1, 9),
        endTime: DateTime(2026, 5, 1, 10),
        bucketMinutes: 5,
      );
    }

    test('inflated fine buckets are scaled DOWN to the hour total', () async {
      // Fine buckets sum to 1500 but the hour truthfully holds 1000.
      final samples = await read(hourWith(1000, {0: 900, 5: 300, 10: 300}));
      final sum = samples.fold<int>(0, (a, s) => a + s.steps);
      expect(sum, 1000, reason: 'hour must sum exactly to the aggregate');
      // Shape preserved: first bucket keeps its 3:1:1 dominance.
      expect(samples.first.steps, 600);
    });

    test('undercounting fine buckets are scaled UP to the hour total', () async {
      final samples = await read(hourWith(1000, {0: 400, 30: 400}));
      final sum = samples.fold<int>(0, (a, s) => a + s.steps);
      expect(sum, 1000);
    });

    test('matching fine buckets pass through unchanged', () async {
      final samples = await read(hourWith(150, {0: 100, 10: 50}));
      expect(samples.length, 2);
      expect(samples[0].steps, 100);
      expect(samples[1].steps, 50);
    });

    test('active hour with zero/null fine reads falls back to one hourly sample',
        () async {
      // Pass 1 sees 500 steps but every fine read returns 0 (or errors) —
      // the steps must not vanish from the payload.
      final samples = await read(hourWith(500, {}));
      expect(samples.length, 1);
      expect(samples.single.periodStart, DateTime(2026, 5, 1, 9).toUtc());
      expect(samples.single.periodEnd, DateTime(2026, 5, 1, 10).toUtc());
      expect(samples.single.steps, 500);
    });

    test('rounding never changes the hour sum (largest remainder)', () async {
      // 3 equal buckets into 100: 33/33/34 (any order), sum exactly 100.
      final samples = await read(hourWith(100, {0: 7, 5: 7, 10: 7}));
      final sum = samples.fold<int>(0, (a, s) => a + s.steps);
      expect(sum, 100);
    });
  });
}
