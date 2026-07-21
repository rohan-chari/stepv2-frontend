import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/loadable.dart';
import 'package:step_tracker/screens/tabs/races_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/widgets/featured_race_card.dart';

// D13 (spec §3): featured tournaments merge into the races-tab featured row
// alongside featured races, and an ALL / RACES / TOURNAMENTS filter pill row
// filters the lists below (the featured row itself is never filtered). Missing
// keys degrade safely (the #1 rule).

Future<void> _noop() async {}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_coins': 500,
    'auth_held_coins': 0,
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Map<String, dynamic> _featuredRace() => {
  'raceId': 'fr1',
  'name': 'Daily 10K',
  'seedKind': 'DAILY_10K',
  'endsAt':
      DateTime.now().add(const Duration(hours: 5)).toUtc().toIso8601String(),
  'participantCount': 12,
  'finishReward': {'pool': 500, 'paidPlaces': 3},
};

Map<String, dynamic> _featuredTournament() => {
  'id': 'ft1',
  'name': 'Daily Dash',
  'status': 'PENDING',
  'seedId': 'seed-tournament-daily-dash',
  'seedKind': 'DAILY_DASH',
  'bracketSize': 4,
  'matchupDurationDays': 1,
  'championPrizeCoins': 150,
  'acceptedCount': 3,
};

Map<String, dynamic> _activeRace() => {
  'id': 'r1',
  'name': 'My Race',
  'status': 'ACTIVE',
  'maxDurationDays': 7,
  'participantCount': 3,
  'myStatus': 'ACCEPTED',
  'isCreator': false,
  'endsAt':
      DateTime.now().add(const Duration(days: 2)).toUtc().toIso8601String(),
};

Map<String, dynamic> _aliveTournament() => {
  'id': 't1',
  'name': 'Gauntlet',
  'status': 'ACTIVE',
  'bracketSize': 8,
  'currentRound': 2,
  'totalRounds': 3,
  'myStatus': 'ACCEPTED',
};

Future<void> _pump(
  WidgetTester tester, {
  List<Map<String, dynamic>> featuredRaces = const [],
  List<Map<String, dynamic>> featuredTournaments = const [],
  Map<String, dynamic>? racesData,
}) async {
  final auth = await _auth();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RacesTab(
          authService: auth,
          racesState: Loadable.success(
            racesData ??
                {'active': const [], 'pending': const [], 'completed': const []},
          ),
          friendsSteps: const [],
          featuredRaces: featuredRaces,
          featuredTournaments: featuredTournaments,
          onRacesChanged: _noop,
          onJoinFeaturedTournament: (_) async => true,
          displayName: 'Trail Walker',
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('featured row renders mixed race + tournament cards',
      (tester) async {
    await _pump(
      tester,
      featuredRaces: [_featuredRace()],
      featuredTournaments: [_featuredTournament()],
    );
    // The featured race card and the featured tournament card both appear.
    expect(find.byType(FeaturedRaceCard), findsOneWidget);
    expect(
      find.byKey(const Key('featured-tournament-join-ft1')),
      findsOneWidget,
    );
    expect(find.text('BRACKET'), findsOneWidget);
    expect(find.text('3/4 IN'), findsOneWidget);
  });

  testWidgets('empty featured-tournaments → row shows only races',
      (tester) async {
    await _pump(tester, featuredRaces: [_featuredRace()]);
    expect(find.byType(FeaturedRaceCard), findsOneWidget);
    expect(
      find.byKey(const Key('featured-tournament-join-ft1')),
      findsNothing,
    );
    expect(find.text('BRACKET'), findsNothing);
  });

  testWidgets('missing tournaments key is defensive (no crash, no section)',
      (tester) async {
    // racesData without a `tournaments` key + no featured tournaments.
    await _pump(
      tester,
      racesData: {
        'active': [_activeRace()],
        'pending': const [],
        'completed': const [],
      },
    );
    // Race content renders; no tournament row badge anywhere.
    // §4 removed the ACTIVE RACES section header — the personal list is now
    // pills + rows, so assert the user's own race ROW instead.
    expect(find.text('My Race'), findsOneWidget);
    expect(find.text('ALIVE'), findsNothing);
  });

  testWidgets(
      'pill filters the FEATURED ROW only; user races/brackets stay visible',
      (tester) async {
    // §9.5: the Races content now builds lazily (CustomScrollView +
    // SliverList-per-section), so offscreen sections are intentionally NOT built
    // on first frame. This test interleaves top-of-page checks (featured cards,
    // filter pills) with lower-list checks (the user's own race row, the
    // bracket row) and taps the pills between them, so it can't just scroll.
    // We instead give the test a tall viewport so the whole page lays out at
    // once and every lazy sliver is in view — this changes ONLY how the widgets
    // are brought into view for layout, not what the test asserts is true.
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(
      tester,
      featuredRaces: [_featuredRace()],
      featuredTournaments: [_featuredTournament()],
      racesData: {
        'active': [_activeRace()],
        'pending': const [],
        'completed': const [],
        'tournaments': [_aliveTournament()],
      },
    );

    // ALL (default): featured row shows BOTH a race card and a tournament card;
    // the user's own ACTIVE race row is visible underneath.
    expect(find.byKey(const Key('content-filter-all')), findsOneWidget);
    expect(find.byType(FeaturedRaceCard), findsOneWidget);
    expect(find.byKey(const Key('featured-tournament-join-ft1')), findsOneWidget);
    expect(find.text('My Race'), findsOneWidget);

    // RACES: featured row shows ONLY the race card; the featured tournament is
    // hidden — but the user's own personal list stays put.
    await tester.tap(find.byKey(const Key('content-filter-races')));
    await tester.pump();
    expect(find.byType(FeaturedRaceCard), findsOneWidget);
    expect(find.byKey(const Key('featured-tournament-join-ft1')), findsNothing);
    expect(find.text('My Race'), findsOneWidget); // NOT filtered

    // TOURNAMENTS: featured row shows ONLY the seeded tournament card; the
    // featured race is hidden — the personal list is still untouched.
    await tester.tap(find.byKey(const Key('content-filter-tournaments')));
    await tester.pump();
    expect(find.byType(FeaturedRaceCard), findsNothing);
    expect(find.byKey(const Key('featured-tournament-join-ft1')), findsOneWidget);
    expect(find.text('My Race'), findsOneWidget); // still visible

    // And the user's own bracket is still reachable in its own state pill,
    // regardless of which featured filter is selected. (§4.2 puts an alive
    // bracket with no live matchup in PENDING.)
    await tester.tap(find.byKey(const Key('personal-state-pending')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Gauntlet'), findsOneWidget);
    expect(find.text('ALIVE'), findsOneWidget);
  });

  testWidgets('TOURNAMENTS filter with no featured tournaments shows the '
      'featured empty note (user lists untouched)', (tester) async {
    await _pump(
      tester,
      featuredRaces: [_featuredRace()], // featured races exist; no featured brackets
      racesData: {
        'active': [_activeRace()],
        'pending': const [],
        'completed': const [],
      },
    );
    await tester.tap(find.byKey(const Key('content-filter-tournaments')));
    await tester.pump();
    expect(find.byKey(const Key('featured-empty-note')), findsOneWidget);
    expect(find.textContaining('No featured tournaments'), findsOneWidget);
    // The featured race card is filtered out of the row...
    expect(find.byType(FeaturedRaceCard), findsNothing);
    // ...but the user's own race list is untouched.
    expect(find.text('My Race'), findsOneWidget);
  });

  testWidgets('pill is hidden when there is no featured content at all',
      (tester) async {
    await _pump(
      tester,
      racesData: {
        'active': [_activeRace()],
        'pending': const [],
        'completed': const [],
      },
    );
    expect(find.byKey(const Key('content-filter-all')), findsNothing);
    // User content still renders normally.
    expect(find.text('My Race'), findsOneWidget);
  });
}
