import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:step_tracker/services/health_service.dart';

/// Fake that observes concurrency: it holds each call open for a short delay so
/// overlapping calls are actually in flight at once, records the peak, and keys
/// its result on the interval start (so value assignment does not depend on call
/// completion order — only the production code's index bookkeeping does).
class _ConcurrencyFakeHealth extends Health {
  _ConcurrencyFakeHealth(
    this.byStart, {
    this.delay = const Duration(milliseconds: 5),
  });

  final Map<DateTime, int?> byStart;
  final Duration delay;
  int inFlight = 0;
  int maxInFlight = 0;
  int totalCalls = 0;

  @override
  Future<int?> getTotalStepsInInterval(
    DateTime startTime,
    DateTime endTime, {
    bool includeManualEntry = true,
  }) async {
    totalCalls += 1;
    inFlight += 1;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    await Future<void>.delayed(delay);
    inFlight -= 1;
    return byStart[startTime];
  }
}

void main() {
  test(
    'getHourlySteps never exceeds four concurrent platform calls',
    () async {
      // 10 one-hour buckets, all nonzero so every bucket makes a platform call.
      final byStart = <DateTime, int?>{
        for (var h = 0; h < 10; h++)
          DateTime(2026, 5, 1, h): (h + 1) * 100,
      };
      final fake = _ConcurrencyFakeHealth(byStart);
      final service = HealthService(health: fake);

      final samples = await service.getHourlySteps(
        startTime: DateTime(2026, 5, 1, 0),
        endTime: DateTime(2026, 5, 1, 10),
      );

      expect(fake.totalCalls, 10);
      expect(fake.maxInFlight, lessThanOrEqualTo(4));
      // All buckets nonzero -> 10 chronological samples.
      expect(samples.length, 10);
      for (var i = 0; i < samples.length; i++) {
        expect(samples[i].periodStart, DateTime(2026, 5, 1, i).toUtc());
        expect(samples[i].steps, (i + 1) * 100);
      }
    },
  );

  test(
    'getHourlySteps returns chronological nonzero samples identical to the '
    'sequential implementation',
    () async {
      // Mix of zero/null/nonzero across 6 buckets.
      final values = <int?>[0, 120, null, 0, 90, 300];
      final byStart = <DateTime, int?>{
        for (var h = 0; h < values.length; h++)
          DateTime(2026, 6, 2, h): values[h],
      };
      final fake = _ConcurrencyFakeHealth(byStart);
      final service = HealthService(health: fake);

      final samples = await service.getHourlySteps(
        startTime: DateTime(2026, 6, 2, 0),
        endTime: DateTime(2026, 6, 2, 6),
      );

      // Reference: same filter, chronological, sequential.
      final expected = <MapEntry<DateTime, int>>[];
      for (var h = 0; h < values.length; h++) {
        final v = values[h];
        if (v != null && v > 0) {
          expected.add(MapEntry(DateTime(2026, 6, 2, h).toUtc(), v));
        }
      }

      expect(samples.length, expected.length);
      for (var i = 0; i < samples.length; i++) {
        expect(samples[i].periodStart, expected[i].key);
        expect(samples[i].steps, expected[i].value);
      }
      // Samples strictly chronological.
      for (var i = 1; i < samples.length; i++) {
        expect(
          samples[i].periodStart.isAfter(samples[i - 1].periodStart),
          isTrue,
        );
      }
    },
  );

  test('getHourlySteps with a partial trailing bucket still buckets correctly',
      () async {
    final byStart = <DateTime, int?>{
      DateTime(2026, 7, 3, 8): 50,
      DateTime(2026, 7, 3, 9): 75,
    };
    final fake = _ConcurrencyFakeHealth(byStart);
    final service = HealthService(health: fake);

    final samples = await service.getHourlySteps(
      startTime: DateTime(2026, 7, 3, 8),
      endTime: DateTime(2026, 7, 3, 9, 30),
    );

    expect(samples.length, 2);
    expect(samples[0].periodStart, DateTime(2026, 7, 3, 8).toUtc());
    expect(samples[0].periodEnd, DateTime(2026, 7, 3, 9).toUtc());
    expect(samples[1].periodStart, DateTime(2026, 7, 3, 9).toUtc());
    // Trailing partial bucket ends at the supplied endTime.
    expect(samples[1].periodEnd, DateTime(2026, 7, 3, 9, 30).toUtc());
  });
}
