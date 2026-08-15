import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/constants/powerup_copy.dart';
import 'package:step_tracker/widgets/case_opening_strip.dart';
import 'package:step_tracker/widgets/powerup_icon.dart';

/// Batch 2026-08-09 items 1 / 6 / 8 — bundled fallback copy + case decoy reel.
///
/// These are the strings a FROZEN client shows before (or without) a copy-
/// catalog fetch. They were already stale against the live backend; items 1, 6
/// and 8 change the backend values, so the bundled fallbacks are re-pinned to
/// match. The catalog stays authoritative — the override tests below prove the
/// bundled values are still only level 3 of the resolution order.
/// Pumps one freshly-planted reel. The [seed] key forces a NEW State each
/// call — without it Flutter reuses the element and the "sample" is one reel
/// repeated, which is not enough draws to see the rare pool.
Future<void> _pumpStrip(WidgetTester tester, {int seed = 0}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CaseOpeningStrip(
          key: ValueKey('reel-$seed'),
          resultType: '',
          resultRarity: 'COMMON',
          onComplete: () {},
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Every decoy type the reel planted this build, sampled across many reels so
/// the assertion doesn't ride on one random draw.
Future<Set<String>> _sampleDecoyTypes(WidgetTester tester, int reels) async {
  final seen = <String>{};
  for (var i = 0; i < reels; i++) {
    await _pumpStrip(tester, seed: i);
    seen.addAll(
      tester
          .widgetList<PowerupIcon>(
            find.byType(PowerupIcon, skipOffstage: false),
          )
          .map((w) => w.type),
    );
  }
  return seen;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PowerupCopy.resetForTest();
  });

  group('item 1 — Wrong Turn / Leg Cramp 15-minute upgrade ladder', () {
    test('LEG_CRAMP description says 1 hour, not 2', () {
      final description = PowerupCopy.descriptionFor('LEG_CRAMP');
      expect(description, contains('1 hour'));
      expect(description, isNot(contains('2 hours')));
    });

    test('LEG_CRAMP tiers are 1h / 1h 15m / 1h 30m / 1h 45m', () {
      expect(PowerupCopy.upgradeTierLabelsFor('LEG_CRAMP'), [
        'Freeze 1h',
        'Freeze 1h 15m',
        'Freeze 1h 30m',
        'Freeze 1h 45m',
      ]);
    });

    test('WRONG_TURN tiers use the same 15-minute ladder', () {
      expect(PowerupCopy.upgradeTierLabelsFor('WRONG_TURN'), [
        'Reverse 1h',
        'Reverse 1h 15m',
        'Reverse 1h 30m',
        'Reverse 1h 45m',
      ]);
      // The base description already said 1 hour; it must stay that way.
      expect(PowerupCopy.descriptionFor('WRONG_TURN'), contains('1 hour'));
    });

    test('no bundled ladder still advertises the retired 2h+ durations', () {
      for (final type in [
        'LEG_CRAMP',
        'WRONG_TURN',
        'RUNNERS_HIGH',
        'DETOUR_SIGN',
        'STEALTH_MODE',
      ]) {
        final tiers = PowerupCopy.upgradeTierLabelsFor(type)!;
        for (final label in tiers) {
          expect(
            label,
            isNot(anyOf(contains('2h'), contains('3h'), contains('4h'))),
            reason: '$type tier "$label" still names a pre-nerf duration',
          );
        }
      }
    });

    // 2026-08-15: Stealth Mode joined the 15-min upgrade ladder alongside
    // Leg Cramp / Wrong Turn, superseding the 1/2/3/4h values this test used
    // to pin.
    test('STEALTH_MODE ladder matches the real 1h/1h15m/1h30m/1h45m backend values', () {
      expect(PowerupCopy.upgradeTierLabelsFor('STEALTH_MODE'), [
        'Hide 1h',
        'Hide 1h 15m',
        'Hide 1h 30m',
        'Hide 1h 45m',
      ]);
    });
  });

  group('item 8 — Lucky Horseshoe', () {
    test('has no bundled upgrade tiers, so the upgrade UI is hidden', () {
      expect(PowerupCopy.upgradeTierLabelsFor('LUCKY_HORSESHOE'), isNull);
      expect(PowerupCopy.isUpgradeable('LUCKY_HORSESHOE'), isFalse);
    });

    test('other upgradeable types are untouched by the horseshoe removal', () {
      for (final type in [
        'PROTEIN_SHAKE',
        'SHORTCUT',
        'RUNNERS_HIGH',
        'LEG_CRAMP',
        'WRONG_TURN',
        'STEALTH_MODE',
        'COMPRESSION_SOCKS',
        'POCKET_WATCH',
      ]) {
        expect(PowerupCopy.isUpgradeable(type), isTrue, reason: type);
      }
    });

    test('description promises a guaranteed rare and no self-roll', () {
      final description = PowerupCopy.descriptionFor(
        'LUCKY_HORSESHOE',
      ).toLowerCase();
      expect(description, contains('rare'));
      expect(description, contains('horseshoe'));
    });

    testWidgets('FANNY_PACK is gone from the decoy reel', (tester) async {
      final seen = await _sampleDecoyTypes(tester, 40);
      expect(
        seen,
        isNot(contains('FANNY_PACK')),
        reason: 'Fanny Pack is undroppable; the reel must stop advertising it',
      );
      // Sanity: the rare pool is still being sampled at all.
      expect(seen, contains('LUCKY_HORSESHOE'));
    });
  });

  group('item 6 — Power Outage becomes a rare box drop', () {
    testWidgets('POWER_OUTAGE appears in the decoy reel', (tester) async {
      final seen = await _sampleDecoyTypes(tester, 40);
      expect(seen, contains('POWER_OUTAGE'));
    });

    testWidgets('POWER_OUTAGE decoys carry the RARE bundled rarity', (
      tester,
    ) async {
      // The bundled rarity table is the fallback when the backend sends no
      // rarityByType. A missing entry would silently paint the tile COMMON.
      var sawRareOutage = false;
      for (var i = 0; i < 40 && !sawRareOutage; i++) {
        await _pumpStrip(tester, seed: i);
        final icons = tester
            .widgetList<PowerupIcon>(
              find.byType(PowerupIcon, skipOffstage: false),
            )
            .toList();
        final tiles = tester
            .widgetList<CaseReelTile>(
              find.byType(CaseReelTile, skipOffstage: false),
            )
            .toList();
        expect(icons.length, tiles.length);
        for (var t = 0; t < icons.length; t++) {
          if (icons[t].type == 'POWER_OUTAGE') {
            expect(
              tiles[t].rarity,
              'RARE',
              reason: 'POWER_OUTAGE missing from the bundled rarity table',
            );
            sawRareOutage = true;
          }
        }
      }
      expect(
        sawRareOutage,
        isTrue,
        reason: 'never sampled a POWER_OUTAGE tile',
      );
    });
  });

  group('the catalog still overrides every bundled fallback', () {
    test('a server snapshot wins for description and tiers', () async {
      await PowerupCopy.refresh(
        fetch: () async => {
          'version': '2026-08-09T00:00:00.000Z',
          'powerups': [
            {
              'type': 'LEG_CRAMP',
              'name': 'Leg Cramp',
              'description': 'Server description',
              'upgradeTierLabels': ['A', 'B', 'C', 'D'],
            },
            {
              'type': 'LUCKY_HORSESHOE',
              'name': 'Lucky Horseshoe',
              'description': 'Server horseshoe',
              'upgradeTierLabels': ['W', 'X', 'Y', 'Z'],
            },
          ],
        },
      );

      expect(PowerupCopy.descriptionFor('LEG_CRAMP'), 'Server description');
      expect(PowerupCopy.upgradeTierLabelsFor('LEG_CRAMP'), [
        'A',
        'B',
        'C',
        'D',
      ]);
      // Dropping the bundled horseshoe ladder must not stop a backend that
      // still serves one from being honoured (version skew, both directions).
      expect(PowerupCopy.upgradeTierLabelsFor('LUCKY_HORSESHOE'), [
        'W',
        'X',
        'Y',
        'Z',
      ]);
      expect(PowerupCopy.isUpgradeable('LUCKY_HORSESHOE'), isTrue);
    });
  });
}
