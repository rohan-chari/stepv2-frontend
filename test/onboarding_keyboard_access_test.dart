import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/screens/display_name_screen.dart';
import 'package:step_tracker/screens/step_goal_onboarding_screen.dart';
import 'package:step_tracker/screens/step_goal_screen.dart';
import 'package:step_tracker/services/auth_service.dart';

void main() {
  testWidgets('DisplayNameScreen keeps continue button reachable', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: DisplayNameScreen(authService: AuthService()),
      ),
    );

    expect(find.byType(SingleChildScrollView), findsOneWidget);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('CONTINUE')).dy, lessThan(360));
  });

  testWidgets('StepGoalOnboardingScreen keeps continue button reachable', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: StepGoalOnboardingScreen(authService: AuthService()),
      ),
    );

    expect(find.byType(SingleChildScrollView), findsOneWidget);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('CONTINUE')).dy, lessThan(360));
  });

  testWidgets('StepGoalScreen keeps save button reachable', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: StepGoalScreen(authService: AuthService()),
      ),
    );

    expect(find.byType(SingleChildScrollView), findsOneWidget);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('SAVE')).dy, lessThan(360));
  });
}
