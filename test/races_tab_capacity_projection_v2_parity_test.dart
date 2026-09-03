import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/loadable.dart';
import 'package:step_tracker/screens/tabs/races_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/widgets/powerup_icon.dart';
import 'package:step_tracker/widgets/race_ui.dart' show RacerAvatar;
import 'package:step_tracker/widgets/spinning_crate.dart';
import 'package:step_tracker/widgets/team_scoreline.dart';

/// Frontend parity lock for backend load profile
/// `authenticated-races-tab-reveal-v1@2.0.0` and projection marker
/// `races-tab-open-projection-v2`.
///
/// These maps have the exact existing `GET /races?view=compact-v1` shape. The
/// suite pumps the real [RacesTab], rather than a test-only presenter, so a
/// backend workload field can only claim coverage when the production widget
/// actually consumes it.
const _projectionVersion = 'races-tab-open-projection-v2';

const _requiredCoverageVariants = <String>{
  'ordinary_classic_active',
  'ordinary_team_active',
  'ordinary_pending_owner',
  'ordinary_pending_accepted',
  'ordinary_invite',
  'ordinary_completed',
  'pinned_classic',
  'pinned_team',
  'pinned_tournament',
  'ordinary_placement_visible',
  'ordinary_placement_hidden',
  'ordinary_inventory_held_typed',
  'ordinary_inventory_mystery_box',
  'ordinary_inventory_queued_box',
  'ordinary_effect_positive',
  'ordinary_effect_negative',
  'tournament_invite',
  'tournament_lobby',
  'tournament_between_rounds',
  'tournament_live_match',
  'tournament_eliminated',
  'tournament_champion',
  'tournament_completed_non_champion',
  'tournament_match_placement_visible',
  'tournament_match_placement_hidden',
  'tournament_match_inventory_held_typed',
  'tournament_match_inventory_mystery_box',
  'tournament_match_inventory_queued_box',
};

const _coverageByFixture = <String, Set<String>>{
  'classic-active': {
    'ordinary_classic_active',
    'pinned_classic',
    'ordinary_placement_visible',
    'ordinary_inventory_held_typed',
    'ordinary_inventory_mystery_box',
    'ordinary_inventory_queued_box',
    'ordinary_effect_positive',
    'ordinary_effect_negative',
  },
  'classic-hidden': {'ordinary_placement_hidden'},
  'team-active': {'ordinary_team_active', 'pinned_team'},
  'pending-owner': {'ordinary_pending_owner'},
  'pending-accepted': {'ordinary_pending_accepted'},
  'ordinary-invite': {'ordinary_invite'},
  'ordinary-completed': {'ordinary_completed'},
  'tournament-invite': {'tournament_invite'},
  'tournament-lobby': {'tournament_lobby'},
  'tournament-between': {'tournament_between_rounds'},
  'tournament-live': {
    'pinned_tournament',
    'tournament_live_match',
    'tournament_match_placement_visible',
    'tournament_match_inventory_held_typed',
    'tournament_match_inventory_mystery_box',
    'tournament_match_inventory_queued_box',
  },
  'tournament-live-hidden': {'tournament_match_placement_hidden'},
  'tournament-eliminated': {'tournament_eliminated'},
  'tournament-champion': {'tournament_champion'},
  'tournament-finished': {'tournament_completed_non_champion'},
};

Future<void> _noop() async {}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'capacity-token',
    'auth_user_identifier': 'capacity-user',
    'auth_session_token': 'capacity-session',
    'auth_backend_user_id': 'viewer',
    'auth_display_name': 'Trail Walker',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

String _futureIso({int days = 3}) =>
    DateTime.now().toUtc().add(Duration(days: days)).toIso8601String();

String _pastIso({int days = 3}) =>
    DateTime.now().toUtc().subtract(Duration(days: days)).toIso8601String();

Map<String, dynamic> _ordinary({
  required String id,
  required String name,
  required String status,
  String myStatus = 'ACCEPTED',
  bool isCreator = false,
  bool favorite = false,
}) => {
  'id': id,
  'name': name,
  'status': status,
  'myStatus': myStatus,
  'maxDurationDays': 9,
  'participantCount': 4,
  'creator': {'displayName': 'Host Runner'},
  'isCreator': isCreator,
  'isFavorite': favorite,
  'favoritedAt': favorite ? _pastIso(days: 1) : null,
  'createdAt': _pastIso(days: 2),
  'startedAt': status == 'ACTIVE' ? _pastIso(days: 1) : null,
  'endsAt': status == 'ACTIVE' ? _futureIso(days: 3) : null,
  'scheduledStartAt': null,
  'scheduledEndAt': null,
  'myInviteExpiresAt': myStatus == 'INVITED' ? _futureIso(days: 5) : null,
};

Map<String, dynamic> _classicActive() => {
  ..._ordinary(
    id: 'classic-active',
    name: 'Classic Sprint',
    status: 'ACTIVE',
    favorite: true,
  ),
  'placementPrivacyActive': true,
  'myDisplayPlacement': 2,
  // This canonical rank must not leak while the privacy projection is active.
  'myPlacement': 9,
  'myPlacementHidden': false,
  'slotItems': const [
    {'type': 'PROTEIN_SHAKE', 'rarity': 'COMMON', 'status': 'HELD'},
    {'type': null, 'rarity': null, 'status': 'MYSTERY_BOX'},
  ],
  'mysteryBoxCount': 1,
  'queuedBoxCount': 2,
  'myActiveEffects': const [
    {
      'type': 'RUNNERS_HIGH',
      'status': 'ACTIVE',
      'sourceUserId': 'viewer',
      'expiresAt': '2030-01-01T00:00:00.000Z',
    },
    {
      'type': 'LEG_CRAMP',
      'status': 'ACTIVE',
      'sourceUserId': 'other',
      'expiresAt': '2030-01-01T00:00:00.000Z',
    },
  ],
};

Map<String, dynamic> _classicHidden() => {
  ..._ordinary(
    id: 'classic-hidden',
    name: 'Hidden Rank Dash',
    status: 'ACTIVE',
  ),
  'placementPrivacyActive': true,
  'myDisplayPlacement': null,
  'myPlacement': 1,
  'myPlacementHidden': true,
  'slotItems': const [],
  'mysteryBoxCount': 0,
  'queuedBoxCount': 0,
  'myActiveEffects': const [],
};

Map<String, dynamic> _teamActive() => {
  ..._ordinary(
    id: 'team-active',
    name: 'Team Relay',
    status: 'ACTIVE',
    favorite: true,
  ),
  'isTeamRace': true,
  'teamSize': 5,
  'myTeam': 'TEAM_A',
  'teamAName': 'Trail Blazers',
  'teamBName': 'River Runners',
  'teamATotalSteps': 11000,
  'teamBTotalSteps': 9000,
  'winnerTeam': null,
  'teams': {
    'teamA': {'name': 'Trail Blazers', 'memberCount': 5, 'totalSteps': 12345},
    'teamB': {'name': 'River Runners', 'memberCount': 5, 'totalSteps': 9876},
    'asOf': _pastIso(days: 0),
  },
  'placementPrivacyActive': false,
  'myPlacement': 1,
  'myPlacementHidden': false,
  'slotItems': const [],
  'mysteryBoxCount': 0,
  'queuedBoxCount': 0,
  'myActiveEffects': const [],
};

Map<String, dynamic> _tournament({
  required String id,
  required String name,
  required String status,
  String myStatus = 'ACCEPTED',
  bool favorite = false,
}) => {
  'id': id,
  'name': name,
  'status': status,
  'myStatus': myStatus,
  'isFavorite': favorite,
  'favoritedAt': favorite ? _pastIso(days: 1) : null,
  'bracketSize': 8,
  'acceptedCount': 5,
  'currentRound': status == 'ACTIVE' ? 2 : 0,
  'totalRounds': 3,
  'championPrizeCoins': 0,
  'potCoins': 0,
  'prizePool': const {'funded': true, 'coins': 777},
  'myIdentity': const {
    'displayName': 'Trail Walker',
    'animal': 'corgi_puppy',
    'equippedAccessories': [
      {'slot': 'HEAD', 'assetId': 'trail_hat'},
    ],
  },
  'createdAt': _pastIso(days: 2),
  'startedAt': status == 'ACTIVE' ? _pastIso(days: 1) : null,
  'completedAt': status == 'COMPLETED' ? _pastIso(days: 1) : null,
};

Map<String, dynamic> _tournamentLive({bool hidden = false}) => {
  ..._tournament(
    id: hidden ? 'tournament-live-hidden' : 'tournament-live',
    name: hidden ? 'Masked Match Bracket' : 'Live Match Bracket',
    status: 'ACTIVE',
    favorite: !hidden,
  ),
  'myCurrentMatchRaceId': hidden ? 'match-hidden' : 'match-visible',
  'myCurrentMatch': {
    'raceId': hidden ? 'match-hidden' : 'match-visible',
    'endsAt': _futureIso(days: 2),
    'myPlacement': hidden ? null : 3,
    'myPlacementHidden': hidden,
    'slotItems': hidden
        ? const <Map<String, dynamic>>[]
        : const [
            {'type': 'SECOND_WIND', 'rarity': 'RARE', 'status': 'HELD'},
            {'type': null, 'rarity': null, 'status': 'MYSTERY_BOX'},
          ],
    'mysteryBoxCount': hidden ? 0 : 1,
    'queuedBoxCount': hidden ? 0 : 1,
  },
};

Map<String, dynamic> _racesPayload() => {
  'contract': 'race-list-compact-v1',
  'active': [_classicActive(), _classicHidden(), _teamActive()],
  'pending': [
    _ordinary(
      id: 'ordinary-invite',
      name: 'Invite From Host',
      status: 'PENDING',
      myStatus: 'INVITED',
    ),
    _ordinary(
      id: 'pending-owner',
      name: 'Owner Setup Race',
      status: 'PENDING',
      isCreator: true,
    ),
    _ordinary(
      id: 'pending-accepted',
      name: 'Accepted Waiting Race',
      status: 'PENDING',
    ),
  ],
  'completed': [
    _ordinary(
      id: 'ordinary-completed',
      name: 'Completed Classic',
      status: 'COMPLETED',
    ),
  ],
  'tournaments': [
    _tournament(
      id: 'tournament-invite',
      name: 'Tournament Invitation',
      status: 'PENDING',
      myStatus: 'INVITED',
    ),
    _tournament(
      id: 'tournament-lobby',
      name: 'Lobby Bracket',
      status: 'PENDING',
    ),
    _tournament(
      id: 'tournament-between',
      name: 'Between Rounds Bracket',
      status: 'ACTIVE',
    ),
    _tournamentLive(),
    _tournamentLive(hidden: true),
    {
      ..._tournament(
        id: 'tournament-eliminated',
        name: 'Eliminated Bracket',
        status: 'ACTIVE',
      ),
      'myEliminatedInRound': 1,
    },
    {
      ..._tournament(
        id: 'tournament-champion',
        name: 'Champion Bracket',
        status: 'COMPLETED',
      ),
      'championUserId': 'viewer',
    },
    {
      ..._tournament(
        id: 'tournament-finished',
        name: 'Finished Nonchampion Bracket',
        status: 'COMPLETED',
      ),
      'championUserId': 'someone-else',
    },
  ],
};

Future<void> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(500, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RacesTab(
          authService: await _auth(),
          racesState: Loadable.success(_racesPayload()),
          friendsSteps: const [],
          onRacesChanged: _noop,
          displayName: 'Trail Walker',
          publicRacesCount: 11,
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _select(WidgetTester tester, String state) async {
  await tester.tap(find.byKey(Key('personal-state-$state')));
  await tester.pump(const Duration(milliseconds: 200));
}

Finder _inside(Key key, Finder descendant) => find.descendant(
  // Favorited rows are intentionally rendered once in PINNED and once in
  // their selected shelf. The last surface is the shelf copy; both consume
  // the same payload and production row builder.
  of: find.byKey(key).last,
  matching: descendant,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.bara.app',
      version: '3.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  test('v2 fixture inventory names exactly 28 required variants', () {
    final covered = _coverageByFixture.values.expand((value) => value).toSet();

    expect(_projectionVersion, 'races-tab-open-projection-v2');
    expect(_requiredCoverageVariants, hasLength(28));
    expect(covered, _requiredCoverageVariants);
    expect(
      covered,
      isNot(contains('tournament_cancelled')),
      reason: 'GET /races filters cancelled tournaments from this profile.',
    );
  });

  testWidgets(
    'ACTIVE renders classic/team/live-match, pins, privacy, inventory, effects, identity, prize, and discovery count',
    (tester) async {
      await _pump(tester);

      expect(
        find.descendant(
          of: find.byKey(const Key('races-public-action')),
          matching: find.text('11'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('personal-state-count-active')))
            .data,
        '5',
      );

      for (final key in [
        'pinned-race-row-classic-active',
        'pinned-race-row-team-active',
        'pinned-tournament-row-tournament-live',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }

      final classic = const Key('race-card-surface-classic-active');
      expect(_inside(classic, find.text('2ND PLACE')), findsWidgets);
      expect(_inside(classic, find.text('9TH PLACE')), findsNothing);
      expect(
        _inside(classic, find.byType(PowerupIcon)),
        findsNWidgets(3),
        reason: 'one held item plus one positive and one negative effect',
      );
      final classicCrates = tester
          .widgetList<CrateIcon>(_inside(classic, find.byType(CrateIcon)))
          .toList();
      expect(classicCrates.where((crate) => crate.filled), hasLength(2));
      expect(
        _inside(classic, find.byKey(const Key('race-effects-classic-active'))),
        findsWidgets,
      );

      const hidden = Key('race-card-surface-classic-hidden');
      expect(_inside(hidden, find.text('??? PLACE')), findsOneWidget);
      expect(_inside(hidden, find.text('1ST PLACE')), findsNothing);

      const team = Key('race-card-surface-team-active');
      expect(_inside(team, find.text('5v5')), findsWidgets);
      expect(_inside(team, find.byType(TeamScoreline)), findsWidgets);
      expect(_inside(team, find.textContaining('12,345')), findsWidgets);
      expect(_inside(team, find.textContaining('9,876')), findsWidgets);
      expect(
        _inside(team, find.byKey(const Key('team-totals-as-of-team-active'))),
        findsWidgets,
      );

      const live = Key('tournament-card-surface-tournament-live');
      expect(_inside(live, find.text('SEMIFINALS')), findsWidgets);
      expect(_inside(live, find.text('3RD PLACE')), findsWidgets);
      expect(_inside(live, find.text('777')), findsWidgets);
      expect(
        _inside(
          live,
          find.byKey(const Key('tournament-card-inventory-tournament-live')),
        ),
        findsWidgets,
      );
      final avatar = tester.widget<RacerAvatar>(
        _inside(
          live,
          find.byKey(const Key('tournament-identity-avatar-tournament-live')),
        ).first,
      );
      expect(avatar.animal, 'corgi_puppy');
      expect(avatar.accessories.single['assetKey'], 'trail_hat');

      const hiddenMatch = Key('tournament-card-surface-tournament-live-hidden');
      expect(_inside(hiddenMatch, find.text('??? PLACE')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invite strip and PENDING distinguish ordinary owner/accepted plus tournament invite/lobby/between-rounds',
    (tester) async {
      await _pump(tester);

      expect(find.byKey(const Key('invites-strip-header')), findsOneWidget);
      expect(find.text('Invite From Host'), findsOneWidget);
      expect(find.textContaining('by @Host Runner'), findsOneWidget);
      expect(
        find.byKey(const Key('tournament-accept-tournament-invite')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('tournament-decline-tournament-invite')),
        findsOneWidget,
      );

      await _select(tester, 'pending');
      expect(
        tester
            .widget<Text>(find.byKey(const Key('personal-state-count-pending')))
            .data,
        '4',
      );
      expect(find.text('Owner Setup Race'), findsOneWidget);
      expect(find.text('Accepted Waiting Race'), findsOneWidget);
      expect(find.text('SETUP'), findsOneWidget);
      expect(
        _inside(
          const Key('race-card-surface-pending-owner'),
          find.text('9d race'),
        ),
        findsOneWidget,
      );
      expect(
        _inside(
          const Key('race-card-surface-pending-accepted'),
          find.text('9d race'),
        ),
        findsOneWidget,
      );
      expect(find.text('Lobby Bracket'), findsOneWidget);
      expect(
        _inside(
          const Key('tournament-card-surface-tournament-lobby'),
          find.text('5/8 FILLED'),
        ),
        findsOneWidget,
      );
      expect(find.text('Between Rounds Bracket'), findsOneWidget);
      expect(find.text("ROUND 2 OF 3 · YOU'RE ALIVE"), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'COMPLETED distinguishes ordinary, eliminated, champion, and nonchampion rows',
    (tester) async {
      await _pump(tester);
      await _select(tester, 'completed');

      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('personal-state-count-completed')),
            )
            .data,
        '4',
      );
      expect(find.text('Completed Classic'), findsOneWidget);
      expect(
        _inside(
          const Key('race-card-surface-ordinary-completed'),
          find.text('9d race'),
        ),
        findsOneWidget,
      );
      expect(find.text('Eliminated Bracket'), findsOneWidget);
      expect(find.textContaining('KNOCKED OUT'), findsOneWidget);
      expect(find.text('OUT'), findsOneWidget);
      expect(find.text('Champion Bracket'), findsOneWidget);
      expect(find.text('CHAMPION'), findsOneWidget);
      expect(find.text('Finished Nonchampion Bracket'), findsOneWidget);
      expect(find.text('FINISHED'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing v2 additive fields still degrades without a crash', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RacesTab(
            authService: await _auth(),
            racesState: const Loadable.success({
              'active': [
                {
                  'id': 'old-race',
                  'name': 'Old Backend Race',
                  'status': 'ACTIVE',
                },
              ],
              'pending': [],
              'completed': [],
              'tournaments': [
                {
                  'id': 'old-tournament',
                  'name': 'Old Backend Bracket',
                  'status': 'ACTIVE',
                  'myStatus': 'ACCEPTED',
                },
              ],
            }),
            friendsSteps: const [],
            onRacesChanged: _noop,
            displayName: 'Trail Walker',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Old Backend Race'), findsOneWidget);
    expect(find.text('??? PLACE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
