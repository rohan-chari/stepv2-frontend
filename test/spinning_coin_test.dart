import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/spinning_coin.dart';

void main() {
  testWidgets('SpinningCoin renders the generated coin asset', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SpinningCoin(size: 32))),
    );

    expect(
      find.byWidgetPredicate((widget) {
        return widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName == 'assets/images/coin.png';
      }),
      findsOneWidget,
    );
  });
}
