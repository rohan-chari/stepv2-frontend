import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/utils/team_race.dart';
import 'package:step_tracker/widgets/team_scoreboard_cards.dart';

// The head-to-head SCOREBOARD cards: one card per side carrying that team's
// top-scorer portrait and combined total, with an OUTLINE crowning the leader.
// Totals are always honest (TR-658) and NULLABLE — a stealthed member makes a
// side's total genuinely unknowable, and every derived affordance (the crown,
// the lead banner) has to degrade rather than read null as zero.
//
// Replaces the old TeamH2HBanner tug-of-war banner (TR-803).

Future<void> _pumpCards(
  WidgetTester tester, {
  int? teamATotal = 12340,
  int? teamBTotal = 11900,
}) async {
  await tester.binding.setSurfaceSize(const Size(500, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TeamScoreboardCards(
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

Future<void> _pumpBanner(
  WidgetTester tester, {
  int? teamATotal,
  int? teamBTotal,
  RaceTeam? myTeam,
}) async {
  await tester.binding.setSurfaceSize(const Size(500, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TeamLeadBanner(
          teamAName: 'Swift Capys',
          teamBName: 'Turbo Beavers',
          teamATotal: teamATotal,
          teamBTotal: teamBTotal,
          myTeam: myTeam,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// The LEADING ribbon became an outline on the card itself; this key marks the
// crowned card so "which side is leading?" stays assertable.
final _leadingA = find.byKey(const ValueKey('team-leading-TEAM_A'));
final _leadingB = find.byKey(const ValueKey('team-leading-TEAM_B'));

void main() {
  group('TeamScoreboardCards', () {
    testWidgets('shows both team names and formatted combined totals', (
      tester,
    ) async {
      await _pumpCards(tester);

      expect(find.text('Swift Capys'), findsOneWidget);
      expect(find.text('Turbo Beavers'), findsOneWidget);
      expect(find.text('12,340'), findsOneWidget);
      expect(find.text('11,900'), findsOneWidget);
      expect(find.text('TEAM STEPS'), findsNWidgets(2));
    });

    testWidgets('the leading OUTLINE lands on the higher total only', (
      tester,
    ) async {
      await _pumpCards(tester, teamATotal: 30000, teamBTotal: 10000);
      expect(_leadingA, findsOneWidget);
      expect(_leadingB, findsNothing);

      await _pumpCards(tester, teamATotal: 10000, teamBTotal: 30000);
      expect(_leadingA, findsNothing);
      expect(_leadingB, findsOneWidget);
    });

    testWidgets('a tie (and 0-0) crowns neither side', (tester) async {
      await _pumpCards(tester, teamATotal: 0, teamBTotal: 0);
      expect(_leadingA, findsNothing);
      expect(_leadingB, findsNothing);

      await _pumpCards(tester, teamATotal: 9000, teamBTotal: 9000);
      expect(_leadingA, findsNothing);
      expect(_leadingB, findsNothing);
    });

    testWidgets('an unknowable total shows a dash and crowns no one', (
      tester,
    ) async {
      // F-16f: null means "hidden by stealth", not zero. Crowning the known
      // side would be a confident guess off a half-known scoreline.
      await _pumpCards(tester, teamATotal: null, teamBTotal: 11900);

      expect(find.text('—'), findsOneWidget);
      expect(find.text('11,900'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      expect(_leadingA, findsNothing);
      expect(_leadingB, findsNothing);
    });

    testWidgets('both cards keep the same height when a name wraps', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(500, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TeamScoreboardCards(
              teamAName: 'A',
              teamBName: 'The Extremely Long Team Name Brigade',
              teamATotal: 12340,
              teamBTotal: 11900,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final a = tester.getSize(
        find.byKey(const ValueKey('team-card-TEAM_A')),
      );
      final b = tester.getSize(
        find.byKey(const ValueKey('team-card-TEAM_B')),
      );
      expect(a.height, b.height);
    });

    testWidgets('the two big totals share a baseline', (
      tester,
    ) async {
      // Regression guard from the ribbon era: the LEADING strip used to be a
      // real row, so it had to be reserved on the trailing card or the two
      // totals fell out of line. An outline occupies no layout, so this should
      // hold trivially now — it stays because any future crown treatment that
      // DOES occupy layout has to keep the totals aligned.
      await _pumpCards(tester, teamATotal: 30000, teamBTotal: 10000);

      final top = tester.getTopLeft(find.text('30,000')).dy;
      final other = tester.getTopLeft(find.text('10,000')).dy;
      expect(top, other);
    });
  });

  group('TeamLeadBanner', () {
    testWidgets('tells the viewer they are ahead by the gap', (tester) async {
      await _pumpBanner(
        tester,
        teamATotal: 12340,
        teamBTotal: 11900,
        myTeam: RaceTeam.teamA,
      );
      expect(find.text('Keep it up! '), findsNothing); // spans, not Texts
      expect(find.textContaining('Keep it up!'), findsOneWidget);
      expect(find.textContaining('440'), findsOneWidget);
    });

    testWidgets('tells the trailing viewer how far back they are', (
      tester,
    ) async {
      await _pumpBanner(
        tester,
        teamATotal: 12340,
        teamBTotal: 11900,
        myTeam: RaceTeam.teamB,
      );
      expect(find.textContaining('Push!'), findsOneWidget);
      expect(find.textContaining('440'), findsOneWidget);
      expect(find.textContaining('Keep it up!'), findsNothing);
    });

    testWidgets('a spectator gets neutral third-person copy', (tester) async {
      await _pumpBanner(
        tester,
        teamATotal: 12340,
        teamBTotal: 11900,
        myTeam: null,
      );
      expect(find.textContaining('Swift Capys'), findsOneWidget);
      expect(find.textContaining('leads by'), findsOneWidget);
      expect(find.textContaining('Keep it up!'), findsNothing);
      expect(find.textContaining('Push!'), findsNothing);
    });

    testWidgets('a tie says so instead of naming a leader', (tester) async {
      await _pumpBanner(
        tester,
        teamATotal: 9000,
        teamBTotal: 9000,
        myTeam: RaceTeam.teamA,
      );
      expect(find.textContaining('Dead even'), findsOneWidget);
    });

    testWidgets('hides itself entirely when a total is unknowable', (
      tester,
    ) async {
      await _pumpBanner(
        tester,
        teamATotal: null,
        teamBTotal: 11900,
        myTeam: RaceTeam.teamA,
      );
      // Nothing rendered — and critically no leftover margin, since the gap
      // below the banner belongs to the banner rather than its caller.
      expect(find.byKey(const Key('team-lead-banner')), findsNothing);
      expect(find.textContaining('ahead'), findsNothing);
    });
  });

  group('TeamCardMember.topScorerOf', () {
    List<Map<String, dynamic>> ps() => [
      {
        'userId': 'a1',
        'team': 'TEAM_A',
        'displayName': 'Ann',
        'totalSteps': 100,
      },
      {
        'userId': 'a2',
        'team': 'TEAM_A',
        'displayName': 'Bo',
        'totalSteps': 900,
      },
      {
        'userId': 'b1',
        'team': 'TEAM_B',
        'displayName': 'Cy',
        'totalSteps': 400,
      },
    ];

    test('picks the highest scorer on the side', () {
      expect(
        TeamCardMember.topScorerOf(ps(), RaceTeam.teamA)!.displayName,
        'Bo',
      );
      expect(
        TeamCardMember.topScorerOf(ps(), RaceTeam.teamB)!.displayName,
        'Cy',
      );
    });

    test('skips a stealthed member so the portrait leaks nothing', () {
      final list = ps();
      list[1]['stealthed'] = true;
      // Bo outscores Ann but is hidden — picturing Bo would leak both their
      // sprite and their name while their own plank reads "???".
      expect(
        TeamCardMember.topScorerOf(list, RaceTeam.teamA)!.displayName,
        'Ann',
      );
    });

    test('returns null for an empty side', () {
      expect(TeamCardMember.topScorerOf(const [], RaceTeam.teamA), isNull);
    });
  });
}
