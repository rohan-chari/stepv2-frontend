import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/powerup_icon.dart';
import 'package:step_tracker/widgets/spinning_face.dart';

void main() {
  for (final type in const [
    'LEG_CRAMP',
    'RED_CARD',
    'SHORTCUT',
    'COMPRESSION_SOCKS',
    'PROTEIN_SHAKE',
    'RUNNERS_HIGH',
    'SECOND_WIND',
    'STEALTH_MODE',
    'WRONG_TURN',
    'FANNY_PACK',
    'TRAIL_MIX',
    'DETOUR_SIGN',
  ]) {
    testWidgets('PowerupIcon renders the image asset for $type', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: PowerupIcon(type: type, size: 56)),
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
  }

  testWidgets('PowerupIcon can render as a spinning preview', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: PowerupIcon(
              type: 'LEG_CRAMP',
              size: 56,
              spinning: true,
              spinDuration: Duration(milliseconds: 2800),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(PowerupIcon), findsOneWidget);
    expect(find.byType(SpinningFace), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PowerupIcon),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
