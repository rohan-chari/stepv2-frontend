import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/coin_balance_badge.dart';

void main() {
  testWidgets('CoinBalanceBadge shows the held badge when coins are reserved', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CoinBalanceBadge(coins: 420, heldCoins: 100),
        ),
      ),
    );

    expect(find.text('420'), findsOneWidget);
    expect(find.text('HOLD 100'), findsOneWidget);
  });

  testWidgets('CoinBalanceBadge hides the held badge when nothing is reserved', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CoinBalanceBadge(coins: 420, heldCoins: 0),
        ),
      ),
    );

    expect(find.text('420'), findsOneWidget);
    expect(find.textContaining('HOLD'), findsNothing);
  });
}
