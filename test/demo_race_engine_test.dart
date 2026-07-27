import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/demo/demo_race_engine.dart';
import 'package:step_tracker/demo/demo_race_script.dart';

/// Spec §10 items 17, 23 and 24 — the three properties an integration test
/// structurally cannot express, because they are about the *engine's* internal
/// arithmetic across time, not about anything the screen renders.

DemoRaceEngine _engine({DateTime? startedAt}) => DemoRaceEngine(
  myUserId: 'real-user-1',
  myDisplayName: 'Rohan',
  startedAt: startedAt ?? DateTime(2026, 7, 26, 12),
);

/// Plays the whole script through the engine's public surface, exactly as the
/// host would drive it. Returns the final standings.
List<Map<String, dynamic>> _playFullScript(DemoRaceEngine e) {
  e.acknowledgeIntro();
  final boxes = DemoRaceEngine.mysteryBoxIds;
  e.openBox(boxes[0]);
  e.usePowerup(powerupId: boxes[0]);
  e.openBox(boxes[1]);
  e.usePowerup(powerupId: boxes[1]);
  e.resolveScriptedAttack();
  e.acknowledgeAttack();
  e.usePowerup(
    powerupId: DemoRaceEngine.shortcutPowerupId,
    targetUserId: DemoRaceEngine.rivalLeaderUserId,
  );
  e.completeRace();
  return e.participants;
}

void main() {
  group('engine determinism (§10.17)', () {
    test('two full runs produce identical standings', () {
      final a = _playFullScript(_engine());
      final b = _playFullScript(_engine());

      expect(
        a.map((p) => '${p['userId']}:${p['totalSteps']}').toList(),
        b.map((p) => '${p['userId']}:${p['totalSteps']}').toList(),
      );
      // And there is no RNG hiding in the roll order either.
      expect(a.first['userId'], 'real-user-1');
    });

    test('the box rolls are scripted, never random', () {
      for (var i = 0; i < 5; i++) {
        final e = _engine();
        final boxes = DemoRaceEngine.mysteryBoxIds;
        expect(e.openBox(boxes[0])['result']['type'], 'PROTEIN_SHAKE');
        expect(e.openBox(boxes[1])['result']['type'], 'COMPRESSION_SOCKS');
      }
    });

    test('roll order follows the OPEN order, not the slot id', () {
      // A user who taps the second box first still gets the boost first, so
      // the script stays reachable (spec §5.7b).
      final e = _engine();
      final boxes = DemoRaceEngine.mysteryBoxIds;
      expect(e.openBox(boxes[1])['result']['type'], 'PROTEIN_SHAKE');
      expect(e.openBox(boxes[0])['result']['type'], 'COMPRESSION_SOCKS');
    });
  });

  group('clock arithmetic across the floor boundary (§10.23)', () {
    final t0 = DateTime(2026, 7, 26, 12);

    test('ticks down in real time above the floor', () {
      final e = _engine(startedAt: t0);
      expect(e.remainingAt(t0), const Duration(minutes: 2));
      expect(e.remainingAt(t0.add(const Duration(seconds: 30))),
          const Duration(seconds: 90));
      expect(e.remainingAt(t0.add(const Duration(seconds: 99))),
          const Duration(seconds: 21));
    });

    test('floors at 0:20 and never expires while the user reads', () {
      final e = _engine(startedAt: t0);
      expect(e.remainingAt(t0.add(const Duration(seconds: 100))),
          DemoRaceEngine.clockFloor);
      expect(e.remainingAt(t0.add(const Duration(seconds: 600))),
          DemoRaceEngine.clockFloor);
      expect(e.remainingAt(t0.add(const Duration(hours: 3))),
          DemoRaceEngine.clockFloor);
    });

    test('never re-pins upward, even if wall time goes backwards', () {
      final e = _engine(startedAt: t0);
      final at60 = e.remainingAt(t0.add(const Duration(seconds: 60)));
      // A backwards clock (NTP correction, timezone change) must not raise it.
      final at10 = e.remainingAt(t0.add(const Duration(seconds: 10)));
      expect(at10 <= at60, isTrue);
      expect(at10, at60);
    });

    test('the floor lifts on the final beat and runs to 0:00', () {
      final e = _engine(startedAt: t0);
      final idle = t0.add(const Duration(minutes: 10));
      expect(e.remainingAt(idle), DemoRaceEngine.clockFloor);

      e.startFinalCountdown(idle);
      expect(e.remainingAt(idle), DemoRaceEngine.finalCountdown);
      expect(
        e.remainingAt(idle.add(const Duration(seconds: 3))),
        const Duration(seconds: 3),
      );
      expect(
        e.remainingAt(idle.add(const Duration(seconds: 30))),
        Duration.zero,
      );
      // Still monotonic through the transition.
      expect(e.remainingAt(idle), Duration.zero);
    });

    test('a completed race reads 0:00', () {
      final e = _engine(startedAt: t0);
      e.completeRace();
      expect(e.remainingAt(t0), Duration.zero);
    });
  });

  group('step math for steal / boost / block (§10.24)', () {
    test('the boost adds 1,500 and leaves the user in 2nd', () {
      final e = _engine();
      e.acknowledgeIntro();
      final before = e.stepsFor(e.myUserId);
      final boxes = DemoRaceEngine.mysteryBoxIds;
      e.openBox(boxes[0]);
      e.usePowerup(powerupId: boxes[0]);

      expect(e.stepsFor(e.myUserId), before + 1500);
      expect(e.myPlacement, 2, reason: 'the leader drifted; the race is live');
    });

    test('the blocked attack costs the user nothing', () {
      final e = _engine();
      e.acknowledgeIntro();
      final boxes = DemoRaceEngine.mysteryBoxIds;
      e.openBox(boxes[0]);
      e.usePowerup(powerupId: boxes[0]);
      e.openBox(boxes[1]);
      e.usePowerup(powerupId: boxes[1]);

      final before = e.stepsFor(e.myUserId);
      final outcome = e.resolveScriptedAttack();

      expect(outcome['result']['blocked'], isTrue);
      expect(outcome['result']['outcome'], 'BLOCKED');
      expect(e.stepsFor(e.myUserId), before,
          reason: 'the shield ate the steal');
    });

    test('the Shortcut takes 1,000 from the leader and wins the race', () {
      final e = _engine();
      e.acknowledgeIntro();
      final boxes = DemoRaceEngine.mysteryBoxIds;
      e.openBox(boxes[0]);
      e.usePowerup(powerupId: boxes[0]);
      e.openBox(boxes[1]);
      e.usePowerup(powerupId: boxes[1]);
      e.resolveScriptedAttack();
      e.acknowledgeAttack();

      final leaderBefore = e.stepsFor(DemoRaceEngine.rivalLeaderUserId);
      final meBefore = e.stepsFor(e.myUserId);

      final result = e.usePowerup(
        powerupId: DemoRaceEngine.shortcutPowerupId,
        targetUserId: DemoRaceEngine.rivalLeaderUserId,
      );

      expect(result['result']['stepsStolen'], 1000);
      expect(e.stepsFor(DemoRaceEngine.rivalLeaderUserId), leaderBefore - 1000);
      expect(e.stepsFor(e.myUserId), meBefore + 1000);
      expect(e.myPlacement, 1);
    });

    test('the user wins even if they target the WRONG rival', () {
      // "The Shortcut always steals exactly enough" (§5.2). No path loses.
      final e = _engine();
      e.acknowledgeIntro();
      final boxes = DemoRaceEngine.mysteryBoxIds;
      e.openBox(boxes[0]);
      e.usePowerup(powerupId: boxes[0]);
      e.openBox(boxes[1]);
      e.usePowerup(powerupId: boxes[1]);
      e.resolveScriptedAttack();
      e.acknowledgeAttack();

      e.usePowerup(
        powerupId: DemoRaceEngine.shortcutPowerupId,
        targetUserId: 'demo-priya',
      );
      e.completeRace();

      expect(e.myPlacement, 1);
      expect(e.participants.first['userId'], e.myUserId);
    });

    test('every demo action reports coinsSpent: 0 (§5.5b belt and braces)', () {
      final e = _engine();
      e.acknowledgeIntro();
      final boxes = DemoRaceEngine.mysteryBoxIds;
      for (final id in boxes) {
        expect(e.openBox(id)['result']['coinsSpent'], 0);
      }
      for (final id in [...boxes, DemoRaceEngine.shortcutPowerupId]) {
        final r = e.usePowerup(
          powerupId: id,
          targetUserId: DemoRaceEngine.rivalLeaderUserId,
        );
        expect(r['result']['coinsSpent'], 0);
      }
    });
  });

  group('beats are state-driven (§5.7b)', () {
    test('the beat advances with the engine state, not a tap counter', () {
      final e = _engine();
      expect(e.beat, DemoBeat.intro);
      e.acknowledgeIntro();
      expect(e.beat, DemoBeat.openBox);

      final boxes = DemoRaceEngine.mysteryBoxIds;
      e.openBox(boxes[0]);
      expect(e.beat, DemoBeat.useBoost);
      e.usePowerup(powerupId: boxes[0]);
      expect(e.beat, DemoBeat.openSecondBox);
      e.openBox(boxes[1]);
      expect(e.beat, DemoBeat.useShield);
      e.usePowerup(powerupId: boxes[1]);
      expect(e.beat, DemoBeat.blockedAttack);
      e.resolveScriptedAttack();
      e.acknowledgeAttack();
      expect(e.beat, DemoBeat.useShortcut);
      e.usePowerup(
        powerupId: DemoRaceEngine.shortcutPowerupId,
        targetUserId: DemoRaceEngine.rivalLeaderUserId,
      );
      expect(e.beat, DemoBeat.finish);
      e.completeRace();
      expect(e.beat, DemoBeat.win);
    });

    test('opening both boxes at once satisfies beats 2 and 4 together', () {
      final e = _engine();
      e.acknowledgeIntro();
      final boxes = DemoRaceEngine.mysteryBoxIds;
      e.openBox(boxes[0]);
      e.openBox(boxes[1]);
      // Beat 2 and beat 4 are both satisfied; the coach advances to the first
      // still-incomplete goal, which is "use the boost".
      expect(e.beat, DemoBeat.useBoost);
    });

    test('using the Shortcut early never dead-ends the script', () {
      final e = _engine();
      e.acknowledgeIntro();
      e.usePowerup(
        powerupId: DemoRaceEngine.shortcutPowerupId,
        targetUserId: DemoRaceEngine.rivalLeaderUserId,
      );
      // Still asks for the boxes; the script remains reachable.
      expect(e.beat, DemoBeat.openBox);
      final boxes = DemoRaceEngine.mysteryBoxIds;
      e.openBox(boxes[0]);
      e.usePowerup(powerupId: boxes[0]);
      e.openBox(boxes[1]);
      e.usePowerup(powerupId: boxes[1]);
      e.resolveScriptedAttack();
      e.acknowledgeAttack();
      expect(e.beat, DemoBeat.finish);
      e.completeRace();
      expect(e.myPlacement, 1);
    });
  });

  group('identity is injected, never hardcoded (§5.5b / G2)', () {
    test('the participant list carries the REAL user id and name', () {
      final e = DemoRaceEngine(
        myUserId: 'usr_abc123',
        myDisplayName: 'Wandering Otter42',
      );
      final me = e.participants.firstWhere((p) => p['userId'] == 'usr_abc123');
      expect(me['displayName'], 'Wandering Otter42');
      expect(e.myUserId, 'usr_abc123');
      // And the rivals are never the real user.
      expect(
        e.participants.where((p) => p['userId'] == 'usr_abc123').length,
        1,
      );
    });
  });

  group('wire shapes (§6.4)', () {
    test('progress carries the inventory the real screen parses', () {
      final e = _engine();
      final progress = e.raceProgress(DateTime(2026, 7, 26, 12));
      final powerupData = progress['powerupData'] as Map<String, dynamic>;
      expect(powerupData['enabled'], isTrue);
      expect(powerupData['powerupSlots'], 3);
      expect(powerupData['queuedBoxCount'], 0);
      final inventory = (powerupData['inventory'] as List)
          .cast<Map<String, dynamic>>();
      expect(inventory.length, 3);
      expect(
        inventory.where((p) => p['status'] == 'MYSTERY_BOX').length,
        2,
      );
      expect(
        inventory.firstWhere((p) => p['status'] == 'HELD')['type'],
        'SHORTCUT',
      );
    });

    test('details carry an ACTIVE, ACCEPTED, zero-buy-in race', () {
      final e = _engine();
      final details = e.raceDetails(DateTime(2026, 7, 26, 12));
      expect(details['status'], 'ACTIVE');
      expect(details['myStatus'], 'ACCEPTED');
      expect(details['buyInAmount'], 0);
      expect(details['id'], DemoRaceEngine.raceId);
      expect(DateTime.tryParse(details['endsAt'] as String), isNotNull);
    });

    test('a completed race names the user as the winner', () {
      final e = _engine();
      _playFullScript(e);
      final details = e.raceDetails(DateTime(2026, 7, 26, 12));
      expect(details['status'], 'COMPLETED');
      expect(
        (details['winner'] as Map<String, dynamic>)['userId'],
        e.myUserId,
      );
    });
  });
}
