import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/services/backend_api_service.dart';

void main() {
  test(
    'clientFeaturesHeader advertises race_leave for both compile branches',
    () {
      final tokens = BackendApiService.clientFeaturesHeader.split(',');
      expect(tokens, contains('race_leave'));

      // The literal must be in both ternary branches: a build with ads compiled
      // out still needs the stamped leaveAction field, rather than guessing from
      // locally-derived eligibility.
      final source = File(
        'lib/services/backend_api_service.dart',
      ).readAsStringSync();
      final start = source.indexOf('clientFeaturesHeader = _adsSupported');
      final end = source.indexOf('/// Replays a persisted results dismissal');
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      expect(
        RegExp('race_leave').allMatches(source.substring(start, end)),
        hasLength(2),
      );
    },
  );
}
