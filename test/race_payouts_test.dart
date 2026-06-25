import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/models/race_payouts.dart';

void main() {
  group('parsePayoutTiers', () {
    test('prefers payoutTiers and sorts by placement, dropping zero amounts', () {
      final tiers = parsePayoutTiers({
        'payoutTiers': [
          {'placement': 2, 'amount': 120},
          {'placement': 1, 'amount': 420},
          {'placement': 3, 'amount': 0}, // dropped
        ],
      });
      expect(tiers, [
        (placement: 1, amount: 420),
        (placement: 2, amount: 120),
      ]);
    });

    test('falls back to legacy first/second/third when tiers are absent', () {
      final tiers = parsePayoutTiers({
        'payouts': {'first': 210, 'second': 60, 'third': 30},
      });
      expect(tiers, [
        (placement: 1, amount: 210),
        (placement: 2, amount: 60),
        (placement: 3, amount: 30),
      ]);
    });

    test('winner-takes-all legacy shape yields a single tier', () {
      final tiers = parsePayoutTiers({
        'payouts': {'first': 100, 'second': 0, 'third': 0},
      });
      expect(tiers, [(placement: 1, amount: 100)]);
    });

    test('coerces numeric strings and doubles', () {
      final tiers = parsePayoutTiers({
        'payoutTiers': [
          {'placement': 1, 'amount': '50'},
          {'placement': 2, 'amount': 25.0},
        ],
      });
      expect(tiers, [
        (placement: 1, amount: 50),
        (placement: 2, amount: 25),
      ]);
    });

    test('returns empty for null race or missing payout data', () {
      expect(parsePayoutTiers(null), isEmpty);
      expect(parsePayoutTiers({'name': 'x'}), isEmpty);
    });
  });

  group('payoutPlacementLabel', () {
    test('uses correct ordinal suffixes', () {
      expect(payoutPlacementLabel(1), '1ST');
      expect(payoutPlacementLabel(2), '2ND');
      expect(payoutPlacementLabel(3), '3RD');
      expect(payoutPlacementLabel(4), '4TH');
      expect(payoutPlacementLabel(11), '11TH');
      expect(payoutPlacementLabel(12), '12TH');
      expect(payoutPlacementLabel(13), '13TH');
      expect(payoutPlacementLabel(21), '21ST');
    });
  });

  group('payout preset options', () {
    test('offers the four selectable presets in order', () {
      expect(payoutPresetOptions.map((o) => o.$2), [
        'WINNER_TAKES_ALL',
        'TOP3_70_20_10',
        'TOP_HALF',
        'ALL_BUT_LAST',
      ]);
    });

    test('every selectable preset has help text', () {
      for (final option in payoutPresetOptions) {
        expect(payoutHelpText(option.$2), isNotEmpty);
      }
    });
  });
}
