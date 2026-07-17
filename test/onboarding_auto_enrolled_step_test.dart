import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/screens/onboarding_flow.dart';

void main() {
  testWidgets(
    'auto-enrolled step shows the confirmation copy and drops into the daily on CTA',
    (WidgetTester tester) async {
      var entered = 0;
      var skipped = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingAutoEnrolledStep(
            onEnterDaily: () async {
              entered++;
            },
            onSkip: () => skipped++,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      // Confirmation messaging (auto-enrolled, boxes waiting, opt-out).
      expect(find.textContaining('Daily'), findsWidgets);
      expect(find.textContaining('mystery boxes'), findsOneWidget);
      expect(find.textContaining('Races page'), findsOneWidget);

      // Primary CTA drops the user into the live daily race.
      final cta = find.text('START THE DAILY CHALLENGE');
      expect(cta, findsOneWidget);
      await tester.tap(cta);
      await tester.pump();

      expect(entered, 1);
      expect(skipped, 0);
    },
  );

  testWidgets(
    'a pending share link short-circuits the step (auto-skip, no CTA)',
    (WidgetTester tester) async {
      var entered = 0;
      var skipped = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingAutoEnrolledStep(
            onEnterDaily: () async {
              entered++;
            },
            onSkip: () => skipped++,
            skipForPendingShare: true,
          ),
        ),
      );
      // Let the post-frame auto-skip fire.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(skipped, 1);
      expect(entered, 0);
      // The CTA is never offered — the share link owns the destination.
      expect(find.text('START THE DAILY CHALLENGE'), findsNothing);
    },
  );
}
