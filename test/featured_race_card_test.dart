import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/featured_race_card.dart';

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SizedBox(height: 260, child: child)),
  );
}

FeaturedRaceCard _card({
  bool isUpcoming = false,
  bool isJoined = false,
  bool isFull = false,
  VoidCallback? onJoin,
  VoidCallback? onView,
}) {
  return FeaturedRaceCard(
    name: 'Daily 10K Sprint',
    seedKind: 'DAILY_10K',
    endsAt: DateTime.now().add(const Duration(hours: 8)),
    startsAt: DateTime.now().add(const Duration(hours: 5)),
    participantCount: 12,
    finishRewardPool: 100,
    isJoined: isJoined,
    isFull: isFull,
    isJoining: false,
    isUpcoming: isUpcoming,
    onJoin: onJoin ?? () {},
    onView: onView ?? () {},
  );
}

void main() {
  testWidgets('live card shows DAILY / ENDS IN / JOIN', (tester) async {
    await tester.pumpWidget(_host(_card()));
    expect(find.text('DAILY'), findsOneWidget);
    expect(find.textContaining('ENDS IN'), findsOneWidget);
    expect(find.text('JOIN'), findsOneWidget);
  });

  testWidgets('upcoming card shows TOMORROW / STARTS IN / OPT IN', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_card(isUpcoming: true)));
    expect(find.text('TOMORROW'), findsOneWidget);
    expect(find.textContaining('STARTS IN'), findsOneWidget);
    expect(find.text('OPT IN'), findsOneWidget);
    expect(find.text('12 joined'), findsOneWidget);
  });

  testWidgets("upcoming card that you opted into shows YOU'RE IN", (
    tester,
  ) async {
    await tester.pumpWidget(_host(_card(isUpcoming: true, isJoined: true)));
    expect(find.text("YOU'RE IN"), findsOneWidget);
    expect(find.text('OPT IN'), findsNothing);
  });

  testWidgets('upcoming card at capacity shows FULL', (tester) async {
    await tester.pumpWidget(_host(_card(isUpcoming: true, isFull: true)));
    expect(find.text('FULL'), findsOneWidget);
    expect(find.text('OPT IN'), findsNothing);
  });

  testWidgets('tapping OPT IN calls onJoin', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _host(_card(isUpcoming: true, onJoin: () => tapped = true)),
    );
    await tester.tap(find.text('OPT IN'));
    expect(tapped, isTrue);
  });
}
