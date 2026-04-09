import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/models/step_sample_data.dart';

void main() {
  test('toJson includes source metadata for backend validation', () {
    final sample = StepSampleData(
      periodStart: DateTime.parse('2026-04-09T12:30:32.671Z'),
      periodEnd: DateTime.parse('2026-04-09T12:40:05.326Z'),
      steps: 985,
      sourceName: 'Apple Watch',
      sourceId: 'com.apple.health.123',
      sourceDeviceId: 'watch-device-1',
      deviceModel: 'Watch7,5',
      recordingMethod: 'automatic',
      metadata: const {'HKWasUserEntered': false},
    );

    expect(sample.toJson(), {
      'periodStart': '2026-04-09T12:30:32.671Z',
      'periodEnd': '2026-04-09T12:40:05.326Z',
      'steps': 985,
      'sourceName': 'Apple Watch',
      'sourceId': 'com.apple.health.123',
      'sourceDeviceId': 'watch-device-1',
      'deviceModel': 'Watch7,5',
      'recordingMethod': 'automatic',
      'metadata': {'HKWasUserEntered': false},
    });
  });
}
