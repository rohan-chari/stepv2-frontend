import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/pill_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('normal-sized game action labels use the bundled pixel font', () {
    expect(PixelText.display().fontFamily, 'Jersey25');
    expect(PixelText.pill().fontFamily, 'Jersey25');
  });

  testWidgets('standard action buttons render the pixel label without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PillButton(label: 'DAILY REWARD', onPressed: () {}),
        ),
      ),
    );

    final label = tester.widget<Text>(find.text('DAILY REWARD'));
    expect(label.style?.fontFamily, 'Jersey25');
    expect(tester.takeException(), isNull);
  });
}
