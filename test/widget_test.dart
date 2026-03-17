import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/main.dart';
import 'package:step_tracker/services/notification_service.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(
      StepTrackerApp(notificationService: NotificationService()),
    );
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
