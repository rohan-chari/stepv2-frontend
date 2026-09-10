import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/constants/powerup_copy.dart';
import 'package:step_tracker/widgets/powerup_guide_sheet.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PowerupCopy.resetForTest();
  });
  testWidgets(
    'guide shows Red Card maximum when server descriptions are absent',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PowerupGuideSheet())),
      );
      await tester.scrollUntilVisible(
        find.text('Red Card'),
        200,
        scrollable: find.descendant(
          of: find.byKey(const Key('powerup-guide-powerups-page')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(
        find.text("Remove 10% of the leader's steps, up to 10,000 steps."),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
