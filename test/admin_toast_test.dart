import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/screens/admin_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/widgets/powerup_icon.dart';

void main() {
  testWidgets('admin powerup icon list includes newer powerups', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: AdminScreen(authService: AuthService())),
    );

    expect(find.text('Cleanse'), findsOneWidget);
    expect(find.text('Imposter'), findsOneWidget);
    expect(find.text('Rainstorm'), findsOneWidget);
    expect(find.text('Lucky Horseshoe'), findsOneWidget);
    expect(find.text('Sneaky Swap'), findsOneWidget);
    expect(find.text('Mirror'), findsOneWidget);

    // One row per type PowerupIcon can render — keeps the admin list from
    // drifting out of sync when new powerups are added.
    expect(
      find.byType(PowerupIcon),
      findsNWidgets(PowerupIcon.knownTypeCount),
    );
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
