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
    'returned Red Card maximum survives a refresh with absent description',
    (tester) async {
      await PowerupCopy.refresh(
        fetch: () async => {
          'powerups': [
            {
              'type': 'RED_CARD',
              'name': 'Red Card',
              'description': PowerupCopy.descriptionFor('RED_CARD'),
            },
          ],
        },
      );
      await PowerupCopy.refresh(
        fetch: () async => {
          'powerups': [
            {'type': 'RED_CARD', 'name': 'Red Card'},
          ],
        },
      );
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
