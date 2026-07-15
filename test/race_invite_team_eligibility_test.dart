import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/screens/race_invite_screen.dart';

// TR-708: inviting to a TEAM race grays out friends whose last-seen client
// can't render team races (teamRaceEligible false) with a "needs app update"
// badge, instead of failing after selection. A missing flag (older backend)
// stays selectable — the server still hard-blocks at invite time (TR-707).
// Individual-race invites are unaffected.

final _friends = [
  {'id': 'f1', 'displayName': 'Updated Ursula', 'teamRaceEligible': true},
  {'id': 'f2', 'displayName': 'Stale Stanley', 'teamRaceEligible': false},
  {'id': 'f3', 'displayName': 'Unknown Uma'}, // flag absent -> selectable
];

Future<void> _pump(WidgetTester tester, {required bool teamRaceMode}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RaceInviteScreen(
        friends: _friends,
        teamRaceMode: teamRaceMode,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('TR-708: ineligible friends are badged and unselectable in '
      'team mode', (tester) async {
    await _pump(tester, teamRaceMode: true);

    expect(find.text('NEEDS APP UPDATE'), findsOneWidget);

    // Tapping Stanley does nothing — no INVITE button appears.
    await tester.tap(find.textContaining('Stale Stanley'));
    await tester.pump();
    expect(find.textContaining('INVITE 1 FRIEND'), findsNothing);

    // Ursula and flag-less Uma both select fine.
    await tester.tap(find.textContaining('Updated Ursula'));
    await tester.pump();
    await tester.tap(find.textContaining('Unknown Uma'));
    await tester.pump();
    expect(find.textContaining('INVITE 2 FRIENDS'), findsOneWidget);
  });

  testWidgets('TR-708: individual-race invites ignore the eligibility flag',
      (tester) async {
    await _pump(tester, teamRaceMode: false);

    expect(find.text('NEEDS APP UPDATE'), findsNothing);
    await tester.tap(find.textContaining('Stale Stanley'));
    await tester.pump();
    expect(find.textContaining('INVITE 1 FRIEND'), findsOneWidget);
  });
}
