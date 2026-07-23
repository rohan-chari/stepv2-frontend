import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/utils/effect_polarity.dart';

// Pure-function classification shared by the race-detail ACTIVE EFFECTS groups
// and the races-tab badge cluster, so the two surfaces can never disagree about
// whether an effect on me is a boost or a rival attack. (This is the allowed
// unit-test exception: a pure function with many small cases.)
void main() {
  const me = 'me';

  test('self-cast effect is a boost', () {
    expect(
      effectIsBoost(type: 'RUNNERS_HIGH', sourceUserId: me, myUserId: me),
      isTrue,
    );
  });

  test('null source is a boost (unattributable, do not accuse nobody)', () {
    expect(
      effectIsBoost(type: 'LEG_CRAMP', sourceUserId: null, myUserId: me),
      isTrue,
    );
  });

  test('empty source is a boost', () {
    expect(
      effectIsBoost(type: 'LEG_CRAMP', sourceUserId: '', myUserId: me),
      isTrue,
    );
  });

  test('rival-cast group rallies land on me as boosts', () {
    for (final type in ['UPRISING', 'RALLY_FLAG']) {
      expect(
        effectIsBoost(type: type, sourceUserId: 'u1', myUserId: me),
        isTrue,
        reason: '$type is a group boost regardless of caster',
      );
    }
  });

  test('rival-cast non-rally effect is a debuff', () {
    expect(
      effectIsBoost(type: 'LEG_CRAMP', sourceUserId: 'u1', myUserId: me),
      isFalse,
    );
  });

  test('unknown/null type from a rival is still a debuff', () {
    expect(
      effectIsBoost(type: null, sourceUserId: 'u1', myUserId: me),
      isFalse,
    );
  });
}
