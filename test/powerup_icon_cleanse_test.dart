import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/powerup_icon.dart';

// 1.1.7: CLEANSE is a new powerup. There is no cleanse.png art yet, so the
// PowerupIcon must register CLEANSE in its asset map and render an Image whose
// errorBuilder falls back gracefully — never crashing or showing a broken '?'.
void main() {
  testWidgets('PowerupIcon renders an Image for CLEANSE without throwing', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: PowerupIcon(type: 'CLEANSE', size: 56)),
        ),
      ),
    );

    expect(find.byType(PowerupIcon), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PowerupIcon),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('PowerupIcon handles lowercase cleanse type', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: PowerupIcon(type: 'cleanse', size: 56)),
        ),
      ),
    );

    expect(find.byType(PowerupIcon), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
