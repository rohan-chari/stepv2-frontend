import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/case_opening_strip.dart';

/// Tiny trigger for the Open-All grid: notifies listeners on [fire].
class _Trigger extends ChangeNotifier {
  void fire() => notifyListeners();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('external spinTrigger spins the reel without a swipe (#1)',
      (tester) async {
    final trigger = _Trigger();
    var completed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CaseOpeningStrip(
            resultType: 'RED_CARD',
            resultRarity: 'RARE',
            spinTrigger: trigger,
            hideSwipeHint: true,
            onComplete: () => completed = true,
          ),
        ),
      ),
    );
    await tester.pump();

    // hideSwipeHint replaces the swipe affordance with READY and hides the hint.
    expect(find.text('READY'), findsOneWidget);
    expect(find.text('SWIPE OR TAP'), findsNothing);
    expect(find.text('drag across the reel'), findsNothing);

    // Fire the shared trigger — the reel starts spinning with no user gesture.
    trigger.fire();
    await tester.pump();
    expect(find.text('OPENING...'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 4100));
    expect(completed, isFalse); // dramatic pause still pending
    await tester.pump(const Duration(milliseconds: 700));
    expect(completed, isTrue);

    trigger.dispose();
  });
}
