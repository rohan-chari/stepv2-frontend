import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/screens/case_opening_screen.dart';

/// Position-aware drops spec §6 ("Backward compatibility — the one hard
/// invariant").
///
/// After this backend change, `powerupData.dropOdds.byType` becomes
/// per-player: an excluded type reports `0` or vanishes from the map, and the
/// remaining weights differ from player to player. `rarity` is guaranteed
/// unchanged, and it alone decides whether the sheet exists at all
/// (`odds_sheet.dart` returns null — hiding the ENTIRE sheet — when `rarity`
/// fails the sum-to-1.0 ± 0.01 check).
///
/// These tests pin that contract through the real screen: every new `byType`
/// shape the backend can now emit must render, and none of them may take the
/// sheet down with it.
Future<void> _pumpCaseOpening(
  WidgetTester tester, {
  Map<String, dynamic>? dropOdds,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: CaseOpeningScreen(
        openMysteryBox: () async => const {
          'result': {'type': 'SHORTCUT', 'rarity': 'RARE'},
        },
        dropOdds: dropOdds,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _openSheet(WidgetTester tester) async {
  expect(find.text('ODDS'), findsOneWidget);
  await tester.tap(find.text('ODDS'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.text('DROP ODDS'), findsOneWidget);
}

/// The `rarity` block the feature promises never to touch.
const _rarity = {'COMMON': 0.31, 'UNCOMMON': 0.31, 'RARE': 0.38};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a byType entry of exactly 0.0 (leader-excluded type) renders as '
      'an honest 0% row and does not hide the sheet', (
    WidgetTester tester,
  ) async {
    await _pumpCaseOpening(
      tester,
      dropOdds: const {
        'configVersion': 12,
        'position': 1,
        'totalParticipants': 7,
        'rarity': _rarity,
        // RED_CARD / SECOND_WIND are hard-excluded for the step leader.
        'byType': {
          'SHORTCUT': 0.12,
          'RED_CARD': 0.0,
          'SECOND_WIND': 0.0,
          'RUNNERS_HIGH': 0.04,
        },
      },
    );

    await _openSheet(tester);

    expect(find.text('BY POWERUP'), findsOneWidget);
    expect(find.text('12%'), findsOneWidget);
    expect(find.text('4%'), findsOneWidget);
    // A true zero prints "0%" — the item genuinely cannot drop for this
    // player, so this is accurate rather than the misleading rounding
    // formatOddsPercent guards against for small non-zero values.
    expect(find.text('0%'), findsNWidgets(2));
    // The rarity rows are untouched by within-tier filtering.
    expect(find.text('31%'), findsNWidgets(2));
    expect(find.text('38%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a byType map that OMITS excluded types entirely still renders '
      'the full sheet', (WidgetTester tester) async {
    await _pumpCaseOpening(
      tester,
      dropOdds: const {
        'configVersion': 12,
        'position': 7,
        'totalParticipants': 7,
        'rarity': _rarity,
        // Last place: TRAIL_MINE is gone from the map rather than zeroed.
        'byType': {'SHORTCUT': 0.19, 'CLEANSE': 0.05},
      },
    );

    await _openSheet(tester);

    expect(find.text('BY POWERUP'), findsOneWidget);
    expect(find.text('19%'), findsOneWidget);
    expect(find.text('5%'), findsOneWidget);
    // Nothing invents a row for the missing type.
    expect(
      find.descendant(
        of: find.byKey(const Key('odds-sheet')),
        matching: find.text('Trail Mine'),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('per-player-different byType weights (down-weighted and '
      'redistributed) render sorted, with the rarity block unchanged', (
    WidgetTester tester,
  ) async {
    await _pumpCaseOpening(
      tester,
      dropOdds: const {
        'configVersion': 12,
        'position': 4,
        'totalParticipants': 7,
        'rarity': _rarity,
        // Nothing uniform about these: freed mass redistributed within tiers,
        // plus a 0.5x down-weight on RUNNERS_HIGH.
        'byType': {
          'RUNNERS_HIGH': 0.021,
          'SHORTCUT': 0.163,
          'MIRROR': 0.0004,
          'PROTEIN_SHAKE': 0.244,
        },
      },
    );

    await _openSheet(tester);

    expect(find.text('24%'), findsOneWidget);
    expect(find.text('16%'), findsOneWidget);
    expect(find.text('2.1%'), findsOneWidget);
    // A sub-0.1% slice must never print as "0%" — that would read as
    // impossible when it is merely rare.
    expect(find.text('<0.1%'), findsOneWidget);
    // Provenance explains why two players in one race see different numbers.
    expect(find.textContaining('Position 4 of 7'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unknown byType key from a newer backend degrades to its raw '
      'identifier instead of crashing', (WidgetTester tester) async {
    await _pumpCaseOpening(
      tester,
      dropOdds: const {
        'configVersion': 99,
        'rarity': _rarity,
        'byType': {'SOME_FUTURE_POWERUP': 0.07, 'SHORTCUT': 0.1},
      },
    );

    await _openSheet(tester);

    expect(find.text('7%'), findsOneWidget);
    expect(find.text('10%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an all-zero byType (every type filtered out of a tier) renders '
      'without taking the sheet down', (WidgetTester tester) async {
    await _pumpCaseOpening(
      tester,
      dropOdds: const {
        'configVersion': 12,
        'rarity': _rarity,
        'byType': {'RED_CARD': 0.0, 'SECOND_WIND': 0.0},
      },
    );

    await _openSheet(tester);

    expect(find.text('BY POWERUP'), findsOneWidget);
    expect(find.text('0%'), findsNWidgets(2));
    // byType is explicitly NOT a distribution — a sum of 0 is not a reason to
    // invalidate the payload.
    expect(find.text('38%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the rarity block alone gates the sheet: a bad byType drops only '
      'the section, a bad rarity hides everything', (WidgetTester tester) async {
    // Unusable byType (negative slice) -> section dropped, sheet still shown.
    await _pumpCaseOpening(
      tester,
      dropOdds: const {
        'configVersion': 12,
        'rarity': _rarity,
        'byType': {'SHORTCUT': -0.1},
      },
    );
    await _openSheet(tester);
    expect(find.text('BY POWERUP'), findsNothing);
    expect(find.text('38%'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // A rarity block that no longer sums to 1.0 hides the ENTIRE affordance —
    // which is exactly why this feature must filter WITHIN a tier and never
    // move mass between tiers.
    await _pumpCaseOpening(
      tester,
      dropOdds: const {
        'configVersion': 12,
        'rarity': {'COMMON': 0.31, 'UNCOMMON': 0.31, 'RARE': 0.20},
        'byType': {'SHORTCUT': 0.1},
      },
    );
    expect(find.text('ODDS'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
