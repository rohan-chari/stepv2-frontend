import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/settings_screen.dart';
import 'package:step_tracker/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('SettingsScreen shows admin tools for admin users', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'auth_identity_token': 'apple-token',
      'auth_user_identifier': 'apple-user-123',
      'auth_session_token': 'session-token',
      'auth_is_admin': true,
    });

    final authService = AuthService();
    await authService.restoreSession();

    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(authService: authService)),
    );

    expect(find.text('ADMIN CHALLENGE TOOLS'), findsOneWidget);
  });
}
