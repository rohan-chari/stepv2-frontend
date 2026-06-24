import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/main.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/deep_link_service.dart';
import 'package:step_tracker/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App renders without crashing', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final authService = AuthService();
    await tester.pumpWidget(
      StepTrackerApp(
        notificationService: NotificationService(),
        authService: authService,
        deepLinkService: DeepLinkService(authService: authService),
      ),
    );
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
