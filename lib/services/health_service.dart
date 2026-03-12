import 'package:health/health.dart';
import '../models/step_data.dart';

class HealthService {
  final Health _health = Health();

  Future<bool> requestAuthorization() async {
    final types = [HealthDataType.STEPS];
    final permissions = [HealthDataAccess.READ];

    bool requested = await _health.requestAuthorization(
      types,
      permissions: permissions,
    );
    return requested;
  }

  Future<StepData> getStepsToday() async {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);

    final steps = await _health.getTotalStepsInInterval(midnight, now);

    return StepData(
      steps: steps ?? 0,
      date: now,
    );
  }
}
