import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/screens/case_opening_screen.dart';

/// Spec §6.3.B.10 / test plan 21-23: the case-opening screen surfaces an ODDS
/// affordance ONLY when the backend sent a well-formed `powerupData.dropOdds`.
/// Absent or malformed → the affordance is hidden entirely, because a wrong
/// odds display is worse than none.
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

const _validDropOdds = {
  'configVersion': 7,
  'position': 3,
  'totalParticipants': 8,
  'rarity': {'COMMON': 0.38, 'UNCOMMON': 0.29, 'RARE': 0.33},
  'byType': {'SHORTCUT': 0.031, 'RED_CARD': 0.015},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('dropOdds present -> ODDS affordance renders and opens a sheet '
      'showing the payload values', (WidgetTester tester) async {
    await _pumpCaseOpening(tester, dropOdds: _validDropOdds);

    expect(find.text('ODDS'), findsOneWidget);

    await tester.tap(find.text('ODDS'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('DROP ODDS'), findsOneWidget);
    // Rarity rows, exactly as the server sent them.
    expect(find.text('38%'), findsOneWidget);
    expect(find.text('29%'), findsOneWidget);
    expect(find.text('33%'), findsOneWidget);
    // Per-type slices, at a precision that keeps 3.1% distinguishable from
    // 3.4% instead of both rounding to "3%".
    expect(find.text('BY POWERUP'), findsOneWidget);
    expect(find.text('3.1%'), findsOneWidget);
    expect(find.text('1.5%'), findsOneWidget);
    // Provenance: which config version produced these numbers (D9).
    expect(find.textContaining('v7'), findsWidgets);
  });

  testWidgets('dropOdds absent -> no ODDS affordance, reel still renders', (
    WidgetTester tester,
  ) async {
    await _pumpCaseOpening(tester);

    expect(find.text('ODDS'), findsNothing);
    // Screen otherwise unchanged.
    expect(find.text('MYSTERY BOX'), findsOneWidget);
    expect(find.text('SWIPE OR TAP'), findsOneWidget);
  });

  testWidgets('malformed dropOdds (rarity sums to 0.4) -> affordance hidden, '
      'no crash', (WidgetTester tester) async {
    await _pumpCaseOpening(
      tester,
      dropOdds: const {
        'configVersion': 7,
        'rarity': {'COMMON': 0.2, 'UNCOMMON': 0.1, 'RARE': 0.1},
      },
    );

    expect(find.text('ODDS'), findsNothing);
    expect(find.text('MYSTERY BOX'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dropOdds with a non-map rarity block -> affordance hidden', (
    WidgetTester tester,
  ) async {
    await _pumpCaseOpening(
      tester,
      dropOdds: const {'configVersion': 7, 'rarity': 'nonsense'},
    );

    expect(find.text('ODDS'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
