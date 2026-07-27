import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/coin_glyph.dart';
import 'package:step_tracker/widgets/featured_race_card.dart';

/// Batch 2026-07-27 item 3 — coins must never be drawn with a dollar sign.
///
/// Material's `Icons.monetization_on_rounded` is a `$` glyph, which reads as
/// real money. The featured race card was the last coin-denominated use of it
/// outside the shop.

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: SizedBox(height: 260, child: child)));

FeaturedRaceCard _card({int finishRewardPool = 100}) => FeaturedRaceCard(
  name: 'Daily 10K Sprint',
  seedKind: 'DAILY_10K',
  endsAt: DateTime.now().add(const Duration(hours: 8)),
  startsAt: DateTime.now().add(const Duration(hours: 5)),
  participantCount: 12,
  finishRewardPool: finishRewardPool,
  finishRewardPlaces: 0,
  isJoined: false,
  isFull: false,
  isJoining: false,
  isUpcoming: false,
  onJoin: () {},
  onView: () {},
);

void main() {
  testWidgets('the finish reward is marked with the paw coin, not a dollar', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_card()));

    expect(find.byIcon(Icons.monetization_on_rounded), findsNothing);
    expect(find.byType(CoinGlyph), findsOneWidget);
  });

  testWidgets('no coin glyph when there is no reward pool', (tester) async {
    await tester.pumpWidget(_host(_card(finishRewardPool: 0)));

    expect(find.byType(CoinGlyph), findsNothing);
    expect(find.byIcon(Icons.monetization_on_rounded), findsNothing);
  });
}
