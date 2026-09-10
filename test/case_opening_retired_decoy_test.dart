import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mystery-box reel contains no compiled product pool', () {
    final source = File(
      'lib/widgets/case_opening_strip.dart',
    ).readAsStringSync();
    final pools = RegExp(
      r'static const _commonTypes = \[(.*?)static const _rareTypes = \[(.*?)\];',
      dotAll: true,
    ).firstMatch(source);

    expect(
      pools,
      isNull,
      reason: 'backend probabilities exclusively determine candidates',
    );
    expect(source, contains('sampleServerProbability'));
    expect(source, contains("'reelPreviewAvailable'"));
  });
}
