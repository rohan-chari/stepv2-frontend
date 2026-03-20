import '../models/challenge_sync_day.dart';
import '../models/step_data.dart';
import 'backend_api_service.dart';
import 'health_service.dart';

class ChallengeWeekStepSyncService {
  ChallengeWeekStepSyncService({
    BackendApiService? backendApiService,
    HealthService? healthService,
    DateTime Function()? now,
  }) : _backendApiService = backendApiService ?? BackendApiService(),
       _healthService = healthService ?? HealthService(),
       _now = now ?? DateTime.now;

  final BackendApiService _backendApiService;
  final HealthService _healthService;
  final DateTime Function() _now;

  Future<List<StepData>> loadCurrentChallengeWeekSteps({
    required String identityToken,
  }) async {
    final currentTime = _now();
    final syncDays = await _loadSyncDays(
      identityToken: identityToken,
      now: currentTime,
    );

    return _healthService.getStepsForSyncDays(syncDays: syncDays);
  }

  Future<List<ChallengeSyncDay>> _loadSyncDays({
    required String identityToken,
    required DateTime now,
  }) async {
    try {
      final currentChallenge = await _backendApiService.fetchCurrentChallenge(
        identityToken: identityToken,
      );
      final syncDays = _parseSyncDays(currentChallenge['syncDays']);

      if (syncDays.isNotEmpty) {
        return syncDays;
      }
    } catch (_) {
      return [ChallengeSyncDay.localToday(now)];
    }

    return [ChallengeSyncDay.localToday(now)];
  }

  List<ChallengeSyncDay> _parseSyncDays(Object? rawValue) {
    if (rawValue is! List) return const [];

    final syncDays = <ChallengeSyncDay>[];

    for (final entry in rawValue) {
      if (entry is! Map<String, dynamic>) {
        return const [];
      }

      try {
        syncDays.add(ChallengeSyncDay.fromJson(entry));
      } on FormatException {
        return const [];
      }
    }

    return syncDays;
  }
}
