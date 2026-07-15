import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/team_h2h_banner.dart';

// TR-803: the head-to-head tug-of-war banner — team plaques at each end,
// combined totals beneath, and a rope whose knot slides toward the leading
// side. Totals are always honest (TR-658) — the banner just renders what the
// team totals say.

Future<void> _pump(
  WidgetTester tester, {
  int teamATotal = 12340,
  int teamBTotal = 11900,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TeamH2HBanner(
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
  testWidgets('shows both plaques and formatted combined totals',
      (tester) async {
    await _pump(tester);

    expect(find.text('SWIFT CAPYS'), findsOneWidget);
    expect(find.text('TURBO BEAVERS'), findsOneWidget);
    expect(find.text('12,340'), findsOneWidget);
    expect(find.text('11,900'), findsOneWidget);
  });

  testWidgets('knot slides toward the leading side', (tester) async {
    await _pump(tester, teamATotal: 30000, teamBTotal: 10000);
    final rope = tester.widget<TeamTugRope>(find.byType(TeamTugRope));
    expect(rope.share, lessThan(0.5)); // knot pulled toward Team A's end

    await _pump(tester, teamATotal: 10000, teamBTotal: 30000);
    final rope2 = tester.widget<TeamTugRope>(find.byType(TeamTugRope));
    expect(rope2.share, greaterThan(0.5));
  });

  testWidgets('tie (and 0-0) centers the knot and says so', (tester) async {
    await _pump(tester, teamATotal: 0, teamBTotal: 0);
    final rope = tester.widget<TeamTugRope>(find.byType(TeamTugRope));
    expect(rope.share, 0.5);
    expect(find.text('ALL TIED'), findsOneWidget);
  });

  testWidgets('lead pill names the leading team and the gap', (tester) async {
    await _pump(tester, teamATotal: 12340, teamBTotal: 11900);
    expect(find.text('SWIFT CAPYS LEAD +440'), findsOneWidget);
  });
}
