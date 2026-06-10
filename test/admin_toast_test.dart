import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/screens/admin_screen.dart';
import 'package:step_tracker/services/auth_service.dart';

void main() {
  testWidgets('admin powerup icon list includes newer powerups', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: AdminScreen(authService: AuthService())),
    );

    expect(find.text('Cleanse'), findsOneWidget);
    expect(find.text('Imposter'), findsOneWidget);
  });

  testWidgets('admin toast test buttons show shared toasts', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: AdminScreen(authService: AuthService())),
    );

    await tester.tap(find.text('TEST INFO TOAST'));
    await tester.pump();

    expect(find.byKey(const Key('info-toast-shell')), findsOneWidget);
    expect(find.text('This is a test notification toast.'), findsOneWidget);

    await tester.tap(find.text('TEST ERROR TOAST'));
    await tester.pump();

    expect(find.byKey(const Key('error-toast-shell')), findsOneWidget);
    expect(find.text('This is a test error toast.'), findsOneWidget);
  });
}
