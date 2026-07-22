import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/models/step_sample_data.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('featureFlags.stepSampleBucketMinutes plumbing', () {
    test('defaults to 60 (hourly) when never set', () {
      final auth = AuthService();
      expect(auth.stepSampleBucketMinutes, 60);
    });

    test('a valid value in {5,10,15,30,60} is accepted', () {
      final auth = AuthService();
      auth.applyBackendUser({
        'featureFlags': {'stepSampleBucketMinutes': 5},
      });
      expect(auth.stepSampleBucketMinutes, 5);
    });

    test('an absent key inside featureFlags falls back to 60', () {
      final auth = AuthService();
      auth.applyBackendUser({
        'featureFlags': {'bannerAdsEnabled': true},
      });
      expect(auth.stepSampleBucketMinutes, 60);
    });

    test('an out-of-set numeric value falls back to 60', () {
      final auth = AuthService();
      auth.applyBackendUser({
        'featureFlags': {'stepSampleBucketMinutes': 20},
      });
      expect(auth.stepSampleBucketMinutes, 60);
    });

    test('null falls back to 60', () {
      final auth = AuthService();
      auth.applyBackendUser({
        'featureFlags': {'stepSampleBucketMinutes': null},
      });
      expect(auth.stepSampleBucketMinutes, 60);
    });

    test('a string value (not an integer) falls back to 60', () {
      final auth = AuthService();
      auth.applyBackendUser({
        'featureFlags': {'stepSampleBucketMinutes': '5'},
      });
      expect(auth.stepSampleBucketMinutes, 60);
    });

    test('the last-accepted value survives a cold start via SharedPreferences',
        () async {
      final auth = AuthService();
      await auth.syncFromBackendUser({
        'featureFlags': {'stepSampleBucketMinutes': 15},
      });

      // A fresh instance restoring from prefs sees the persisted granularity
      // (cold-start syncs run before the me-fetch completes).
      final restored = AuthService();
      await restored.restoreSession();
      expect(restored.stepSampleBucketMinutes, 15);
    });
  });

  test('fine 5-min samples pass through buildStepSyncV2Payload unchanged', () {
    final samples = [
      StepSampleData(
        periodStart: DateTime.utc(2026, 5, 1, 9, 0),
        periodEnd: DateTime.utc(2026, 5, 1, 9, 5),
        steps: 100,
      ),
      StepSampleData(
        periodStart: DateTime.utc(2026, 5, 1, 9, 5),
        periodEnd: DateTime.utc(2026, 5, 1, 9, 10),
        steps: 60,
      ),
      StepSampleData(
        periodStart: DateTime.utc(2026, 5, 1, 9, 10),
        periodEnd: DateTime.utc(2026, 5, 1, 9, 15),
        steps: 40,
      ),
    ];

    final payload = BackendApiService.buildStepSyncV2Payload(
      stepData: StepData(steps: 200, date: DateTime(2026, 5, 1)),
      samples: samples,
    );

    final out = payload['samples'] as List;
    expect(out.length, 3);
    expect((out[0] as Map)['periodStart'], '2026-05-01T09:00:00.000Z');
    expect((out[0] as Map)['periodEnd'], '2026-05-01T09:05:00.000Z');
    expect((out[0] as Map)['steps'], 100);
    expect((out[2] as Map)['steps'], 40);
  });
}
