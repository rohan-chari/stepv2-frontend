import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/screens/multi_case_opening_screen.dart';
import 'package:step_tracker/widgets/pill_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<Map<String, dynamic>> results(int n, {bool queued = false}) => [
    for (int i = 0; i < n; i++)
      {
        'powerupId': 'p$i',
        'type': i.isEven ? 'RED_CARD' : 'PROTEIN_SHAKE',
        'rarity': i.isEven ? 'RARE' : 'COMMON',
        'autoActivated': false,
        'queued': queued,
      },
  ];

  testWidgets('one tap opens all boxes and shows the aggregate summary (#1)',
      (tester) async {
    List<Map<String, dynamic>>? handedBack;

    await tester.pumpWidget(
      MaterialApp(
        home: MultiCaseOpeningScreen(
          boxCount: 3,
          includesQueued: true,
          onResults: (r) => handedBack = r,
          openAll: () async => results(3, queued: true),
        ),
      ),
    );
    await tester.pump();

    // Idle: a single OPEN ALL trigger, no summary yet.
    expect(find.text('Crack open all 3 boxes at once'), findsOneWidget);
    expect(find.text('YOU OPENED 3'), findsNothing);

    // One tap fires the batch and starts every reel together.
    await tester.tap(find.widgetWithText(PillButton, 'OPEN ALL'));
    await tester.pump(); // resolve openAll future -> revealing
    await tester.pump(); // post-frame trigger fires the reels

    // §6 reveal sync: the inventory commit is DEFERRED until the reels land, so
    // onResults must NOT have fired yet while the reels are still spinning
    // (previously it fired here, spoiling the result behind the reel).
    expect(handedBack, isNull);

    // Let all reels finish (4s spin + 600ms dramatic pause).
    await tester.pump(const Duration(milliseconds: 4200));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();

    // Only now — after every reel has landed — is the batch handed back.
    expect(handedBack, isNotNull);
    expect(handedBack!.length, 3);

    // Aggregate summary.
    expect(find.text('YOU OPENED 3'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.textContaining('queued'), findsOneWidget);
  });

  testWidgets('empty results (nothing to open) closes without a summary',
      (tester) async {
    var resultsCallbackFired = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute(
            builder: (_) => MultiCaseOpeningScreen(
              boxCount: 2,
              onResults: (_) => resultsCallbackFired = true,
              openAll: () async => const <Map<String, dynamic>>[],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(PillButton, 'OPEN ALL'));
    await tester.pump();
    await tester.pump();

    // No summary, no optimistic reconcile fired for an empty open.
    expect(find.text('YOU OPENED 2'), findsNothing);
    expect(resultsCallbackFired, isFalse);
  });
}
