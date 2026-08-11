import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/team_h2h_banner.dart';
import 'package:step_tracker/widgets/team_scoreline.dart';

// The tug-of-war knot assertions used to live in `team_h2h_banner_test.dart`,
// covering the rope the detail-screen H2H banner drew. That banner is gone
// (replaced by TeamScoreboardCards) but the ROPE is not — TeamTugRope is still
// live in the compact scoreline on race-list rows and the Home current-race
// area, and it is the only remaining lean-toward-the-leader affordance in the
// app. These two assertions moved here with it rather than being deleted.
//
// The obsolete assertions from that file — the `ALL TIED` label and the
// `SWIFT CAPYS LEAD +440` pill — are NOT carried over: neither string exists in
// `lib/` any more, and those three tests had been failing on the tree since the
// banner was first reworked.

Future<void> _pump(
  WidgetTester tester, {
  required int teamATotal,
  required int teamBTotal,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TeamScoreline(
          teamAName: 'Swift Capys',
          teamBName: 'Turbo Beavers',
          teamATotal: teamATotal,
          teamBTotal: teamBTotal,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows both names and formatted totals', (tester) async {
    await _pump(tester, teamATotal: 12340, teamBTotal: 11900);

    expect(find.textContaining('Swift Capys'), findsOneWidget);
    expect(find.textContaining('Turbo Beavers'), findsOneWidget);
    expect(find.textContaining('12,340'), findsOneWidget);
    expect(find.textContaining('11,900'), findsOneWidget);
  });

  testWidgets('knot slides toward the leading side', (tester) async {
    await _pump(tester, teamATotal: 30000, teamBTotal: 10000);
    final rope = tester.widget<TeamTugRope>(find.byType(TeamTugRope));
    expect(rope.share, lessThan(0.5)); // knot pulled toward Team A's end

    await _pump(tester, teamATotal: 10000, teamBTotal: 30000);
    final rope2 = tester.widget<TeamTugRope>(find.byType(TeamTugRope));
    expect(rope2.share, greaterThan(0.5));
  });

  testWidgets('tie (and 0-0) centers the knot', (tester) async {
    await _pump(tester, teamATotal: 0, teamBTotal: 0);
    expect(tester.widget<TeamTugRope>(find.byType(TeamTugRope)).share, 0.5);

    await _pump(tester, teamATotal: 9000, teamBTotal: 9000);
    expect(tester.widget<TeamTugRope>(find.byType(TeamTugRope)).share, 0.5);
  });
}
