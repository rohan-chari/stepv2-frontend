import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/models/challenge_sync_day.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/challenge_week_step_sync_service.dart';
import 'package:step_tracker/services/health_service.dart';

class _FakeBackendApiService extends BackendApiService {
  _FakeBackendApiService({this.currentChallenge, this.error});

  final Map<String, dynamic>? currentChallenge;
  final Object? error;

  @override
  Future<Map<String, dynamic>> fetchCurrentChallenge({
    required String identityToken,
  }) async {
    if (error != null) throw error!;
    return currentChallenge ?? const {};
  }
}

class _FakeHealthService extends HealthService {
  _FakeHealthService(this.stepData);

  final List<StepData> stepData;
  List<ChallengeSyncDay> capturedSyncDays = [];

  @override
  Future<List<StepData>> getStepsForSyncDays({
    required List<ChallengeSyncDay> syncDays,
  }) async {
    capturedSyncDays = syncDays;
    return stepData;
  }
}

void main() {
  test(
    'loadCurrentChallengeWeekSteps uses backend sync days for the challenge week',
    () async {
      final healthService = _FakeHealthService([
        StepData(steps: 4100, date: DateTime(2026, 3, 16)),
        StepData(steps: 5800, date: DateTime(2026, 3, 17)),
        StepData(steps: 7200, date: DateTime(2026, 3, 18)),
      ]);

      final service = ChallengeWeekStepSyncService(
        backendApiService: _FakeBackendApiService(
          currentChallenge: {
            'challenge': {'title': 'Summit Sprint'},
            'weekOf': '2026-03-16',
            'syncDays': [
              {
                'date': '2026-03-16',
                'startsAt': '2026-03-16T04:00:00.000Z',
                'endsAt': '2026-03-17T04:00:00.000Z',
              },
              {
                'date': '2026-03-17',
                'startsAt': '2026-03-17T04:00:00.000Z',
                'endsAt': '2026-03-18T04:00:00.000Z',
              },
              {
                'date': '2026-03-18',
                'startsAt': '2026-03-18T04:00:00.000Z',
                'endsAt': '2026-03-18T14:30:00.000Z',
              },
            ],
          },
        ),
        healthService: healthService,
        now: () => DateTime(2026, 3, 18, 14, 30),
      );

      final result = await service.loadCurrentChallengeWeekSteps(
        identityToken: 'session-token',
      );

      expect(result, hasLength(3));
      expect(healthService.capturedSyncDays, hasLength(3));
      expect(
        healthService.capturedSyncDays.first.date,
        DateTime.utc(2026, 3, 16),
      );
      expect(
        healthService.capturedSyncDays.first.startsAt,
        DateTime.parse('2026-03-16T04:00:00.000Z'),
      );
      expect(
        healthService.capturedSyncDays.last.endsAt,
        DateTime.parse('2026-03-18T14:30:00.000Z'),
      );
      expect(result.last.steps, 7200);
    },
  );

  test(
    'loadCurrentChallengeWeekSteps falls back to today when syncDays are missing',
    () async {
      final healthService = _FakeHealthService([
        StepData(steps: 3600, date: DateTime.utc(2026, 3, 18)),
      ]);

      final service = ChallengeWeekStepSyncService(
        backendApiService: _FakeBackendApiService(
          currentChallenge: {
            'challenge': null,
            'weekOf': null,
            'syncDays': const [],
          },
        ),
        healthService: healthService,
        now: () => DateTime(2026, 3, 18, 14, 30),
      );

      final result = await service.loadCurrentChallengeWeekSteps(
        identityToken: 'session-token',
      );

      expect(result, hasLength(1));
      expect(healthService.capturedSyncDays, hasLength(1));
      expect(
        healthService.capturedSyncDays.single.date,
        DateTime.utc(2026, 3, 18),
      );
      expect(
        healthService.capturedSyncDays.single.endsAt,
        DateTime(2026, 3, 18, 14, 30),
      );
    },
  );

  test(
    'loadCurrentChallengeWeekSteps falls back to today when the challenge fetch fails',
    () async {
      final healthService = _FakeHealthService([
        StepData(steps: 2900, date: DateTime.utc(2026, 3, 18)),
      ]);

      final service = ChallengeWeekStepSyncService(
        backendApiService: _FakeBackendApiService(
          error: const ApiException('backend unavailable', statusCode: 500),
        ),
        healthService: healthService,
        now: () => DateTime(2026, 3, 18, 14, 30),
      );

      final result = await service.loadCurrentChallengeWeekSteps(
        identityToken: 'session-token',
      );

      expect(result, hasLength(1));
      expect(
        healthService.capturedSyncDays.single.date,
        DateTime.utc(2026, 3, 18),
      );
      expect(result.single.steps, 2900);
    },
  );
}
