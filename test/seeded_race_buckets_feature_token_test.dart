import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/services/backend_api_service.dart';

void main() {
  test(
    'seeded_race_buckets is advertised by both client-feature header branches',
    () {
      expect(
        BackendApiService.clientFeaturesHeader.split(','),
        contains('seeded_race_buckets'),
      );

      // iOS and Android can each compile with or without an ad unit. Keep the
      // seeded-bucket capability in both branches so either platform can be
      // recognized by the backend regardless of its ad configuration.
      final source = File(
        'lib/services/backend_api_service.dart',
      ).readAsStringSync();
      final start = source.indexOf('clientFeaturesHeader = _adsSupported');
      final end = source.indexOf('/// Replays a persisted results dismissal');
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));

      final headerDefinition = source.substring(start, end);
      expect(
        RegExp('seeded_race_buckets').allMatches(headerDefinition),
        hasLength(2),
      );
    },
  );
}
