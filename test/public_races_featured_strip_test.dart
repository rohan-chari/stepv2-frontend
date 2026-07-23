import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/public_races_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/featured_race_card.dart';

// The FEATURED strip (seeded daily/weekly races) moved from the Races tab to
// the Public Races screen: the screen loads /races/featured itself and renders
// the same FeaturedRaceCard rail at the top of the FEATURED section, above the
// seeded brackets. These tests pump the real screen against a fake API — no
// reaching past the widget. Includes the tests ported from
// races_tab_featured_tournament_test / races_tab_no_upcoming_card_test when
// the strip moved here (2026-07-23), re-targeted at this screen's
// ALL / FEATURED / TOURNEYS / RACES filter.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AuthService> signedInAuth() async {
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

  // Frame pumps instead of pumpAndSettle — the featured card embeds a
  // SpinningCoin whose animation never settles.
  Future<void> pumpFrames(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 60));
  }

  Future<void> pumpScreen(WidgetTester tester, _FakeApi api) async {
    final auth = await signedInAuth();
    await tester.pumpWidget(MaterialApp(
      home: PublicRacesScreen(
        authService: auth,
        backendApiService: api,
      ),
    ));
    await pumpFrames(tester);
  }

  testWidgets('featured race strip renders on the Public Races screen',
      (tester) async {
    await pumpScreen(tester, _FakeApi(featuredRaces: [_featuredRace()]));

    expect(find.text('FEATURED'), findsWidgets);
    expect(find.byType(FeaturedRaceCard), findsOneWidget);
    // DAILY_10K seeds render under the friendly display name.
    expect(find.text('Daily Challenge'), findsOneWidget);
    // Not joined yet → the one-tap JOIN CTA.
    expect(find.text('JOIN'), findsWidgets);
  });

  testWidgets('older backend without /races/featured → no strip, no crash',
      (tester) async {
    await pumpScreen(tester, _FakeApi(featuredThrows: true));

    expect(find.byType(FeaturedRaceCard), findsNothing);
    // The rest of the screen still renders (the public race list).
    expect(find.text('TRAIL LOOP'), findsOneWidget);
  });

  testWidgets('joined featured race flips its CTA to VIEW', (tester) async {
    await pumpScreen(
      tester,
      _FakeApi(featuredRaces: [_featuredRace(myStatus: 'ACCEPTED')]),
    );

    expect(find.byType(FeaturedRaceCard), findsOneWidget);
    expect(find.text('VIEW'), findsWidgets);
  });

  // Ported: 'featured row renders mixed race + tournament cards'.
  testWidgets('FEATURED section renders mixed race strip + bracket cards',
      (tester) async {
    await pumpScreen(
      tester,
      _FakeApi(
        featuredRaces: [_featuredRace()],
        featuredTournaments: [_featuredTournament()],
      ),
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

  // Ported: 'empty featured-tournaments → row shows only races'.
  testWidgets('empty featured-tournaments → section shows only the race strip',
      (tester) async {
    await pumpScreen(tester, _FakeApi(featuredRaces: [_featuredRace()]));

    expect(find.byType(FeaturedRaceCard), findsOneWidget);
    expect(
      find.byKey(const Key('featured-tournament-join-ft1')),
      findsNothing,
    );
    expect(find.text('BRACKET'), findsNothing);
  });

  // Ported: 'pill filters the FEATURED ROW only; user races/brackets stay
  // visible' — re-targeted at this screen's group filter: each pill narrows to
  // its own group and the featured strip follows the FEATURED/ALL selections.
  testWidgets('filter pills select which groups show, including the strip',
      (tester) async {
    // Tall viewport so every group lays out at once — the assertions below
    // interleave taps with checks across the whole list.
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpScreen(
      tester,
      _FakeApi(
        featuredRaces: [_featuredRace()],
        featuredTournaments: [_featuredTournament()],
        userTournaments: [_userTournament()],
        publicRaces: [_publicRace()],
      ),
    );

    // ALL (default): every group renders — the strip, the seeded bracket, the
    // user bracket, and the public race.
    expect(find.byKey(const Key('public-filter-all')), findsOneWidget);
    expect(find.byType(FeaturedRaceCard), findsOneWidget);
    expect(
        find.byKey(const Key('featured-tournament-join-ft1')), findsOneWidget);
    expect(find.byKey(const Key('user-tournament-join-ut1')), findsOneWidget);
    expect(find.text('TRAIL LOOP'), findsOneWidget);

    // FEATURED: only the featured group — strip + seeded bracket.
    await tester.tap(find.byKey(const Key('public-filter-featured')));
    await pumpFrames(tester);
    expect(find.byType(FeaturedRaceCard), findsOneWidget);
    expect(
        find.byKey(const Key('featured-tournament-join-ft1')), findsOneWidget);
    expect(find.byKey(const Key('user-tournament-join-ut1')), findsNothing);
    expect(find.text('TRAIL LOOP'), findsNothing);

    // TOURNEYS: only user-created brackets — the strip is hidden.
    await tester.tap(find.byKey(const Key('public-filter-tournaments')));
    await pumpFrames(tester);
    expect(find.byType(FeaturedRaceCard), findsNothing);
    expect(
        find.byKey(const Key('featured-tournament-join-ft1')), findsNothing);
    expect(find.byKey(const Key('user-tournament-join-ut1')), findsOneWidget);
    expect(find.text('TRAIL LOOP'), findsNothing);

    // RACES: only the public race list — the strip is hidden.
    await tester.tap(find.byKey(const Key('public-filter-races')));
    await pumpFrames(tester);
    expect(find.byType(FeaturedRaceCard), findsNothing);
    expect(
        find.byKey(const Key('featured-tournament-join-ft1')), findsNothing);
    expect(find.byKey(const Key('user-tournament-join-ut1')), findsNothing);
    expect(find.text('TRAIL LOOP'), findsOneWidget);
  });

  // Ported: 'TOURNAMENTS filter with no featured tournaments shows the
  // featured empty note' — here the FEATURED pill with nothing featured shows
  // the group's empty note while other groups still exist.
  testWidgets('FEATURED filter with nothing featured shows the empty note',
      (tester) async {
    await pumpScreen(tester, _FakeApi(publicRaces: [_publicRace()]));

    await tester.tap(find.byKey(const Key('public-filter-featured')));
    await pumpFrames(tester);
    expect(
      find.text('No featured races or brackets right now.'),
      findsOneWidget,
    );
    expect(find.byType(FeaturedRaceCard), findsNothing);
    // The public race list is merely filtered out, not gone: RACES shows it.
    await tester.tap(find.byKey(const Key('public-filter-races')));
    await pumpFrames(tester);
    expect(find.text('TRAIL LOOP'), findsOneWidget);
  });

  // Ported from races_tab_no_upcoming_card_test: the featured row no longer
  // renders the upcoming/opt-in "next race" card, even when the backend still
  // attaches an `upcoming` payload (old clients keep rendering it; this build
  // drops it — auto-join covers the next daily/weekly instead).
  testWidgets('featured race with an `upcoming` payload shows only ONE card',
      (tester) async {
    await pumpScreen(
      tester,
      _FakeApi(featuredRaces: [_featuredRaceWithUpcoming()]),
    );

    // Only the live featured race — no second (upcoming) FeaturedRaceCard.
    expect(find.byType(FeaturedRaceCard), findsOneWidget);
    // The upcoming CTA copy must not appear.
    expect(find.text('OPT IN'), findsNothing);
    expect(find.text("YOU'RE IN"), findsNothing);
  });
}

Map<String, dynamic> _featuredRace({String? myStatus}) => {
      'raceId': 'fr1',
      'name': 'Daily 10K',
      'seedKind': 'DAILY_10K',
      'endsAt': DateTime.now()
          .add(const Duration(hours: 5))
          .toUtc()
          .toIso8601String(),
      'participantCount': 12,
      'finishReward': {'pool': 500, 'paidPlaces': 3},
      'myStatus': myStatus,
      'isFull': false,
    };

Map<String, dynamic> _featuredRaceWithUpcoming() => {
      ..._featuredRace(),
      // Backend still sends the pre-registerable next race — must be ignored.
      'upcoming': {
        'raceId': 'fr1-next',
        'scheduledStartAt': DateTime.now()
            .add(const Duration(hours: 20))
            .toUtc()
            .toIso8601String(),
        'endsAt': DateTime.now()
            .add(const Duration(days: 1, hours: 5))
            .toUtc()
            .toIso8601String(),
        'participantCount': 2,
        'isFull': false,
      },
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

Map<String, dynamic> _userTournament() => {
      'id': 'ut1',
      'name': 'Gauntlet',
      'status': 'PENDING',
      'bracketSize': 8,
      'matchupDurationDays': 2,
      'buyInAmount': 0,
      'acceptedCount': 2,
    };

Map<String, dynamic> _publicRace() => {
      'id': 'race-1',
      'name': 'Trail Loop',
      'status': 'PENDING',
      'participantCount': 2,
      'maxDurationDays': 3,
      'buyInAmount': 0,
      'creator': {'displayName': 'walker'},
    };

class _FakeApi extends BackendApiService {
  _FakeApi({
    this.featuredThrows = false,
    this.featuredRaces = const [],
    this.featuredTournaments = const [],
    this.userTournaments = const [],
    this.publicRaces = const [
      {
        'id': 'race-1',
        'name': 'Trail Loop',
        'status': 'PENDING',
        'participantCount': 2,
        'maxDurationDays': 3,
        'buyInAmount': 0,
        'creator': {'displayName': 'walker'},
      },
    ],
  });

  final bool featuredThrows;
  final List<Map<String, dynamic>> featuredRaces;
  final List<Map<String, dynamic>> featuredTournaments;
  final List<Map<String, dynamic>> userTournaments;
  final List<Map<String, dynamic>> publicRaces;

  @override
  Future<List<Map<String, dynamic>>> fetchFeaturedRaces({
    required String identityToken,
  }) async {
    if (featuredThrows) throw Exception('404');
    return featuredRaces;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchPublicRaces({
    required String identityToken,
  }) async =>
      publicRaces;

  @override
  Future<Map<String, dynamic>> fetchPublicTournaments({
    required String identityToken,
  }) async =>
      {'featured': featuredTournaments, 'tournaments': userTournaments};

  @override
  Future<Map<String, dynamic>> fetchRaces({
    required String identityToken,
  }) async =>
      {'active': const [], 'pending': const [], 'tournaments': const []};
}
