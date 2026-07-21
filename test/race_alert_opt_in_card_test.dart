import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/widgets/race_alert_opt_in_card.dart';

void main() {
  testWidgets('omitted callback renders no alert prompt', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RaceAlertOptInCard(onEnable: null)),
      ),
    );
    await tester.pump();
    expect(find.text('ENABLE RACE ALERTS'), findsNothing);
  });

  testWidgets('Not now persists device dismissal', (tester) async {
    SharedPreferences.setMockInitialValues({});
    Future<bool> enable() async => true;
    Widget app() => MaterialApp(
      home: Scaffold(body: RaceAlertOptInCard(onEnable: enable)),
    );

    await tester.pumpWidget(app());
    await tester.pump();
    await tester.tap(find.text('Not now'));
    await tester.pump();
    expect(find.text('ENABLE RACE ALERTS'), findsNothing);

    await tester.pumpWidget(app());
    await tester.pump();
    expect(find.text('ENABLE RACE ALERTS'), findsNothing);
  });

  testWidgets('system callback runs only after explicit enable tap', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RaceAlertOptInCard(
            onEnable: () async {
              calls += 1;
              return false;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(calls, 0);
    await tester.tap(find.text('ENABLE RACE ALERTS'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('ENABLE RACE ALERTS'), findsNothing);
  });
}
