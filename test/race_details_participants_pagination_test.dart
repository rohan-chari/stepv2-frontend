import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/edit_race_screen.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/screens/race_invite_screen.dart';
import 'package:step_tracker/services/activation_analytics_service.dart';
import 'package:step_tracker/services/app_route_observer.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/utils/team_race.dart';
import 'package:step_tracker/widgets/home_course_track.dart';
import 'package:step_tracker/widgets/pill_button.dart';
import 'package:step_tracker/widgets/race_payout_scorecard.dart';
import 'package:step_tracker/widgets/team_lobby_board.dart';

// ---------------------------------------------------------------------------
// Race-details participants pagination
// (docs/race-details-participants-pagination-requirements.md).
//
// `race.participants` on GET /races/:id[/bootstrap] becomes a PAGE once this
// build sends the `race_participants_paging` capability token. The load-bearing
// consequence: THE VIEWER'S OWN ROW IS NOT GUARANTEED TO BE IN THE PAGE. Every
// count, membership check, team assignment and "my steps" read must come from
// the top-level summary fields (`acceptedCount`, `teamAAcceptedCount`/
// `teamBAcceptedCount`, `myStatus`, `myTeam`, `myTotalSteps`,
// `participantUserIds`) instead of scanning the array.
//
// Every fixture below therefore models the dangerous case: a page that does
// NOT contain `user-1` (the signed-in viewer), with the truth living only in
// the summary fields.
// ---------------------------------------------------------------------------

Map<String, dynamic> _participant(
  String id, {
  String status = 'ACCEPTED',
  String? team,
}) => {
  'userId': id,
  'displayName': 'Racer $id',
  'status': status,
  'team': ?team,
  'accessories': const [],
};

/// A large PENDING non-team race served as a 15-row page out of 473 accepted.
/// The viewer (`user-1`) is deliberately absent from the page.
class _PagedPendingApi extends BackendApiService {
  _PagedPendingApi({
    this.acceptedCount = 473,
    this.pageSize = 15,
    this.includeSummaryFields = true,
    this.includeParticipantUserIds = true,
  });

  final int acceptedCount;
  final int pageSize;

  /// When false the response is what an OLDER backend sends: the full array,
  /// no summary fields at all. The screen must degrade, not crash.
  final bool includeSummaryFields;
  final bool includeParticipantUserIds;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async {
    final rows = includeSummaryFields
        // Server-paged: only the page comes down, and `user-1` isn't in it.
        ? [for (var i = 0; i < pageSize; i++) _participant('u$i')]
        // Old backend: the whole field, viewer included.
        : [
            _participant('user-1'),
            for (var i = 0; i < acceptedCount - 1; i++) _participant('u$i'),
          ];
    return {
      'id': raceId,
      'name': 'Weekly Challenge',
      'seedKind': 'WEEKLY',
      'status': 'PENDING',
      'maxDurationDays': 7,
      'buyInAmount': 0,
      'payoutPreset': 'WINNER_TAKES_ALL',
      'potCoins': 0,
      'projectedPotCoins': 0,
      'myStatus': 'ACCEPTED',
      'isCreator': true,
      'participants': rows,
      if (includeSummaryFields) ...{
        'acceptedCount': acceptedCount,
        'teamAAcceptedCount': null,
        'teamBAcceptedCount': null,
        'myTotalSteps': null,
        'participantsPagination': {
          'offset': 0,
          'limit': pageSize,
          'total': acceptedCount,
          'hasMore': true,
          'nextOffset': pageSize,
        },
      },
      if (includeSummaryFields && includeParticipantUserIds)
        'participantUserIds': [
          'user-1',
          'friend-2',
          for (var i = 0; i < pageSize; i++) 'u$i',
        ],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async =>
      const {'coins': 320, 'heldCoins': 0};
}

/// An ACTIVE race the viewer IS in, served as a page that omits their row.
/// The old `.any(p => p.userId == me)` scan would call them a spectator.
class _PagedActiveApi extends BackendApiService {
  static const int myTotalSteps = 8200;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async => {
    'id': raceId,
    'name': 'Daily Challenge',
    'seedKind': 'DAILY',
    'status': 'ACTIVE',
    'maxDurationDays': 1,
    'buyInAmount': 0,
    'payoutPreset': 'TOP_HALF',
    'potCoins': 0,
    'heldPotCoins': 0,
    'projectedPotCoins': 0,
    'myStatus': 'ACCEPTED',
    'isCreator': false,
    'powerupsEnabled': false,
    'leaveAction': 'FORFEIT',
    'endsAt': '2126-04-10T12:00:00.000Z',
    'participants': [for (var i = 0; i < 15; i++) _participant('u$i')],
    'acceptedCount': 247,
    'teamAAcceptedCount': null,
    'teamBAcceptedCount': null,
    'myTotalSteps': myTotalSteps,
    'participantsPagination': const {
      'offset': 0,
      'limit': 15,
      'total': 247,
      'hasMore': true,
      'nextOffset': 15,
    },
  };

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async => const {
    'status': 'ACTIVE',
    'participants': [
      {'userId': 'u0', 'displayName': 'Racer u0', 'totalSteps': 9000.0},
    ],
    'powerupData': {
      'enabled': false,
      'inventory': [],
      'powerupSlots': 3,
      'queuedBoxCount': 0,
      'activeEffects': [],
    },
  };

  @override
  Future<Map<String, dynamic>> fetchRaceMessages({
    required String identityToken,
    required String raceId,
    String? cursor,
    int? limit,
    String? kind,
  }) async => const {'messages': [], 'events': []};

  @override
  Future<Map<String, dynamic>> fetchRaceFeed({
    String? cursor,
    required String identityToken,
    required String raceId,
    int? limit,
  }) async => const {'events': []};

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async =>
      const {'coins': 320, 'heldCoins': 0};
}

class _RecordingActivationAnalytics extends ActivationAnalyticsService {
  _RecordingActivationAnalytics() : super(isIosForTesting: true);

  final List<Map<String, String>> leaderboardViews = [];

  @override
  Future<void> record(
    String name, {
    String? sessionId,
    String? ownerUserId,
    Map<String, String> context = const {},
  }) async {
    if (name == 'race_leaderboard_viewed') {
      leaderboardViews.add(Map<String, String>.from(context));
    }
  }

  @override
  Future<void> flush(String? authToken, {String? userId}) async {}
}

/// A PENDING team race whose page holds ONE row; the real 2v2 field lives in
/// `teamAAcceptedCount`/`teamBAcceptedCount`, and the viewer's side in
/// `myTeam`.
class _PagedTeamApi extends BackendApiService {
  _PagedTeamApi({this.myStatus = 'ACCEPTED', this.myTeam = 'TEAM_B'});

  static const int teamACount = 2;
  static const int teamBCount = 2;
  final String myStatus;
  final String? myTeam;

  String? switchedTo;

  @override
  Future<Map<String, dynamic>> setRaceTeam({
    required String identityToken,
    required String raceId,
    required String team,
  }) async {
    switchedTo = team;
    return {
      'participant': {'userId': 'user-1', 'team': team},
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async => {
    'id': raceId,
    'name': 'Team Showdown',
    'status': 'PENDING',
    'isTeamRace': true,
    'teamSize': 2,
    'teamAName': 'Swift Capys',
    'teamBName': 'Turbo Beavers',
    'maxDurationDays': 7,
    'buyInAmount': 0,
    'payoutPreset': 'WINNER_TAKES_ALL',
    'potCoins': 0,
    'myStatus': myStatus,
    'myTeam': myTeam,
    'isCreator': myStatus == 'ACCEPTED',
    // One row only — everything else is off-page.
    'participants': [_participant('u9', team: 'TEAM_A')],
    'acceptedCount': teamACount + teamBCount,
    'teamAAcceptedCount': teamACount,
    'teamBAcceptedCount': teamBCount,
    'myTotalSteps': null,
    'participantsPagination': const {
      'offset': 0,
      'limit': 1,
      'total': 4,
      'hasMore': true,
      'nextOffset': 1,
    },
  };

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async =>
      const {'coins': 320, 'heldCoins': 0};
}

Future<AuthService> _createAuthService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_coins': 420,
    'auth_held_coins': 0,
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

Future<void> _pump(
  WidgetTester tester,
  BackendApiService api, {
  List<Map<String, dynamic>> friends = const [],
  String raceId = 'race-paged',
  ActivationAnalyticsService? activationAnalyticsService,
}) async {
  final authService = await _createAuthService();
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [appRouteObserver],
      home: RaceDetailScreen(
        authService: authService,
        raceId: raceId,
        backendApiService: api,
        activationAnalyticsService: activationAnalyticsService,
        friends: friends,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.bara.app',
      version: '2.3.5',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('capability token', () {
    test('clientFeaturesHeader advertises race_participants_paging', () {
      final tokens = BackendApiService.clientFeaturesHeader.split(',');
      expect(tokens, contains('race_participants_paging'));
    });

    test('the token is present in BOTH header variants', () {
      final source = File(
        'lib/services/backend_api_service.dart',
      ).readAsStringSync();
      final start = source.indexOf('clientFeaturesHeader = _adsSupported');
      final end = source.indexOf('/// Replays a persisted results dismissal');
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final headerDefinition = source.substring(start, end);
      expect(
        RegExp('race_participants_paging').allMatches(headerDefinition),
        hasLength(2),
        reason:
            'race_participants_paging must occur in both the ads and ad-less '
            'header variants — half the builds otherwise never page',
      );
    });

    test('existing feature tokens survive alongside it', () {
      final tokens = BackendApiService.clientFeaturesHeader.split(',');
      for (final token in const [
        'characters',
        'team_races',
        'race_leave',
        'seeded_race_buckets',
        'remote_assets',
      ]) {
        expect(tokens, contains(token));
      }
    });
  });

  group('pending hero + PARTICIPANTS list', () {
    testWidgets('header count is the true total, sprites are capped', (
      tester,
    ) async {
      await _pump(tester, _PagedPendingApi());

      // The true field size, not the page length.
      expect(find.text('473'), findsWidgets);
      expect(find.text('15'), findsNothing);

      final track = tester.widget<HomeCourseTrack>(
        find.byType(HomeCourseTrack),
      );
      expect(track.runners, hasLength(15));
    });

    testWidgets('the PARTICIPANTS list shows a "+N more" trailing row', (
      tester,
    ) async {
      await _pump(tester, _PagedPendingApi());

      expect(find.text('PARTICIPANTS'), findsOneWidget);
      expect(find.text('+458 more'), findsOneWidget);
    });

    testWidgets('an oversized UNPAGED response is still render-capped', (
      tester,
    ) async {
      // No summary fields at all (older backend), 40 participants in one array.
      await _pump(
        tester,
        _PagedPendingApi(acceptedCount: 40, includeSummaryFields: false),
      );

      final track = tester.widget<HomeCourseTrack>(
        find.byType(HomeCourseTrack),
      );
      expect(
        track.runners,
        hasLength(15),
        reason: 'the hero render cap has no backend dependency',
      );
      // acceptedCount is absent, so the count degrades to the array length.
      expect(find.text('40'), findsWidgets);
      expect(find.text('+25 more'), findsOneWidget);
    });

    testWidgets('a small race renders every row with no "+N more"', (
      tester,
    ) async {
      await _pump(tester, _PagedPendingApi(acceptedCount: 4, pageSize: 4));

      final track = tester.widget<HomeCourseTrack>(
        find.byType(HomeCourseTrack),
      );
      expect(track.runners, hasLength(4));
      expect(find.textContaining('more'), findsNothing);
      expect(find.text('4'), findsWidgets);
    });
  });

  group('the viewer is not in the page', () {
    testWidgets('leaderboard view records only when standings reach viewport', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final analytics = _RecordingActivationAnalytics();
      const raceId = '0198c82f-0011-7000-8000-000000000001';
      await _pump(
        tester,
        _PagedActiveApi(),
        raceId: raceId,
        activationAnalyticsService: analytics,
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(analytics.leaderboardViews, isEmpty);
      await tester.ensureVisible(find.text('STANDINGS').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(analytics.leaderboardViews, [
        const {'race_id': raceId},
      ]);

      // Leaving and deliberately returning is a second view, while rebuilds
      // that keep the board visible must not duplicate one interaction.
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, 1000),
      );
      await tester.pump();
      await tester.ensureVisible(find.text('STANDINGS').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(analytics.leaderboardViews, [
        const {'race_id': raceId},
        const {'race_id': raceId},
      ]);

      final raceContext = tester.element(find.byType(RaceDetailScreen));
      unawaited(
        Navigator.of(raceContext).push<void>(
          MaterialPageRoute<void>(builder: (_) => const SizedBox.expand()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(analytics.leaderboardViews, hasLength(2));
      Navigator.of(raceContext).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(analytics.leaderboardViews, hasLength(3));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(analytics.leaderboardViews, hasLength(3));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(analytics.leaderboardViews, [
        const {'race_id': raceId},
        const {'race_id': raceId},
        const {'race_id': raceId},
        const {'race_id': raceId},
      ]);
    });

    testWidgets('an off-page participant is NOT shown as a spectator', (
      tester,
    ) async {
      await _pump(tester, _PagedActiveApi());
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('SPECTATING · READ-ONLY'), findsNothing);
    });

    testWidgets('the stamped FORFEIT action survives an off-page row', (
      tester,
    ) async {
      await _pump(tester, _PagedActiveApi());
      await tester.pump(const Duration(milliseconds: 50));

      // `leaveAction: FORFEIT` on an ACTIVE race the viewer is ACCEPTED in must
      // still be offered even though their own row is off-page — the old
      // membership re-scan silently withheld it.
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('FORFEIT RACE'), findsOneWidget);
    });

    testWidgets('_myLobbyTeam seats the viewer from myTeam, not the page', (
      tester,
    ) async {
      final api = _PagedTeamApi();
      await _pump(tester, api);

      expect(find.byType(TeamLobbyBoard), findsOneWidget);
      // The viewer is already on TEAM_B per `myTeam`; tapping an empty TEAM_B
      // peg must be a no-op. Scanning the (1-row) page would report "no team"
      // and fire a pointless side-switch.
      final peg = find.byKey(const Key('lobby-empty-B-0'));
      await tester.ensureVisible(peg);
      await tester.tap(peg);
      // Not pumpAndSettle: the lobby's idle capy animation never settles.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(api.switchedTo, isNull);
    });
  });

  group('team summary counts', () {
    testWidgets('the start lever arms from teamA/teamBAcceptedCount', (
      tester,
    ) async {
      await _pump(tester, _PagedTeamApi());

      final startFinder = find.widgetWithText(PillButton, 'START RACE');
      await tester.ensureVisible(startFinder);
      final button = tester.widget<PillButton>(startFinder);
      expect(
        button.onPressed,
        isNotNull,
        reason: '2v2 per the summary counts, even though the page holds 1 row',
      );
      expect(find.textContaining('Teams must be even'), findsNothing);
    });

    testWidgets('_bothSidesFull blocks a surplus invitee from the page', (
      tester,
    ) async {
      await _pump(tester, _PagedTeamApi(myStatus: 'INVITED', myTeam: null));

      expect(find.textContaining('Both teams are full'), findsOneWidget);
    });
  });

  group('_inviteMore', () {
    testWidgets('does not re-offer a friend who is off-page', (tester) async {
      await _pump(
        tester,
        _PagedPendingApi(),
        friends: const [
          {'id': 'friend-2', 'displayName': 'Off Page Friend'},
          {'id': 'friend-9', 'displayName': 'Invitable Friend'},
        ],
      );

      final inviteFinder = find.widgetWithText(PillButton, 'INVITE FRIENDS');
      await tester.ensureVisible(inviteFinder);
      await tester.tap(inviteFinder);
      await tester.pumpAndSettle();

      final invite = tester.widget<RaceInviteScreen>(
        find.byType(RaceInviteScreen),
      );
      expect(invite.existingParticipantIds, contains('friend-2'));
      expect(invite.existingParticipantIds, isNot(contains('friend-9')));
    });

    testWidgets('falls back to the array when participantUserIds is absent', (
      tester,
    ) async {
      await _pump(
        tester,
        _PagedPendingApi(includeParticipantUserIds: false),
        friends: const [
          {'id': 'u3', 'displayName': 'On Page Friend'},
        ],
      );

      final inviteFinder = find.widgetWithText(PillButton, 'INVITE FRIENDS');
      await tester.ensureVisible(inviteFinder);
      await tester.tap(inviteFinder);
      await tester.pumpAndSettle();

      final invite = tester.widget<RaceInviteScreen>(
        find.byType(RaceInviteScreen),
      );
      expect(invite.existingParticipantIds, contains('u3'));
    });
  });

  group('EditRaceScreen counts', () {
    testWidgets('uses the counts passed in, not a re-derived array scan', (
      tester,
    ) async {
      final authService = await _createAuthService();
      await tester.pumpWidget(
        MaterialApp(
          home: EditRaceScreen(
            authService: authService,
            raceId: 'race-paged',
            backendApiService: BackendApiService(),
            acceptedCount: 473,
            race: {
              'id': 'race-paged',
              'name': 'Weekly Challenge',
              'status': 'PENDING',
              'maxDurationDays': 7,
              'buyInAmount': 0,
              'payoutPreset': 'WINNER_TAKES_ALL',
              'participants': [
                for (var i = 0; i < 15; i++) _participant('u$i'),
              ],
              'acceptedCount': 473,
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('473 runners already accepted'),
        findsOneWidget,
      );
    });
  });

  group('pure consumers', () {
    test('RacePayoutPresentation.fromRace prefers acceptedCount', () {
      final presentation = RacePayoutPresentation.fromRace({
        'maxDurationDays': 7,
        'buyInAmount': 10,
        'projectedPotCoins': 4730,
        'payoutPreset': 'WINNER_TAKES_ALL',
        'participants': [for (var i = 0; i < 15; i++) _participant('u$i')],
        'acceptedCount': 473,
      });
      expect(presentation.acceptedCount, 473);
    });

    test(
      'RacePayoutPresentation.fromRace still counts the array when absent',
      () {
        final presentation = RacePayoutPresentation.fromRace({
          'maxDurationDays': 7,
          'buyInAmount': 10,
          'participants': [for (var i = 0; i < 3; i++) _participant('u$i')],
        });
        expect(presentation.acceptedCount, 3);
      },
    );

    test('TeamRace.sideCounts prefers the summary counts over the page', () {
      final counts = TeamRace.sideCounts({
        'isTeamRace': true,
        'teamSize': 3,
        'participants': [_participant('u9', team: 'TEAM_A')],
        'teamAAcceptedCount': 3,
        'teamBAcceptedCount': 2,
      });
      expect(counts, (3, 2));
    });

    test('TeamRace.sideCounts keeps the teams block as first preference', () {
      final counts = TeamRace.sideCounts({
        'isTeamRace': true,
        'teams': const {
          'teamA': {'memberCount': 4},
          'teamB': {'memberCount': 4},
        },
        'teamAAcceptedCount': 1,
        'teamBAcceptedCount': 1,
      });
      expect(counts, (4, 4));
    });

    test('TeamRace.sideCounts still falls back to the array', () {
      final counts = TeamRace.sideCounts({
        'isTeamRace': true,
        'participants': [
          _participant('u1', team: 'TEAM_A'),
          _participant('u2', team: 'TEAM_B'),
          _participant('u3', team: 'TEAM_B'),
        ],
      });
      expect(counts, (1, 2));
    });
  });
}
