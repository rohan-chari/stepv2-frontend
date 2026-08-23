import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/services/backend_api_service.dart';

void main() {
  test(
    'race payout capability is independently conditional in both branches',
    () {
      final source = File(
        'lib/services/backend_api_service.dart',
      ).readAsStringSync();
      final branchOccurrences = RegExp(
        r"_racePayoutDoubleSupported\s*\?\s*',race_payout_flat_50'\s*:\s*''",
      ).allMatches(source);

      expect(
        branchOccurrences,
        hasLength(2),
        reason:
            'the ads/no-ads ternary must independently append the race payout '
            'token in both branches',
      );
    },
  );

  test('request-specific replay never upgrades or downgrades capability', () {
    final capable =
        BackendApiService.clientFeaturesHeaderForRacePayoutDoubleCapability(
          true,
        ).split(',');
    final tokenless =
        BackendApiService.clientFeaturesHeaderForRacePayoutDoubleCapability(
          false,
        ).split(',');

    expect(
      capable.where((token) => token == 'race_payout_flat_50'),
      hasLength(1),
    );
    expect(tokenless, isNot(contains('race_payout_flat_50')));
    expect(tokenless, contains('characters'));
  });

  test(
    'both dedicated platform defines exist without a test-unit fallback',
    () {
      final source = File('lib/services/ad_service.dart').readAsStringSync();
      expect(source, contains("'ADMOB_RACE_PAYOUT_DOUBLE_AD_UNIT_ID'"));
      expect(source, contains("'ADMOB_RACE_PAYOUT_DOUBLE_AD_UNIT_ID_ANDROID'"));
      final getter = RegExp(
        r'static String get racePayoutDoubleAdUnitId \{([\s\S]*?)\n  \}',
      ).firstMatch(source);
      expect(getter, isNotNull);
      expect(getter!.group(1), isNot(contains('_testAdUnit')));
    },
  );
}
