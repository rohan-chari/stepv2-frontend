import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/pill_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('normal-sized game action labels use the established sans font', () {
    expect(PixelText.display().fontFamily, 'Jersey25');
  });

  test('Jersey25 display styles use the enlarged arcade scale', () {
    expect(PixelText.display(size: 20).fontSize, 30);
  });

  testWidgets(
    'standard action buttons render the sans label without overflow',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PillButton(label: 'DAILY REWARD', onPressed: () {}),
          ),
        ),
      );

      final label = tester.widget<Text>(find.text('DAILY REWARD'));
      expect(label.style?.fontFamily, startsWith('DMSans'));
      expect(tester.takeException(), isNull);
    },
  );
}
