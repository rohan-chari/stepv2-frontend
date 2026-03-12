import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/main.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const StepTrackerApp());
    expect(find.text('Step Tracker'), findsOneWidget);
  });
}
