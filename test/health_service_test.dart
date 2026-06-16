import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:step_tracker/services/health_service.dart';

class _FakeHealth extends Health {
  final List<DateTime> capturedStarts = [];
  final List<DateTime> capturedEnds = [];
  final List<bool> capturedIncludeManualEntry = [];
  final List<int?> stepResults;
  int _callIndex = 0;

  _FakeHealth(this.stepResults);

  @override
  Future<int?> getTotalStepsInInterval(
    DateTime startTime,
    DateTime endTime, {
    bool includeManualEntry = true,
  }) async {
    capturedStarts.add(startTime);
    capturedEnds.add(endTime);
    capturedIncludeManualEntry.add(includeManualEntry);
    final result = stepResults[_callIndex % stepResults.length];
    _callIndex += 1;
    return result;
  }
}

void main() {
  test(
    'getStepsForDateRange sums each day via getTotalStepsInInterval and excludes manual entries',
    () async {
      // One value per day in the range (2 days).
      final fakeHealth = _FakeHealth([4100, null]);
      final service = HealthService(health: fakeHealth);

      final result = await service.getStepsForDateRange(
        startDate: DateTime(2026, 3, 16),
        endDate: DateTime(2026, 3, 17, 15, 30),
      );

      // First (non-current) day is queried for the full midnight->midnight day.
      expect(fakeHealth.capturedStarts.first, DateTime(2026, 3, 16));
      expect(fakeHealth.capturedEnds.first, DateTime(2026, 3, 17));
      // The current day's interval ends at the supplied endDate, not midnight.
      expect(fakeHealth.capturedStarts.last, DateTime(2026, 3, 17));
      expect(fakeHealth.capturedEnds.last, DateTime(2026, 3, 17, 15, 30));

      // Manual entries must always be excluded.
      expect(
        fakeHealth.capturedIncludeManualEntry,
        everyElement(isFalse),
      );

      expect(result.length, 2);
      expect(result[0].steps, 4100);
      expect(result[0].date, DateTime(2026, 3, 16));
      // A null result from HealthKit is coerced to 0.
      expect(result[1].steps, 0);
      expect(result[1].date, DateTime(2026, 3, 17));
    },
  );

  group('accurateAndroidTotal (anti-cheat: dedup minus manual)', () {
    test('subtracts manually-entered steps from the deduped total', () {
      expect(HealthService.accurateAndroidTotal(9000, 1500), 7500);
    });

    test('no manual entries leaves the deduped total unchanged', () {
      expect(HealthService.accurateAndroidTotal(8200, 0), 8200);
    });

    test('a massive manual entry cannot inflate — clamps to zero', () {
      // The whole point: typing 10,000,000 steps nets nothing.
      expect(HealthService.accurateAndroidTotal(5000, 10000000), 0);
    });

    test('never returns a negative total', () {
      expect(HealthService.accurateAndroidTotal(0, 250), 0);
    });
  });

  test('getStepsToday returns the current day entry', () async {
    final fakeHealth = _FakeHealth([7321]);
    final service = HealthService(health: fakeHealth);

    final today = await service.getStepsToday();

    expect(today.steps, 7321);
    expect(fakeHealth.capturedIncludeManualEntry, everyElement(isFalse));
  });

  test(
    'getHourlySteps buckets per hour via getTotalStepsInInterval, drops empty/null hours, and excludes manual entries',
    () async {
      // Three one-hour buckets: 0 steps, null, then 250 steps.
      final fakeHealth = _FakeHealth([0, null, 250]);
      final service = HealthService(health: fakeHealth);

      final samples = await service.getHourlySteps(
        startTime: DateTime(2026, 4, 9, 8),
        endTime: DateTime(2026, 4, 9, 11),
      );

      // Three hourly buckets were queried.
      expect(fakeHealth.capturedStarts.length, 3);
      expect(fakeHealth.capturedIncludeManualEntry, everyElement(isFalse));

      // Only the bucket with positive steps is emitted.
      expect(samples.length, 1);
      expect(samples.single.steps, 250);
      expect(samples.single.periodStart, DateTime(2026, 4, 9, 10).toUtc());
      expect(samples.single.periodEnd, DateTime(2026, 4, 9, 11).toUtc());
    },
  );
}
