import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/content_board.dart';
import 'package:step_tracker/widgets/tab_layout.dart';

void main() {
  testWidgets('TabLayout stretches the board across the available width', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));

    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TabLayout(
            title: 'HOME',
            child: SizedBox(height: 120, child: Text('content')),
          ),
        ),
      ),
    );

    expect(find.byType(ContentBoard), findsOneWidget);
    expect(find.text('HOME'), findsOneWidget);
    expect(tester.getSize(find.byType(ContentBoard)).width, 400);
  });
}
