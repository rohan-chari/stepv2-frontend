import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/error_toast.dart';

void main() {
  testWidgets('showErrorToast uses a medium red panel with darker framing', (
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

    final bannerFinder = find.byWidgetPredicate((widget) {
      if (widget is! Container || widget.decoration is! BoxDecoration) {
        return false;
      }

      final decoration = widget.decoration! as BoxDecoration;
      return decoration.color == const Color(0xFFAA5252);
    });

    expect(bannerFinder, findsOneWidget);

    final banner = tester.widget<Container>(bannerFinder);
    final decoration = banner.decoration! as BoxDecoration;
    final border = decoration.border! as Border;

    expect(border.top.color, const Color(0xFF8B2020));

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });
}
