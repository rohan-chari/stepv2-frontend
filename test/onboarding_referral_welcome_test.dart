import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/screens/onboarding_flow.dart';

void main() {
  testWidgets('greets the referee by inviter + reward, then dismisses', (
    tester,
  ) async {
    var dismissed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingReferralWelcomeStep(
          code: 'BARA-7F3K',
          onFetchPreview: (code) async => {
            'inviterName': 'Alice',
            'inviterAvatar': null,
            'rewardCoins': 100,
          },
          onContinue: () => dismissed = true,
        ),
      ),
    );
    await tester.pump(); // resolve the preview future

    expect(find.text('@Alice invited you to Bara'), findsOneWidget);
    expect(find.textContaining('100'), findsOneWidget);

    await tester.tap(find.text("LET'S GO"));
    expect(dismissed, isTrue);
  });

  testWidgets('falls back to a generic welcome when preview fetch fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingReferralWelcomeStep(
          code: 'BARA-7F3K',
          onFetchPreview: (code) async => throw Exception('offline'),
          onContinue: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('A friend invited you to Bara'), findsOneWidget);
    expect(find.text("LET'S GO"), findsOneWidget);
  });
}
