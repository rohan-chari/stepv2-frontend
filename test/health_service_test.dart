import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:step_tracker/models/challenge_sync_day.dart';
import 'package:step_tracker/services/health_service.dart';

class _FakeHealth extends Health {
  final List<DateTime> capturedStarts = [];
  final List<DateTime> capturedEnds = [];
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
    final result = stepResults[_callIndex];
    _callIndex += 1;
    return result;
  }
}

void main() {
  test(
    'getStepsForSyncDays queries the provided intervals and preserves the challenge dates',
    () async {
      final fakeHealth = _FakeHealth([4100, null]);
      final service = HealthService(health: fakeHealth);

      final result = await service.getStepsForSyncDays(
        syncDays: [
          ChallengeSyncDay(
            date: DateTime.utc(2026, 3, 16),
            startsAt: DateTime.parse('2026-03-16T04:00:00.000Z'),
            endsAt: DateTime.parse('2026-03-17T04:00:00.000Z'),
          ),
          ChallengeSyncDay(
            date: DateTime.utc(2026, 3, 17),
            startsAt: DateTime.parse('2026-03-17T04:00:00.000Z'),
            endsAt: DateTime.parse('2026-03-17T15:30:00.000Z'),
          ),
        ],
      );

      expect(fakeHealth.capturedStarts, [
        DateTime.parse('2026-03-16T04:00:00.000Z'),
        DateTime.parse('2026-03-17T04:00:00.000Z'),
      ]);
      expect(fakeHealth.capturedEnds, [
        DateTime.parse('2026-03-17T04:00:00.000Z'),
        DateTime.parse('2026-03-17T15:30:00.000Z'),
      ]);
      expect(result[0].steps, 4100);
      expect(result[0].date, DateTime.utc(2026, 3, 16));
      expect(result[1].steps, 0);
      expect(result[1].date, DateTime.utc(2026, 3, 17));
    },
  );
}
