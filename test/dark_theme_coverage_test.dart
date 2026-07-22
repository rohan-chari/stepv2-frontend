import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/screens/onboarding_flow.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/tutorial/tutorial_screen.dart';
import 'package:step_tracker/widgets/onboarding_permission_gate.dart';

Widget _night(Widget child) =>
    MaterialApp(theme: AppThemeData.night(), home: child);

Color? _textColor(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label).first).style?.color;

void main() {
  testWidgets('every standalone onboarding step uses night foreground tokens', (
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
      AppPalette.night.textLight,
    );

    await tester.pumpWidget(
      _night(OnboardingTutorialStep(onStart: () {}, onSkip: () {})),
    );
    expect(
      _textColor(tester, 'Earn your first 100 coins'),
      AppPalette.night.textLight,
    );

    await tester.pumpWidget(
      _night(
        OnboardingAutoEnrolledStep(onEnterDaily: () async {}, onSkip: () {}),
      ),
    );
    await tester.pump(const Duration(milliseconds: 20));
    expect(
      _textColor(tester, 'Entered in the Daily & Weekly challenge'),
      AppPalette.night.textLight,
    );

    await tester.pumpWidget(
      _night(
        OnboardingReferralWelcomeStep(code: 'BARA-DARK', onContinue: () {}),
      ),
    );
    await tester.pump();
    expect(
      _textColor(tester, 'A friend invited you to Bara'),
      AppPalette.night.textLight,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tutorial preview and spotlight render in the night theme', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_night(TutorialScreen(onComplete: (_) {})));
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(_textColor(tester, 'Track today'), AppPalette.night.textLight);
    expect(_textColor(tester, 'SKIP'), AppPalette.night.textLight);
    expect(tester.takeException(), isNull);
  });
}
