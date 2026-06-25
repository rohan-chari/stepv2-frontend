import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/services/health_service.dart';

// Phase 2 — the deduped-minus-manual step math the background WorkManager worker
// (StepSyncWorker.kt) must mirror exactly so background and foreground totals agree.
void main() {
  group('HealthService.accurateAndroidTotal (anti-cheat dedup math)', () {
    test('subtracts manual steps from the deduped total', () {
      expect(HealthService.accurateAndroidTotal(10500, 300), 10200);
    });

    test('returns the deduped total when there are no manual steps', () {
      expect(HealthService.accurateAndroidTotal(5000, 0), 5000);
    });

    test('clamps to zero when manual entry exceeds the deduped total', () {
      expect(HealthService.accurateAndroidTotal(500, 1000), 0);
    });

    test('a huge fake manual entry can never inflate the total', () {
      expect(HealthService.accurateAndroidTotal(8000, 10000000), 0);
    });

    test('zero in, zero out', () {
      expect(HealthService.accurateAndroidTotal(0, 0), 0);
    });
  });
}
