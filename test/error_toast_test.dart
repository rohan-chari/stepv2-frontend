import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/error_toast.dart';

void main() {
  testWidgets(
    'showErrorToast uses the shared game toast shell with an error badge',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return TextButton(
                  onPressed: () => showErrorToast(context, 'Something broke'),
                  child: const Text('Show error'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show error'));
      await tester.pump();

      expect(find.byKey(const Key('error-toast-shell')), findsOneWidget);
      expect(find.byKey(const Key('error-toast-badge')), findsOneWidget);
      expect(find.text('ERROR'), findsOneWidget);
      expect(find.text('Something broke'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('showErrorToast dismisses when swiped up', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () => showErrorToast(context, 'Something broke'),
                child: const Text('Show error'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show error'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('error-toast-shell')), findsOneWidget);

    await tester.fling(
      find.byKey(const Key('error-toast-shell')),
      const Offset(0, -300),
      1000,
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('error-toast-shell')), findsNothing);
  });
}
