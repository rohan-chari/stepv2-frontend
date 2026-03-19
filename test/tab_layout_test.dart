import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/content_board.dart';
import 'package:step_tracker/widgets/tab_layout.dart';
import 'package:step_tracker/widgets/trail_sign.dart';

void main() {
  testWidgets('TabLayout uses narrower horizontal margins for boards', (
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
    expect(find.byType(TrailSign), findsOneWidget);
    expect(tester.getSize(find.byType(ContentBoard)).width, 368);
    expect(tester.getSize(find.byType(TrailSign)).width, 368);
  });
}
