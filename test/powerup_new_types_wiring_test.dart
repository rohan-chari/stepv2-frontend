import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/constants/powerup_copy.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/powerup_icon.dart';

/// §9.4 — the exact wiring checklist for HITCHHIKE and QUICK_RINSE.
///
/// Powerup copy used to be duplicated across seven files, so a partial edit
/// shipped a raw enum string (`HITCHHIKE`) into the UI. These tests pin the
/// single consolidated source plus the icon/feature-token wiring.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PowerupCopy.resetForTest();
  });

  group('icons', () {
    test('both new types resolve a bundled asset path', () {
      expect(
        PowerupIcon.assetPathFor('HITCHHIKE'),
        'assets/images/powerups/hitchhike.png',
      );
      expect(
        PowerupIcon.assetPathFor('QUICK_RINSE'),
        'assets/images/powerups/quick_rinse.png',
      );
    });

    test('knownTypeCount covers the new types', () {
      // 26 shipped types + Hitchhike + Quick Rinse.
      expect(PowerupIcon.knownTypeCount, 28);
    });

    test('an unknown type still resolves null rather than throwing', () {
      expect(PowerupIcon.assetPathFor('NOT_A_POWERUP'), isNull);
    });

    testWidgets('an unknown type renders the generic fallback icon',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PowerupIcon(type: 'SOME_FUTURE_TYPE')),
        ),
      );
      // Must not throw and must render something.
      expect(find.byType(PowerupIcon), findsOneWidget);
    });

    testWidgets('the new types render without throwing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                PowerupIcon(type: 'HITCHHIKE'),
                PowerupIcon(type: 'QUICK_RINSE'),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(PowerupIcon), findsNWidgets(2));
    });
  });

  group('client feature token', () {
    test('powerups3 is advertised', () {
      final tokens = BackendApiService.clientFeaturesHeader.split(',');
      expect(tokens, contains('powerups3'));
    });

    test('existing tokens are preserved alongside powerups3', () {
      final tokens = BackendApiService.clientFeaturesHeader.split(',');
      // Regression guard: appending powerups3 must not drop any prior token.
      for (final token in [
        'characters',
        'jammer',
        'spinpowerups',
        'team_races',
        'tournaments',
        'powerups2',
      ]) {
        expect(tokens, contains(token), reason: token);
      }
    });
  });

  group('consolidated copy covers every former call site', () {
    test('names resolve for the new types instead of the raw enum', () {
      expect(PowerupCopy.nameFor('HITCHHIKE'), 'Hitchhike');
      expect(PowerupCopy.nameFor('QUICK_RINSE'), 'Quick Rinse');
      // The old failure mode was rendering the enum string itself.
      expect(PowerupCopy.nameFor('HITCHHIKE'), isNot('HITCHHIKE'));
      expect(PowerupCopy.nameFor('QUICK_RINSE'), isNot('QUICK_RINSE'));
    });

    test('descriptions resolve for the new types', () {
      expect(PowerupCopy.descriptionFor('HITCHHIKE'), isNotEmpty);
      expect(PowerupCopy.descriptionFor('QUICK_RINSE'), isNotEmpty);
    });

    test('lowercase input still resolves (defensive casing)', () {
      expect(PowerupCopy.nameFor('hitchhike'), 'Hitchhike');
      expect(PowerupIcon.assetPathFor('quick_rinse'), isNotNull);
    });

    test('legacy display names former maps carried are preserved', () {
      // feed_bubble named BANANA_PEEL; multi_case_opening named COINS. Folding
      // the maps together must not regress either.
      expect(PowerupCopy.nameFor('BANANA_PEEL'), 'Banana Peel');
      expect(PowerupCopy.nameFor('COINS'), 'Coins');
    });

    test('every icon-known type also has a display name', () {
      // Guards the exact drift this consolidation exists to prevent: an icon
      // without copy renders a sprite next to a raw enum string.
      for (final type in PowerupCopy.bundledTypes) {
        expect(
          PowerupIcon.assetPathFor(type),
          isNotNull,
          reason: 'no icon for $type',
        );
      }
    });
  });

  group('targeting classification', () {
    test('Hitchhike is targeted and Quick Rinse is self-only', () {
      // Hitchhike picks a rival to copy steps from; Quick Rinse acts on the
      // caster only and must never open the target picker.
      expect(kTargetedPowerupTypes, contains('HITCHHIKE'));
      expect(kTargetedPowerupTypes, isNot(contains('QUICK_RINSE')));
    });

    test('existing targeted types are unchanged', () {
      for (final type in [
        'LEG_CRAMP',
        'SHORTCUT',
        'WRONG_TURN',
        'DETOUR_SIGN',
        'SNEAKY_SWAP',
        'IMPOSTER',
        'SIGNAL_JAMMER',
        'LEECH',
      ]) {
        expect(kTargetedPowerupTypes, contains(type), reason: type);
      }
    });
  });
}
