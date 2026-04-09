import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:step_tracker/models/challenge_sync_day.dart';
import 'package:step_tracker/services/health_service.dart';

class _FakeHealth extends Health {
  final List<DateTime> capturedStarts = [];
  final List<DateTime> capturedEnds = [];
  final List<int?> stepResults;
  final List<bool> capturedIncludeManualEntry = [];
  List<RecordingMethod> capturedRecordingMethodsToFilter = const [];
  List<HealthDataPoint> hourlyResults = const [];
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
    final result = stepResults[_callIndex];
    _callIndex += 1;
    return result;
  }

  @override
  Future<List<HealthDataPoint>> getHealthDataFromTypes({
    required List<HealthDataType> types,
    Map<HealthDataType, HealthDataUnit>? preferredUnits,
    required DateTime startTime,
    required DateTime endTime,
    List<RecordingMethod> recordingMethodsToFilter = const [],
  }) async {
    capturedRecordingMethodsToFilter = recordingMethodsToFilter;
    return hourlyResults;
  }

  @override
  List<HealthDataPoint> removeDuplicates(List<HealthDataPoint> points) =>
      points;
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
      expect(fakeHealth.capturedIncludeManualEntry, [false, false]);
      expect(result[0].steps, 4100);
      expect(result[0].date, DateTime.utc(2026, 3, 16));
      expect(result[1].steps, 0);
      expect(result[1].date, DateTime.utc(2026, 3, 17));
    },
  );

  test('getHourlySteps filters out manual HealthKit entries', () async {
    final fakeHealth = _FakeHealth(const []);
    fakeHealth.hourlyResults = [
      HealthDataPoint(
        uuid: 'manual-1',
        value: NumericHealthValue(numericValue: 10000),
        type: HealthDataType.STEPS,
        unit: HealthDataUnit.COUNT,
        dateFrom: DateTime.parse('2026-04-09T14:28:00.000Z'),
        dateTo: DateTime.parse('2026-04-09T14:28:00.000Z'),
        sourcePlatform: HealthPlatformType.appleHealth,
        sourceDeviceId: 'device-1',
        sourceId: 'com.apple.Health',
        sourceName: 'Health',
        recordingMethod: RecordingMethod.manual,
        metadata: const {'HKWasUserEntered': true},
        deviceModel: 'iPhone17,1',
      ),
    ];
    final service = HealthService(health: fakeHealth);

    final result = await service.getHourlySteps(
      startTime: DateTime.parse('2026-04-09T00:00:00.000Z'),
      endTime: DateTime.parse('2026-04-09T23:59:59.000Z'),
    );

    expect(fakeHealth.capturedRecordingMethodsToFilter, [
      RecordingMethod.manual,
    ]);
    expect(result.single.steps, 10000);
    expect(result.single.recordingMethod, 'manual');
    expect(result.single.sourceName, 'Health');
    expect(result.single.sourceId, 'com.apple.Health');
    expect(result.single.sourceDeviceId, 'device-1');
    expect(result.single.deviceModel, 'iPhone17,1');
    expect(result.single.metadata, {'HKWasUserEntered': true});
  });
}
