import 'package:flutter_test/flutter_test.dart';

import 'package:step_tracker/services/backend_api_service.dart';

void main() {
  test('race bootstrap cooldown projection replaces the previous race state', () {
    final raceA = RaceBootstrapResult(
      supported: true,
      powerupCooldowns: [
        {
          'powerupType': 'LEECH',
          'activeUntil': '2026-09-17T14:00:00.000Z',
          'nextUsableAt': '2026-09-17T15:00:00.000Z',
        },
      ],
    );
    final raceB = RaceBootstrapResult(
      supported: true,
      powerupCooldowns: const [],
    );

    expect(raceA.powerupCooldowns, hasLength(1));
    expect(raceB.powerupCooldowns, isEmpty);
    expect(raceB.powerupCooldowns, isNot(same(raceA.powerupCooldowns)));
  });
}
