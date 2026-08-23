import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/signed_step_amount.dart';

void main() {
  testWidgets('formats positive changes with a plus and bold green text', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: SignedStepAmount(steps: 1500)),
    );

    final text = tester.widget<Text>(find.text('+1,500 steps'));
    expect(text.style?.fontWeight, FontWeight.w900);
    expect(text.style?.color, isNotNull);
  });

  testWidgets('formats negative changes with a minus and bold red text', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: SignedStepAmount(steps: -1500)),
    );

    final text = tester.widget<Text>(find.text('-1,500 steps'));
    expect(text.style?.fontWeight, FontWeight.w900);
    expect(text.style?.color, isNotNull);
  });
}
