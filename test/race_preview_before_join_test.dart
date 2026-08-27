import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/team_lobby_board.dart';

/// Race preview-before-joining (spec: docs/race-preview-before-join-spec.md,
/// "Frontend change — extend `_isSpectator`").
///
/// A non-participant on a build advertising the `race_preview` capability token
/// now receives a 200 (instead of a 403) for a PUBLIC, NON-TOURNAMENT race:
/// `myStatus` is null, every participant's financial field is redacted to null,
/// and `participantsPagination` is present. The screen must render that as the
/// EXISTING `_isSpectator` read-only mode plus a JOIN CTA — never as a second
/// parallel "preview" state — and must not touch chat, the activity feed, the
/// share-link endpoint, or the 30s progress poll while in it.

const _pagination = {'total': 2, 'offset': 0, 'limit': 10, 'hasMore': false};

/// Financial fields are REDACTED (explicit nulls) for a preview viewer — the
/// screen must not print "null" or crash on any of them.
const _previewParticipants = [
  {
    'userId': 'u1',
    'displayName': 'Runner One',
    'status': 'ACCEPTED',
    'buyInAmount': null,
    'buyInStatus': null,
    'payoutCoins': null,
  },
  {
    'userId': 'u2',
    'displayName': 'Runner Two',
    'status': 'ACCEPTED',
    'buyInAmount': null,
    'buyInStatus': null,
    'payoutCoins': null,
  },
];

class _PreviewApi extends BackendApiService {
  _PreviewApi({
    this.status = 'ACTIVE',
    this.isPublic = true,
    this.tournamentId,
    this.isTeamRace = false,
    this.participants = _previewParticipants,
    this.detailsStatusCode,
    this.fundedPool = false,
  });

  final String status;
  final bool isPublic;
  final String? tournamentId;
  final bool isTeamRace;
  final List<Map<String, dynamic>> participants;

  /// When set, `fetchRaceDetails` throws with this status (the unchanged 403
  /// path).
  final int? detailsStatusCode;
  final bool fundedPool;

  int detailsCalls = 0;
  int progressCalls = 0;
  int feedOrChatCalls = 0;
  int shareLinkCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async {
    detailsCalls += 1;
    final code = detailsStatusCode;
    if (code != null) {
      throw ApiException(
        'You are not a participant in this race',
        statusCode: code,
      );
    }
    return {
      'id': raceId,
      'name': 'Public Sprint',
      'status': status,
      'isTeamRace': isTeamRace,
      if (isTeamRace) 'teamSize': 2,
      if (isTeamRace) 'teamAName': 'Reds',
      if (isTeamRace) 'teamBName': 'Blues',
      'maxDurationDays': 1,
      'buyInAmount': 0,
      'potCoins': 0,
      'heldPotCoins': 0,
      'projectedPotCoins': 240,
      if (fundedPool)
        'prizePool': const {
          'coins': 240,
          'projected': true,
          'atMax': false,
          'playerCount': 2,
          'durationDays': 1,
          'durationPoints': 1,
          'coinUnit': 20,
          'maxCoins': 3200,
          'funded': true,
        },
      if (fundedPool)
        'payoutTiers': const [
          {'placement': 1, 'amount': 168},
          {'placement': 2, 'amount': 72},
        ],
      'payoutPreset': 'TOP3_70_20_10',
      'targetSteps': 20000,
      // The preview contract: no participant row of my own.
      'myStatus': null,
      'myTeam': null,
      'myTotalSteps': null,
      'leaveAction': null,
      'isCreator': false,
      'isPublic': isPublic,
      'tournamentId': tournamentId,
      if (tournamentId != null) 'tournamentName': 'Daily Dash',
      if (tournamentId != null) 'tournamentRoundLabel': 'SEMIFINALS',
      'powerupsEnabled': true,
      'endsAt': '2126-04-10T12:00:00.000Z',
      'participants': participants,
      // Present whenever the backend honoured the paging capability — the
      // signal `_isSpectator` needs to trust `myStatus` over an array scan.
      'participantsPagination': {..._pagination, 'total': participants.length},
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async {
    progressCalls += 1;
    return {
      'status': status,
      'participants': [
        for (final p in participants)
          {
            'userId': p['userId'],
            'displayName': p['displayName'],
            'totalSteps': 5000.0,
            'finishedAt': null,
          },
      ],
      // NOTE: on /progress the key is `pagination`, not `participantsPagination`.
      'pagination': {..._pagination, 'total': participants.length},
      'powerupData': const {
        'enabled': true,
        'inventory': [],
        'powerupSlots': 3,
        'queuedBoxCount': 0,
        'activeEffects': [],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaceMessages({
    required String identityToken,
    required String raceId,
    String? cursor,
    int? limit,
    String? kind,
  }) async {
    feedOrChatCalls += 1;
    return const {'messages': [], 'events': []};
  }

  @override
  Future<Map<String, dynamic>> fetchRaceFeed({
    String? cursor,
    required String identityToken,
    required String raceId,
  }) async {
    feedOrChatCalls += 1;
    return const {'events': []};
  }

  @override
  Future<RaceMessageStreamsResult> fetchRaceMessageStreams({
    required String identityToken,
    required String raceId,
    required bool includeUser,
    int limit = 30,
  }) async {
    feedOrChatCalls += 1;
    return RaceMessageStreamsResult.unsupported;
  }

  @override
  Future<Map<String, dynamic>> createRaceShareLink({
    required String identityToken,
    required String raceId,
  }) async {
    shareLinkCalls += 1;
    return const {'url': 'https://example.invalid/r/abc'};
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async =>
      const {'coins': 500, 'heldCoins': 0};
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'token',
    'auth_user_identifier': 'user',
    'auth_session_token': 'session',
    'auth_backend_user_id': 'me',
    'auth_display_name': 'Bara',
    'auth_coins': 500,
    'auth_held_coins': 0,
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Future<void> _pump(
  WidgetTester tester,
  BackendApiService api, {
  double width = 600,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 3000), textScaler: textScaler),
        child: RaceDetailScreen(
          authService: await _auth(),
          raceId: 'race-public-1',
          backendApiService: api,
        ),
      ),
    ),
  );
  // Bounded pumps: hero art animates forever.
  await tester.pump();
  await tester.pump();
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('clientFeaturesHeader advertises race_preview in BOTH branches', () {
    expect(
      BackendApiService.clientFeaturesHeader.split(','),
      contains('race_preview'),
    );
    // The token list is duplicated across the _adsSupported ternary; a build
    // with ads compiled out must still get the preview carve-out.
    final source = File(
      'lib/services/backend_api_service.dart',
    ).readAsStringSync();
    final start = source.indexOf('clientFeaturesHeader = _adsSupported');
    final end = source.indexOf('/// Replays a persisted results dismissal');
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    expect(
      RegExp('race_preview').allMatches(source.substring(start, end)),
      hasLength(2),
    );
  });

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.bara.app',
      version: '2.3.6',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets(
    'ACTIVE public preview renders the race read-only with a JOIN CTA',
    (tester) async {
      final api = _PreviewApi();
      await _pump(tester, api);

      // The race itself renders — this is a preview, not an error state.
      expect(find.byKey(const Key('race-not-a-participant')), findsNothing);
      expect(find.text('Public Sprint'), findsWidgets);
      expect(find.text('STANDINGS'), findsOneWidget);
      expect(find.textContaining('Runner One'), findsWidgets);

      // Existing spectator chrome — extended, not replaced.
      expect(find.text('SPECTATING · READ-ONLY'), findsOneWidget);
      expect(find.byKey(const Key('race-preview-join-cta')), findsOneWidget);

      // The preview state is a compact conversion rail, not another tall card
      // between the payout summary and standings.
      final spectatorRail = tester.getSize(
        find.byKey(const Key('race-spectator-banner')),
      );
      expect(spectatorRail.height, lessThanOrEqualTo(64));
      expect(
        tester.getSize(find.byKey(const Key('race-preview-join-cta'))).height,
        greaterThanOrEqualTo(44),
      );

      // Write surfaces stay hidden.
      expect(find.text('POWERUPS'), findsNothing);
      expect(find.byIcon(Icons.ios_share), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsNothing);

      // Chat/activity are locked rather than fetched.
      expect(
        find.byKey(const Key('race-preview-locked-activity')),
        findsOneWidget,
      );
      expect(api.feedOrChatCalls, 0);
      expect(api.shareLinkCalls, 0);

      // Redacted financial fields never surface as a "null" literal.
      expect(find.text('null'), findsNothing);
      expect(tester.takeException(), isNull);

      await _teardown(tester);
    },
  );

  testWidgets(
    'preview mode fires no chat/feed calls and never polls progress',
    (tester) async {
      final api = _PreviewApi();
      await _pump(tester, api);

      expect(api.progressCalls, 1, reason: 'single fetch, no poll');
      expect(api.feedOrChatCalls, 0);

      // Well past several 30s poll intervals.
      await tester.pump(const Duration(seconds: 120));
      await tester.pump();

      expect(api.progressCalls, 1, reason: '_startPolling must not run');
      expect(api.feedOrChatCalls, 0);

      // Switching to the CHAT tab must not initialise the chat stream either.
      await tester.tap(find.text('CHAT'));
      await tester.pump();
      expect(find.byKey(const Key('race-preview-locked-chat')), findsOneWidget);
      expect(api.feedOrChatCalls, 0);
      expect(tester.takeException(), isNull);

      await _teardown(tester);
    },
  );

  testWidgets('390pt preview keeps the spectator rail compact', (tester) async {
    await _pump(tester, _PreviewApi(), width: 390);

    expect(
      tester.getSize(find.byKey(const Key('race-spectator-banner'))).height,
      lessThanOrEqualTo(64),
    );
    expect(tester.takeException(), isNull);
    await _teardown(tester);
  });

  testWidgets('narrow top-right payout chip opens its detail sheet', (
    tester,
  ) async {
    await _pump(
      tester,
      _PreviewApi(fundedPool: true),
      width: 320,
      textScaler: const TextScaler.linear(1.2),
    );

    final payouts = find.byKey(const Key('race-prize-pool-board'));
    expect(payouts, findsOneWidget);
    expect(tester.getSize(payouts).height, greaterThanOrEqualTo(44));
    await tester.tap(payouts);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('race-prize-pool-sheet')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _teardown(tester);
  });

  testWidgets('a 403 still renders the unchanged not-a-participant state', (
    tester,
  ) async {
    final api = _PreviewApi(detailsStatusCode: 403);
    await _pump(tester, api);

    expect(find.byKey(const Key('race-not-a-participant')), findsOneWidget);
    expect(find.byKey(const Key('race-preview-join-cta')), findsNothing);
    expect(tester.takeException(), isNull);

    await _teardown(tester);
  });

  testWidgets(
    'a tournament matchup spectator gets the banner but NO JOIN CTA',
    (tester) async {
      // myStatus is null here too — proof the CTA is gated on
      // tournamentId == null && isPublic == true, not on myStatus.
      final api = _PreviewApi(tournamentId: 'tour-1');
      await _pump(tester, api);

      expect(find.text('SPECTATING · READ-ONLY'), findsOneWidget);
      expect(find.byKey(const Key('race-preview-join-cta')), findsNothing);
      expect(tester.takeException(), isNull);

      await _teardown(tester);
    },
  );

  testWidgets('a private race with myStatus null gets no JOIN CTA', (
    tester,
  ) async {
    final api = _PreviewApi(isPublic: false);
    await _pump(tester, api);

    expect(find.text('SPECTATING · READ-ONLY'), findsOneWidget);
    expect(find.byKey(const Key('race-preview-join-cta')), findsNothing);
    expect(tester.takeException(), isNull);

    await _teardown(tester);
  });

  testWidgets('a PENDING team race previews read-only — no team-side picker', (
    tester,
  ) async {
    final api = _PreviewApi(
      status: 'PENDING',
      isTeamRace: true,
      participants: const [
        {
          'userId': 'u1',
          'displayName': 'Runner One',
          'status': 'ACCEPTED',
          'team': 'TEAM_A',
          'buyInAmount': null,
          'buyInStatus': null,
          'payoutCoins': null,
        },
        {
          'userId': 'u2',
          'displayName': 'Runner Two',
          'status': 'ACCEPTED',
          'team': 'TEAM_B',
          'buyInAmount': null,
          'buyInStatus': null,
          'payoutCoins': null,
        },
      ],
    );
    await _pump(tester, api);

    // The lobby board renders (the team split is visible)…
    final board = tester.widget<TeamLobbyBoard>(find.byType(TeamLobbyBoard));
    // …but its empty pegs are inert: joining a side happens inside the JOIN
    // flow's team-side picker, not by tapping the board.
    expect(board.onTapEmptySlot, isNull);

    expect(find.byKey(const Key('race-preview-join-cta')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _teardown(tester);
  });

  testWidgets('a zero-participant public race still previews with a JOIN CTA', (
    tester,
  ) async {
    // The unpaged `_isSpectator` branch returns false on an empty array, so
    // this only works if `participantsPagination` is read and the paged
    // `myStatus == null` branch wins.
    final api = _PreviewApi(status: 'PENDING', participants: const []);
    await _pump(tester, api);

    expect(find.text('SPECTATING · READ-ONLY'), findsOneWidget);
    expect(find.byKey(const Key('race-preview-join-cta')), findsOneWidget);
    expect(find.byIcon(Icons.ios_share), findsNothing);
    expect(find.byIcon(Icons.more_vert), findsNothing);
    expect(tester.takeException(), isNull);

    await _teardown(tester);
  });
}
