import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/pocket_watch_sheet.dart';

/// §6.4 — the Pocket Watch two-mode sheet.
///
/// The capability gate is the load-bearing rule: a NEW client talking to an
/// OLDER backend must never offer targeted mode, because that backend ignores
/// `targetEffectId` and would silently extend the user's own buffs instead of
/// the rival debuff they picked and paid for.
void main() {
  const viewer = 'viewer-user-id';

  Map<String, dynamic> effect({
    required String id,
    required String type,
    String? sourceUserId = viewer,
    String? targetUserId = 'rival-1',
    bool onSelf = false,
    String? expiresAt = '2100-01-01T00:00:00.000Z',
  }) {
    return {
      'id': id,
      'type': type,
      'onSelf': onSelf,
      if (expiresAt != null) 'expiresAt': expiresAt,
      'targetUserId': targetUserId,
      'sourceUserId': sourceUserId,
    };
  }

  Map<String, dynamic> powerupData({
    bool? capability,
    List<Map<String, dynamic>>? effects,
    bool includeCapabilitiesKey = true,
    dynamic rawCapabilities,
  }) {
    return {
      if (includeCapabilitiesKey)
        'capabilities':
            rawCapabilities ??
            (capability == null
                ? <String, dynamic>{}
                : {'pocketWatchTargetEffect': capability}),
      'activeEffects': effects ?? const [],
    };
  }

  group('capability gate', () {
    test('targeted mode requires pocketWatchTargetEffect == true', () {
      expect(
        pocketWatchTargetingEnabled(powerupData(capability: true)),
        isTrue,
      );
    });

    test('capability false means legacy self mode only', () {
      expect(
        pocketWatchTargetingEnabled(powerupData(capability: false)),
        isFalse,
      );
    });

    test('missing capability flag means legacy self mode only', () {
      expect(pocketWatchTargetingEnabled(powerupData()), isFalse);
    });

    test('absent capabilities object (older backend) means self mode only', () {
      expect(
        pocketWatchTargetingEnabled(
          powerupData(includeCapabilitiesKey: false),
        ),
        isFalse,
      );
    });

    test('null powerupData means self mode only', () {
      expect(pocketWatchTargetingEnabled(null), isFalse);
    });

    test('malformed capabilities never throw and mean self mode only', () {
      for (final malformed in <dynamic>[
        'yes',
        42,
        <dynamic>[],
        {'pocketWatchTargetEffect': 'true'},
        {'pocketWatchTargetEffect': 1},
        {'pocketWatchTargetEffect': null},
      ]) {
        expect(
          pocketWatchTargetingEnabled(
            powerupData(rawCapabilities: malformed),
          ),
          isFalse,
          reason: '$malformed',
        );
      }
    });
  });

  group('eligible own-debuff selection', () {
    test('lists only timed harmful effects the viewer applied', () {
      final effects = pocketWatchTargetableEffects(
        powerupData(
          capability: true,
          effects: [
            effect(id: 'e1', type: 'LEG_CRAMP'),
            // Applied by someone else -> not mine to extend.
            effect(id: 'e2', type: 'WRONG_TURN', sourceUserId: 'other-user'),
            // A self-buff belongs to MY BUFFS, not MY DEBUFFS.
            effect(
              id: 'e3',
              type: 'RUNNERS_HIGH',
              onSelf: true,
              targetUserId: viewer,
            ),
            // Untimed -> nothing to extend.
            effect(id: 'e4', type: 'DETOUR_SIGN', expiresAt: null),
            // Not an allowlisted targeted type.
            effect(id: 'e5', type: 'HITCHHIKE'),
          ],
        ),
        viewerUserId: viewer,
      );

      expect(effects.map((e) => e.id), ['e1']);
    });

    test('every allowlisted type is eligible', () {
      const allowed = [
        'LEG_CRAMP',
        'WRONG_TURN',
        'DETOUR_SIGN',
        'SIGNAL_JAMMER',
        'LEECH',
        'RAINSTORM',
      ];
      final effects = pocketWatchTargetableEffects(
        powerupData(
          capability: true,
          effects: [
            for (var i = 0; i < allowed.length; i++)
              effect(id: 'e$i', type: allowed[i], targetUserId: 'rival-$i'),
          ],
        ),
        viewerUserId: viewer,
      );
      expect(effects.length, allowed.length);
      expect(effects.map((e) => e.type), containsAll(allowed));
    });

    test('Hitchhike can never be extended (§2 non-goal)', () {
      final effects = pocketWatchTargetableEffects(
        powerupData(
          capability: true,
          effects: [effect(id: 'e1', type: 'HITCHHIKE')],
        ),
        viewerUserId: viewer,
      );
      expect(effects, isEmpty);
    });

    test('an already-expired effect is not offered', () {
      final effects = pocketWatchTargetableEffects(
        powerupData(
          capability: true,
          effects: [
            effect(
              id: 'old',
              type: 'LEG_CRAMP',
              expiresAt: '2000-01-01T00:00:00.000Z',
            ),
          ],
        ),
        viewerUserId: viewer,
      );
      expect(effects, isEmpty);
    });

    test('RAINSTORM lists each affected rival as a SEPARATE entry', () {
      // Rainstorm is AoE and writes one row per rival, but extending it
      // prolongs exactly ONE row — so the sheet must make the single-target
      // scope explicit BEFORE the user pays.
      final effects = pocketWatchTargetableEffects(
        powerupData(
          capability: true,
          effects: [
            effect(id: 'r1', type: 'RAINSTORM', targetUserId: 'rival-a'),
            effect(id: 'r2', type: 'RAINSTORM', targetUserId: 'rival-b'),
            effect(id: 'r3', type: 'RAINSTORM', targetUserId: 'rival-c'),
          ],
        ),
        viewerUserId: viewer,
      );
      expect(effects.length, 3);
      expect(
        effects.map((e) => e.targetUserId),
        ['rival-a', 'rival-b', 'rival-c'],
      );
      // Distinct selectable ids, not one collapsed "Rainstorm" line.
      expect(effects.map((e) => e.id).toSet().length, 3);
    });

    test('malformed effect entries are skipped rather than throwing', () {
      final effects = pocketWatchTargetableEffects(
        {
          'capabilities': {'pocketWatchTargetEffect': true},
          'activeEffects': [
            null,
            'not-a-map',
            42,
            {'type': 'LEG_CRAMP'}, // no id
            {'id': 'no-type'},
            {'id': 'bad-date', 'type': 'LEG_CRAMP', 'expiresAt': 'nonsense'},
            effect(id: 'good', type: 'LEG_CRAMP'),
          ],
        },
        viewerUserId: viewer,
      );
      expect(effects.map((e) => e.id), ['good']);
    });

    test('a null powerupData yields no targets and does not throw', () {
      expect(pocketWatchTargetableEffects(null, viewerUserId: viewer), isEmpty);
    });

    test('a null viewer id yields no targets (cannot prove ownership)', () {
      final effects = pocketWatchTargetableEffects(
        powerupData(
          capability: true,
          effects: [effect(id: 'e1', type: 'LEG_CRAMP')],
        ),
        viewerUserId: null,
      );
      expect(effects, isEmpty);
    });
  });

  group('eligible self-buff count', () {
    test('counts timed buffs on the viewer only', () {
      final count = pocketWatchSelfBuffCount(
        powerupData(
          effects: [
            effect(
              id: 'b1',
              type: 'RUNNERS_HIGH',
              onSelf: true,
              targetUserId: viewer,
            ),
            effect(
              id: 'b2',
              type: 'STEALTH_MODE',
              onSelf: true,
              targetUserId: viewer,
            ),
            // A debuff I placed on a rival is not a self-buff.
            effect(id: 'd1', type: 'LEG_CRAMP'),
            // Untimed self effect: nothing to extend.
            effect(
              id: 'b3',
              type: 'FANNY_PACK',
              onSelf: true,
              targetUserId: viewer,
              expiresAt: null,
            ),
          ],
        ),
        viewerUserId: viewer,
      );
      expect(count, 2);
    });

    test('is zero for null/malformed data', () {
      expect(pocketWatchSelfBuffCount(null, viewerUserId: viewer), 0);
      expect(
        pocketWatchSelfBuffCount(
          {'activeEffects': 'nope'},
          viewerUserId: viewer,
        ),
        0,
      );
    });
  });

  group('sheet widget', () {
    Future<void> pump(
      WidgetTester tester, {
      required Map<String, dynamic>? data,
      List<int> costs = const [0, 15, 45, 135],
      int coins = 1000,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PocketWatchSheet(
              powerupData: data,
              viewerUserId: viewer,
              myCoins: coins,
              tierLabels: const [
                'Extend 1h',
                'Extend 1.5h',
                'Extend 2h',
                'Extend 3h',
              ],
              costForLevel: (level) => costs[level],
              onConfirm: (_, _) {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }

    testWidgets('without the capability only MY BUFFS is offered',
        (tester) async {
      await pump(
        tester,
        data: powerupData(
          effects: [
            effect(
              id: 'b1',
              type: 'RUNNERS_HIGH',
              onSelf: true,
              targetUserId: viewer,
            ),
          ],
        ),
      );
      expect(find.text('MY BUFFS'), findsOneWidget);
      expect(find.text('MY DEBUFFS'), findsNothing);
    });

    testWidgets('with the capability both modes are offered', (tester) async {
      await pump(
        tester,
        data: powerupData(
          capability: true,
          effects: [
            effect(
              id: 'b1',
              type: 'RUNNERS_HIGH',
              onSelf: true,
              targetUserId: viewer,
            ),
            effect(id: 'e1', type: 'LEG_CRAMP'),
          ],
        ),
      );
      expect(find.text('MY BUFFS'), findsOneWidget);
      expect(find.text('MY DEBUFFS'), findsOneWidget);
    });

    testWidgets('a mode with zero eligible effects is disabled with copy',
        (tester) async {
      await pump(tester, data: powerupData(capability: true));
      // Both counts are zero: the sheet explains rather than silently failing.
      expect(find.byKey(const Key('pocket-watch-buffs-empty')), findsOneWidget);
    });

    testWidgets('targeted mode requires selecting one effect before confirming',
        (tester) async {
      String? confirmedEffectId;
      var confirmCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PocketWatchSheet(
              powerupData: powerupData(
                capability: true,
                effects: [
                  effect(id: 'e1', type: 'LEG_CRAMP', targetUserId: 'rival-1'),
                  effect(id: 'e2', type: 'LEECH', targetUserId: 'rival-2'),
                ],
              ),
              viewerUserId: viewer,
              myCoins: 1000,
              tierLabels: const ['a', 'b', 'c', 'd'],
              costForLevel: (level) => 0,
              onConfirm: (level, effectId) {
                confirmCount++;
                confirmedEffectId = effectId;
              },
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('MY DEBUFFS'));
      await tester.pump(const Duration(milliseconds: 200));

      // No selection yet -> the tier buttons must not fire a use.
      await tester.tap(find.byKey(const Key('pocket-watch-tier-0')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(confirmCount, 0);

      await tester.tap(find.byKey(const Key('pocket-watch-effect-e2')));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byKey(const Key('pocket-watch-tier-0')));
      await tester.pump(const Duration(milliseconds: 200));

      expect(confirmCount, 1);
      expect(confirmedEffectId, 'e2');
    });

    testWidgets('self mode confirms with a null effect id (legacy request)',
        (tester) async {
      String? capturedEffectId = 'sentinel';
      var confirmCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PocketWatchSheet(
              powerupData: powerupData(
                capability: true,
                effects: [
                  effect(
                    id: 'b1',
                    type: 'RUNNERS_HIGH',
                    onSelf: true,
                    targetUserId: viewer,
                  ),
                ],
              ),
              viewerUserId: viewer,
              myCoins: 1000,
              tierLabels: const ['a', 'b', 'c', 'd'],
              costForLevel: (level) => 0,
              onConfirm: (level, effectId) {
                confirmCount++;
                capturedEffectId = effectId;
              },
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const Key('pocket-watch-tier-0')));
      await tester.pump(const Duration(milliseconds: 200));

      expect(confirmCount, 1);
      // Legacy self-buff request: NO targetEffectId is sent.
      expect(capturedEffectId, isNull);
    });

    testWidgets('an unaffordable tier is disabled', (tester) async {
      var confirmCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PocketWatchSheet(
              powerupData: powerupData(
                capability: true,
                effects: [
                  effect(
                    id: 'b1',
                    type: 'RUNNERS_HIGH',
                    onSelf: true,
                    targetUserId: viewer,
                  ),
                ],
              ),
              viewerUserId: viewer,
              myCoins: 10,
              tierLabels: const ['a', 'b', 'c', 'd'],
              costForLevel: (level) => level == 0 ? 0 : 999,
              onConfirm: (_, _) => confirmCount++,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const Key('pocket-watch-tier-3')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(confirmCount, 0);
    });

    testWidgets('renders safely when powerupData is entirely absent',
        (tester) async {
      await pump(tester, data: null);
      expect(find.byType(PocketWatchSheet), findsOneWidget);
      expect(find.text('MY DEBUFFS'), findsNothing);
    });
  });
}
