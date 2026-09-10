import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/utils/server_reel_preview.dart';

void main() {
  test(
    'probability boundaries preserve server weights, zero entries and omitted mass',
    () {
      const complete = {'A': .2, 'ZERO': 0.0, 'B': .8};
      expect(sampleServerProbability(complete, 0), 'A');
      expect(sampleServerProbability(complete, .199999), 'A');
      expect(sampleServerProbability(complete, .2), 'B');
      expect(sampleServerProbability(complete, .999999), 'B');
      const partial = {'INCLUDED': .2};
      expect(sampleServerProbability(partial, .1), isNull);
      expect(
        sampleServerProbability(partial, .1, requireComplete: false),
        'INCLUDED',
      );
      expect(
        sampleServerProbability(partial, .2, requireComplete: false),
        isNull,
      );
      expect(
        sampleServerProbability(partial, .999, requireComplete: false),
        isNull,
      );
    },
  );
  test('invalid or absent probabilities never invent decorative items', () {
    for (final raw in [
      null,
      {},
      [],
      {'A': double.nan},
      {'A': double.infinity},
      {'A': -1},
      {'A': 1.1},
      {'A': .6, 'B': .6},
      {'A': '1'},
      {'': 1},
    ]) {
      expect(sampleServerProbability(raw, .1), isNull, reason: '$raw');
    }
  });
  test(
    'conditional lists preserve truncation and reject duplicate or invalid entries',
    () {
      final odds = serverItemProbabilities([
        {'sku': 'ONE', 'p': .1},
        {'sku': 'TWO', 'p': .2},
      ], 'sku');
      expect(odds, {'ONE': .1, 'TWO': .2});
      expect(sampleServerProbability(odds, .9, requireComplete: false), isNull);
      for (final rows in [
        null,
        [
          {'sku': 'ONE', 'p': .2},
          {'sku': 'ONE', 'p': .3},
        ],
        [
          {'sku': 'ONE', 'p': double.nan},
        ],
        [
          {'sku': 'ONE', 'p': .7},
          {'sku': 'TWO', 'p': .7},
        ],
      ]) {
        expect(serverItemProbabilities(rows, 'sku'), isNull);
      }
    },
  );
}
