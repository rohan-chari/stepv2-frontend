import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/screens/onboarding_flow.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/tutorial/tutorial_screen.dart';
import 'package:step_tracker/widgets/onboarding_permission_gate.dart';

/// Pre-auth surfaces (title screen, onboarding steps, tutorial) are one
/// continuous daytime brand moment. They pin themselves to the light palette
/// via `Theme(data: AppThemeData.light())` so a dark-mode device does not get
/// a night sky mid-onboarding and a bright title screen either side of it.
///
/// Every pump below deliberately hosts the widget in a NIGHT MaterialApp: the
/// assertion is that the surface ignores it and renders light tokens anyway.
///
/// This file is the renamed `dark_theme_coverage_test.dart` with its two
/// assertions inverted. That file only ever covered these pre-auth surfaces,
/// so nothing else moved; post-auth screens still follow the device theme.
Widget _night(Widget child) =>
    MaterialApp(theme: AppThemeData.night(), home: child);

Color? _textColor(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label).first).style?.color;

void main() {
  testWidgets('every standalone onboarding step pins to the light palette', (
    tester,
  ) async {
    await tester.pumpWidget(
      _night(
        OnboardingPermissionGate(
          label: 'HEALTH DATA',
          headline: 'Connect steps to start racing',
          body: 'Permission explanation',
          icon: Icons.favorite_rounded,
          onContinue: () {},
        ),
      ),
    );
    expect(
      _textColor(tester, 'Connect steps to start racing'),
      AppPalette.light.textLight,
    );

    await tester.pumpWidget(
      _night(OnboardingTutorialStep(onStart: () {}, onSkip: () {})),
    );
    expect(
      _textColor(tester, 'Earn your first 100 coins'),
      AppPalette.light.textLight,
    );

    await tester.pumpWidget(
      _night(
        OnboardingAutoEnrolledStep(onEnterDaily: () async {}, onSkip: () {}),
      ),
    );
    await tester.pump(const Duration(milliseconds: 20));
    expect(
      _textColor(tester, 'Entered in the Daily & Weekly challenge'),
      AppPalette.light.textLight,
    );

    await tester.pumpWidget(
      _night(
        OnboardingReferralWelcomeStep(code: 'BARA-DARK', onContinue: () {}),
      ),
    );
    await tester.pump();
    expect(
      _textColor(tester, 'A friend invited you to Bara'),
      AppPalette.light.textLight,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tutorial preview and spotlight pin to the light palette', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_night(TutorialScreen(onComplete: (_, _) {})));
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(_textColor(tester, 'Just walk.'), AppPalette.light.textLight);
    expect(_textColor(tester, 'SKIP'), AppPalette.light.textLight);
    expect(tester.takeException(), isNull);
  });
}
