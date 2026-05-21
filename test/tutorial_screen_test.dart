import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/tutorial/tutorial_screen.dart';
import 'package:step_tracker/widgets/home_chrome.dart';

void main() {
  testWidgets('TutorialScreen shows app-like mock screens with sample data', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: TutorialScreen()));
    await tester.pump();

    expect(find.text('Steps today'), findsOneWidget);
    expect(find.text('13,420'), findsOneWidget);
    expect(find.text('EDIT GOAL'), findsOneWidget);

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('NEXT'));
      await tester.pump();
    }

    expect(find.text('First to the finish line wins.'), findsOneWidget);
    expect(find.text('ACTIVE RACES'), findsOneWidget);
    expect(find.text('Weekend 10K'), findsOneWidget);

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('NEXT'));
      await tester.pump();
    }

    expect(find.text('Search by display name'), findsOneWidget);
    expect(find.text('YOUR FRIENDS'), findsOneWidget);
    expect(find.text('Maya Chen'), findsOneWidget);
  });

  testWidgets('TutorialScreen aligns spotlight targets inside the safe area', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) {
          final mediaQuery = MediaQuery.of(context);
          return MediaQuery(
            data: mediaQuery.copyWith(padding: const EdgeInsets.only(top: 52)),
            child: child!,
          );
        },
        home: const TutorialScreen(),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('NEXT'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    final targetRect = tester.getRect(
      find.widgetWithText(HomePillButton, 'EDIT GOAL'),
    );
    final calloutRect = tester.getRect(
      find.byKey(const Key('tutorial-callout-card')),
    );

    expect(calloutRect.top - targetRect.bottom, inInclusiveRange(20, 32));
  });
}
