import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'retired Trail Magnet is absent from every mystery-box reel decoy pool',
    () {
      final source = File(
        'lib/widgets/case_opening_strip.dart',
      ).readAsStringSync();
      final pools = RegExp(
        r'static const _commonTypes = \[(.*?)static const _rareTypes = \[(.*?)\];',
        dotAll: true,
      ).firstMatch(source);

      expect(
        pools,
        isNotNull,
        reason: 'the reel decoy pools must remain inspectable',
      );
      expect(
        pools!.group(0),
        isNot(contains("'TRAIL_MAGNET'")),
        reason:
            'retired powerups must not be advertised as possible reel drops',
      );
    },
  );
}
