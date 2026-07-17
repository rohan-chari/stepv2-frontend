import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/powerup_icon.dart';

void main() {
  group('PowerupIcon new powerup types (#2)', () {
    test('Leech and X-Ray/DEFENSE_SCAN resolve to bundled assets', () {
      expect(
        PowerupIcon.assetPathFor('LEECH'),
        'assets/images/powerups/leech.png',
      );
      expect(
        PowerupIcon.assetPathFor('DEFENSE_SCAN'),
        'assets/images/powerups/defense_scan.png',
      );
      // Case-insensitive lookup, matching the existing convention.
      expect(
        PowerupIcon.assetPathFor('leech'),
        'assets/images/powerups/leech.png',
      );
    });

    test('an unknown powerup type has no asset (fallback icon path)', () {
      expect(PowerupIcon.assetPathFor('SOME_FUTURE_POWERUP'), isNull);
    });

    testWidgets('unknown type renders the crash-safe fallback icon, not a crash',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PowerupIcon(type: 'SOME_FUTURE_POWERUP', size: 24),
          ),
        ),
      );
      // The fallback uses a bolt glyph; the important assertion is that build
      // succeeds (no exception) for an unknown enum value from a newer backend.
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
    });

    testWidgets('known new type renders an Image (no fallback)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PowerupIcon(type: 'LEECH', size: 24)),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.bolt_rounded), findsNothing);
      expect(find.byType(Image), findsOneWidget);
    });
  });
}
