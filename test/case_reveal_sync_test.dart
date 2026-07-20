import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/screens/case_opening_screen.dart';
import 'package:step_tracker/screens/multi_case_opening_screen.dart';
import 'package:step_tracker/widgets/case_opening_strip.dart';

// Spec §6: the parent inventory commit must fire only AFTER the reel lands, and
// the reveal screens must block dismissal mid-spin (PopScope). Previously the
// commit fired ~4.6s early — on the API response — spoiling the result (and, for
// an auto-activated Fanny Pack, deleting the row) behind the still-spinning reel.

// Reel timing: 4000ms spin + a 600ms settle delay before onComplete.
const _spinMs = 4000;
const _settleMs = 600;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> startSpin(WidgetTester tester) async {
    // Tap the reel to fire the swipe gate → server roll → spin.
    await tester.tap(find.byType(CaseOpeningStrip));
    await tester.pump(); // kick off _startSpin
    await tester.pump(); // resolve the (immediate) roll future
  }

  testWidgets('single open: inventory commit is deferred until the reel lands',
      (tester) async {
    Map<String, dynamic>? committed;

    await tester.pumpWidget(
      MaterialApp(
        home: CaseOpeningScreen(
          openMysteryBox: () async => {
            'result': {'type': 'PROTEIN_SHAKE', 'rarity': 'COMMON'},
          },
          onRevealed: (result) => committed = result,
        ),
      ),
    );
    await tester.pump();

    await startSpin(tester);

    // Mid-spin: the reel is still turning, so nothing has been committed to the
    // visible inventory yet.
    await tester.pump(const Duration(milliseconds: _spinMs ~/ 2));
    expect(committed, isNull);

    // After the reel lands (spin + settle), the commit fires exactly once.
    await tester.pump(const Duration(milliseconds: _spinMs));
    await tester.pump(const Duration(milliseconds: _settleMs + 100));
    expect(committed, isNotNull);
    expect(find.text('UNBOXED'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('single open: an auto-activated Fanny Pack row survives until '
      'reveal', (tester) async {
    var commits = 0;
    Map<String, dynamic>? committed;

    await tester.pumpWidget(
      MaterialApp(
        home: CaseOpeningScreen(
          openMysteryBox: () async => {
            'result': {
              'type': 'FANNY_PACK',
              'rarity': 'RARE',
              'autoActivated': true,
            },
          },
          onRevealed: (result) {
            commits++;
            committed = result;
          },
        ),
      ),
    );
    await tester.pump();
    await startSpin(tester);

    // The auto-activation must not be applied (row deleted) while the reel spins.
    await tester.pump(const Duration(milliseconds: _spinMs ~/ 2));
    expect(commits, 0);

    await tester.pump(const Duration(milliseconds: _spinMs));
    await tester.pump(const Duration(milliseconds: _settleMs + 100));
    expect(commits, 1);
    final result = (committed?['result'] as Map?) ?? committed;
    expect(result?['autoActivated'], true);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('single open: dismissal is blocked between roll and reveal',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CaseOpeningScreen(
          openMysteryBox: () async => {
            'result': {'type': 'PROTEIN_SHAKE', 'rarity': 'COMMON'},
          },
          onRevealed: (_) {},
        ),
      ),
    );
    await tester.pump();

    // Before the swipe the screen can be dismissed (backing out leaves the box
    // unopened).
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isTrue);

    await startSpin(tester);

    // Committed spin: back / swipe-back is a no-op mid-spin.
    await tester.pump(const Duration(milliseconds: _spinMs ~/ 2));
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
    // The X close is likewise inert — still on the opening screen.
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(find.text('MYSTERY BOX'), findsOneWidget);
    expect(find.text('UNBOXED'), findsNothing);

    // After reveal, dismissal is allowed again.
    await tester.pump(const Duration(milliseconds: _spinMs));
    await tester.pump(const Duration(milliseconds: _settleMs + 100));
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Open All: results commit together only after all reels land',
      (tester) async {
    List<Map<String, dynamic>>? committed;
    const results = [
      {'powerupId': 'b1', 'type': 'PROTEIN_SHAKE', 'rarity': 'COMMON'},
      {'powerupId': 'b2', 'type': 'SHORTCUT', 'rarity': 'COMMON'},
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: MultiCaseOpeningScreen(
          boxCount: 2,
          openAll: () async => List<Map<String, dynamic>>.from(results),
          onResults: (r) => committed = r,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.auto_awesome_rounded));
    await tester.pump(); // loading
    await tester.pump(); // resolve openAll → revealing
    await tester.pump(); // post-frame trigger fires the reels

    // Mid-spin: nothing committed yet.
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
    await tester.pump(const Duration(milliseconds: _spinMs ~/ 2));
    expect(committed, isNull);

    // After every reel lands, all results commit together in one shot.
    await tester.pump(const Duration(milliseconds: _spinMs));
    await tester.pump(const Duration(milliseconds: _settleMs + 100));
    expect(committed, isNotNull);
    expect(committed!.length, 2);
    expect(find.text('YOU OPENED 2'), findsOneWidget);
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
