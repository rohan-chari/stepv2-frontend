import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/case_opening_strip.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpStrip(
    WidgetTester tester, {
    required VoidCallback onComplete,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CaseOpeningStrip(
            resultType: 'RED_CARD',
            resultRarity: 'RARE',
            onComplete: onComplete,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('race strip waits for swipe, spins, then calls onComplete', (
    WidgetTester tester,
  ) async {
    var completed = false;
    await pumpStrip(tester, onComplete: () => completed = true);

    expect(find.text('SWIPE OR TAP'), findsOneWidget);
    expect(completed, isFalse);

    await tester.tap(find.text('SWIPE OR TAP'));
    await tester.pump();
    expect(find.text('OPENING...'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 4100));
    expect(completed, isFalse); // dramatic pause still pending
    await tester.pump(const Duration(milliseconds: 700));
    expect(completed, isTrue);
  });

  testWidgets('generic reel renders custom tiles', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CaseOpeningReel(
            itemCount: 5,
            resultIndex: 3,
            onComplete: () {},
            itemBuilder: (context, index, isResult) => CaseReelTile(
              rarity: isResult ? 'RARE' : 'COMMON',
              width: 86,
              height: 100,
              child: Text('tile-$index'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('tile-0'), findsOneWidget);
    expect(find.text('tile-3'), findsOneWidget);
  });
}
