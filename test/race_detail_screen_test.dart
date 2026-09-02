import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/app_route_observer.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/home_course_track.dart';

class _FakeBackendApiService extends BackendApiService {
  int respondCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async {
    return {
      'id': raceId,
      'name': 'Paid Race',
      'status': 'PENDING',
      'targetSteps': 100000,
      'maxDurationDays': 7,
      // App-funded prize pool (contract §5.1): free to enter, so accepting an
      // invite is a single tap with nothing held and nothing to confirm.
      'buyInAmount': 0,
      'payoutPreset': 'WINNER_TAKES_ALL',
      'potCoins': 0,
      'heldPotCoins': 0,
      'projectedPotCoins': 100,
      'prizePool': const {
        'coins': 100,
        'projected': true,
        'atMax': false,
        'playerCount': 2,
        'durationDays': 7,
        'durationPoints': 4,
        'coinUnit': 20,
        'maxCoins': 3200,
        'funded': true,
      },
      'payouts': {'first': 100, 'second': 0, 'third': 0},
      'myStatus': 'INVITED',
      'isCreator': false,
      'participants': const [
        {
          'userId': 'creator-1',
          'displayName': 'RaceMaker',
          'status': 'ACCEPTED',
        },
        {
          'userId': 'user-1',
          'displayName': 'Trail Walker',
          'status': 'INVITED',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> respondToRaceInvite({
    required String identityToken,
    required String raceId,
    required bool accept,
  }) async {
    respondCalls += 1;
    return {
      'participant': {'id': 'rp-1', 'status': accept ? 'ACCEPTED' : 'DECLINED'},
    };
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    return const {'coins': 320, 'heldCoins': 100};
  }
}

class _ActivePaidRaceBackendApiService extends BackendApiService {
  _ActivePaidRaceBackendApiService({
    this.numericValuesAsDouble = false,
    this.powerupData = const {
      'enabled': false,
      'inventory': [],
      'powerupSlots': 3,
      'queuedBoxCount': 0,
      'activeEffects': [],
    },
  });

  final bool numericValuesAsDouble;
  Map<String, dynamic> powerupData;

  num _number(int value) {
    return numericValuesAsDouble ? value.toDouble() : value;
  }

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async {
    return {
      'id': raceId,
      'name': 'Gold Sprint',
      'status': 'ACTIVE',
      'targetSteps': _number(100000),
      'maxDurationDays': _number(7),
      'buyInAmount': _number(100),
      'payoutPreset': 'TOP3_70_20_10',
      'potCoins': _number(600),
      'heldPotCoins': _number(0),
      'projectedPotCoins': _number(600),
      'payouts': {
        'first': _number(420),
        'second': _number(120),
        'third': _number(60),
      },
      'myStatus': 'ACCEPTED',
      'isCreator': true,
      'isPublic': true,
      'creationSource': 'QUICK_CREATE',
      'startPolicy': 'ON_MINIMUM_PARTICIPANTS',
      'powerupsEnabled': false,
      'endsAt': '2026-04-10T12:00:00.000Z',
      'participants': const [
        {
          'userId': 'user-1',
          'displayName': 'Trail Walker',
          'status': 'ACCEPTED',
        },
        {
          'userId': 'user-2',
          'displayName': 'Hill Climber',
          'status': 'ACCEPTED',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async {
    return {
      'status': 'ACTIVE',
      'participants': const [
        {
          'userId': 'user-1',
          'displayName': 'Trail Walker',
          'totalSteps': 42000.0,
          'finishedAt': null,
        },
        {
          'userId': 'user-2',
          'displayName': 'Hill Climber',
          'totalSteps': 38000.0,
          'finishedAt': null,
        },
      ],
      'powerupData': powerupData,
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaceFeed({
    String? cursor,
    required String identityToken,
    required String raceId,
  }) async {
    return const {'events': []};
  }
}

class _PendingAcceptedRaceBackendApiService extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async {
    return {
      'id': raceId,
      'name': 'Test Race Wagers',
      'status': 'PENDING',
      'targetSteps': 40000,
      'maxDurationDays': 5,
      'buyInAmount': 100,
      'payoutPreset': 'TOP3_70_20_10',
      'potCoins': 300,
      'heldPotCoins': 300,
      'projectedPotCoins': 300,
      'payouts': {'first': 210, 'second': 60, 'third': 30},
      'myStatus': 'ACCEPTED',
      'isCreator': true,
      'isPublic': true,
      'creationSource': 'QUICK_CREATE',
      'startPolicy': 'ON_MINIMUM_PARTICIPANTS',
      'participants': const [
        {'userId': 'user-2', 'displayName': 'Sugaroro', 'status': 'ACCEPTED'},
        {'userId': 'user-3', 'displayName': 'emersonz', 'status': 'INVITED'},
        {
          'userId': 'user-1',
          'displayName': 'Trail Walker',
          'status': 'ACCEPTED',
        },
      ],
    };
  }
}

class _SlowProgressRaceBackendApiService
    extends _ActivePaidRaceBackendApiService {
  final Completer<Map<String, dynamic>> progressCompleter =
      Completer<Map<String, dynamic>>();

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) {
    return progressCompleter.future;
  }
}

class _FailingProgressRaceBackendApiService
    extends _ActivePaidRaceBackendApiService {
  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async {
    throw const ApiException('Connection timed out.');
  }
}

/// Fails the details fetch once (simulating a dropped connection on first
/// load), then succeeds on every call after — so a retry (pull-to-refresh)
/// is what recovers the screen, not a second automatic attempt.
class _FailsOnceThenLoadsRaceApi extends _ActivePaidRaceBackendApiService {
  int detailCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async {
    detailCalls++;
    if (detailCalls == 1) {
      throw const ApiException('Connection timed out.');
    }
    return super.fetchRaceDetails(identityToken: identityToken, raceId: raceId);
  }
}

/// Never resolves fetchRaceDetails until the test completes it — lets a test
/// fire two retry entry points (button + pull) while the first fetch is
/// still in flight and assert only one request actually went out.
class _SlowDetailsRaceApi extends _ActivePaidRaceBackendApiService {
  int detailCalls = 0;
  final Completer<Map<String, dynamic>> detailsCompleter =
      Completer<Map<String, dynamic>>();

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async {
    detailCalls++;
    // Fail fast the first time so the test can reach the failed-load panel
    // and its TRY AGAIN button; every retry after that hangs on the shared
    // completer so the test can assert only one of them is truly in flight.
    if (detailCalls == 1) {
      throw const ApiException('Connection timed out.');
    }
    return detailsCompleter.future;
  }
}

/// Fails every call with a distinct, identifiable message so a test can
/// confirm the failed-load panel shows the real error, not a generic one.
class _AlwaysFailsWithMessageRaceApi extends _ActivePaidRaceBackendApiService {
  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async {
    throw const ApiException('Race server is on a coffee break.');
  }
}

class _CompactRaceRequestApi extends BackendApiService {
  _CompactRaceRequestApi({
    this.bootstrapCompleter,
    this.bootstrapSupported = true,
    this.malformedStreams = false,
    this.streamError = false,
    this.streamsUnsupported = false,
    this.raceStatus = 'ACTIVE',
    this.streamCompleter,
    this.legacyMessagesCompleter,
    this.progressCompleter,
    this.systemMessages = const [],
    this.bootstrapOmitsProgress = false,
  });

  final Completer<RaceBootstrapResult>? bootstrapCompleter;
  final bool bootstrapSupported;
  final bool malformedStreams;
  final bool streamError;
  final bool streamsUnsupported;
  final String raceStatus;
  final Completer<RaceMessageStreamsResult>? streamCompleter;
  final Completer<Map<String, dynamic>>? legacyMessagesCompleter;
  final Completer<RaceProgressResult>? progressCompleter;
  final List<Map<String, dynamic>> systemMessages;
  final bool bootstrapOmitsProgress;
  int bootstrapCalls = 0;
  int legacyDetailsCalls = 0;
  int legacyProgressCalls = 0;
  int participantsProgressCalls = 0;
  int readAcks = 0;
  int legacyMessageCalls = 0;
  final List<bool> streamCalls = [];

  Map<String, dynamic> get _race => {
    'id': 'race-compact',
    'name': 'Compact Sprint',
    'status': raceStatus,
    'targetSteps': 10000,
    'maxDurationDays': 1,
    'buyInAmount': 0,
    'payoutPreset': 'WINNER_TAKES_ALL',
    'myStatus': 'ACCEPTED',
    'isCreator': false,
    'powerupsEnabled': false,
    'endsAt': '2026-08-20T12:00:00.000Z',
    'participants': const [
      {'userId': 'user-1', 'displayName': 'Trail Walker', 'status': 'ACCEPTED'},
    ],
  };

  Map<String, dynamic> get _progress => {
    'status': raceStatus,
    'participants': const [
      {'userId': 'user-1', 'displayName': 'Trail Walker', 'totalSteps': 1200},
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
  Future<RaceBootstrapResult> fetchRaceBootstrap({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async {
    bootstrapCalls += 1;
    final pending = bootstrapCompleter;
    if (pending != null) return pending.future;
    if (!bootstrapSupported) return RaceBootstrapResult.unsupported;
    return RaceBootstrapResult(
      supported: true,
      race: _race,
      progress: bootstrapOmitsProgress ? null : _progress,
      globalPowerupInventory: const {'items': []},
    );
  }

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async {
    legacyDetailsCalls += 1;
    return _race;
  }

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async {
    legacyProgressCalls += 1;
    return _progress;
  }

  @override
  Future<RaceProgressResult> fetchRaceProgressCompact({
    required String identityToken,
    required String raceId,
  }) async {
    return RaceProgressResult(
      progress: _progress,
      globalPowerupInventory: const {'items': []},
      hasCompactInventory: true,
    );
  }

  @override
  Future<RaceProgressResult> fetchRaceProgressParticipants({
    required String identityToken,
    required String raceId,
    int offset = 0,
    int limit = 10,
  }) async {
    participantsProgressCalls += 1;
    final pending = progressCompleter;
    if (pending != null && !pending.isCompleted) return pending.future;
    return RaceProgressResult(
      progress: _progress,
      globalPowerupInventory: const {'items': []},
      hasCompactInventory: true,
    );
  }

  @override
  Future<RaceMessageStreamsResult> fetchRaceMessageStreams({
    required String identityToken,
    required String raceId,
    required bool includeUser,
    int limit = 50,
  }) async {
    streamCalls.add(includeUser);
    final pending = streamCompleter;
    if (pending != null && !pending.isCompleted) return pending.future;
    if (streamsUnsupported) return RaceMessageStreamsResult.unsupported;
    if (streamError) throw const ApiException('Connection timed out.');
    if (malformedStreams) return RaceMessageStreamsResult.malformedResult;
    return RaceMessageStreamsResult(
      supported: true,
      systemResolved: true,
      systemStream: {'messages': systemMessages, 'nextCursor': null},
      userResolved: includeUser,
      userStream: includeUser
          ? const {'messages': [], 'nextCursor': null}
          : null,
      chatWatermark: const {'recentIds': <String>[]},
    );
  }

  @override
  Future<Map<String, dynamic>> fetchRaceMessages({
    required String identityToken,
    required String raceId,
    String? cursor,
    int? limit,
    String? kind,
  }) async {
    legacyMessageCalls += 1;
    final pending = legacyMessagesCompleter;
    if (pending != null && !pending.isCompleted) return pending.future;
    return const {'messages': [], 'nextCursor': null};
  }

  @override
  Future<Map<String, dynamic>> markRaceChatRead({
    required String identityToken,
    required String raceId,
  }) async {
    readAcks += 1;
    return const {};
  }

  @override
  Future<Map<String, dynamic>> fetchPowerupInventory({
    required String identityToken,
  }) async => const {'items': []};
}

// A field-scaled preset (top half) that pays five places, so the detail card
// shows the podium inline plus a "+2 MORE" affordance backed by payoutTiers.
class _FieldScaledPayoutRaceBackendApiService
    extends _ActivePaidRaceBackendApiService {
  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async {
    final base = await super.fetchRaceDetails(
      identityToken: identityToken,
      raceId: raceId,
    );
    base['payoutPreset'] = 'TOP_HALF';
    base['payoutTiers'] = const [
      {'placement': 1, 'amount': 300},
      {'placement': 2, 'amount': 150},
      {'placement': 3, 'amount': 90},
      {'placement': 4, 'amount': 40},
      {'placement': 5, 'amount': 20},
    ];
    return base;
  }
}

class _FinishRewardRaceBackendApiService
    extends _ActivePaidRaceBackendApiService {
  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async {
    final race = await super.fetchRaceDetails(
      identityToken: identityToken,
      raceId: raceId,
    );
    race['finishReward'] = const {'pool': 300, 'paidPlaces': 7};
    return race;
  }
}

class _TimelineRaceApi extends _ActivePaidRaceBackendApiService {
  _TimelineRaceApi({this.capable = true, this.messages});

  final bool capable;
  final List<Map<String, dynamic>>? messages;

  @override
  Future<Map<String, dynamic>> fetchRaceTimeline({
    required String identityToken,
    required String raceId,
    String? cursor,
    int limit = 30,
  }) async => {
    if (capable) 'timelineVersion': 1,
    'messages':
        messages ??
        const [
          {
            'kind': 'USER',
            'id': 'chat-timeline',
            'createdAt': '2026-08-25T15:04:05.000Z',
            'body': 'Catch me if you can',
            'senderId': 'user-2',
            'senderName': 'Rival',
          },
          {
            'kind': 'SYSTEM',
            'id': 'event-timeline',
            'createdAt': '2026-08-25T15:03:05.000Z',
            'body': 'Rival took the lead',
            'eventType': 'LEAD_CHANGE',
            'actorUserId': 'user-2',
          },
        ],
    'nextCursor': null,
  };
}

Iterable<TextSpan> _raceDetailLeafSpans(InlineSpan span) sync* {
  if (span is! TextSpan) return;
  if (span.text != null) yield span;
  for (final child in span.children ?? const <InlineSpan>[]) {
    yield* _raceDetailLeafSpans(child);
  }
}

Color? _raceDetailSpanColor(WidgetTester tester, String text) {
  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    for (final span in _raceDetailLeafSpans(richText.text)) {
      if (span.text == text) return span.style?.color;
    }
  }
  return null;
}

class _MissingPayoutRaceApi extends _ActivePaidRaceBackendApiService {
  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async {
    final race = await super.fetchRaceDetails(
      identityToken: identityToken,
      raceId: raceId,
    );
    for (final key in const [
      'prizePool',
      'buyInAmount',
      'potCoins',
      'projectedPotCoins',
      'payouts',
      'payoutTiers',
    ]) {
      race.remove(key);
    }
    return race;
  }
}

class _PrivateLegacyShareRaceApi extends _ActivePaidRaceBackendApiService {
  int shareCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async {
    final race = await super.fetchRaceDetails(
      identityToken: identityToken,
      raceId: raceId,
    );
    race['isPublic'] = false;
    return race;
  }

  @override
  Future<Map<String, dynamic>> createRaceShareLink({
    required String identityToken,
    required String raceId,
  }) async {
    shareCalls += 1;
    return const {'url': 'https://example.invalid/r/legacy'};
  }
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

Future<AuthService> _createSignedOutAuthService() async {
  SharedPreferences.setMockInitialValues({});

  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('RaceDetailScreen stops loading without an auth token', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RaceDetailScreen(
          authService: await _createSignedOutAuthService(),
          raceId: 'race-no-token',
          backendApiService: _ActivePaidRaceBackendApiService(),
        ),
      ),
    );
    await tester.pump();

    // Missing auth can't be fixed by retrying the same request, so it gets
    // its own distinct copy and no dead TRY AGAIN button.
    expect(find.text('Signed out'), findsOneWidget);
    expect(find.text('Failed to load race'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.text('TRY AGAIN'),
      findsNothing,
      reason: 'Retrying the same request can never recover from no auth token.',
    );
  });

  testWidgets('timeline-v1 interleaves chat and activity in one surface', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: RaceDetailScreen(
          authService: await _createAuthService(),
          raceId: 'race-timeline',
          backendApiService: _TimelineRaceApi(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('race-timeline-heading')), findsOneWidget);
    expect(find.text('Catch me if you can'), findsOneWidget);
    expect(find.text('Rival took the lead'), findsOneWidget);
    expect(find.text('ACTIVITY'), findsNothing);
    expect(find.text('CHAT'), findsNothing);
    expect(
      tester.getCenter(find.text('Catch me if you can')).dy,
      greaterThan(tester.getCenter(find.text('Rival took the lead')).dy),
      reason: 'the newest timeline entry belongs nearest the composer',
    );
  });

  testWidgets('Activity applies semantic color to every named powerup', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _CompactRaceRequestApi(
      systemMessages: const [
        {
          'id': 'activity-reflected',
          'eventType': 'POWERUP_REFLECTED',
          'powerupType': 'WRONG_TURN',
          'body': "Maya's Mirror reflected Jordan's Wrong Turn.",
          'actorUserId': 'user-1',
          'createdAt': '2026-08-25T15:05:05.000Z',
        },
        {
          'id': 'activity-blocked',
          'eventType': 'POWERUP_BLOCKED',
          'powerupType': 'HITCHHIKE',
          'body':
              "Shefali's Compression Socks blocked the redirected Hitchhike.",
          'actorUserId': 'redirected-user',
          'targetUserId': 'attacker',
          'createdAt': '2026-08-25T15:03:05.001Z',
        },
        {
          'id': 'activity-redirected',
          'eventType': 'POWERUP_REDIRECTED',
          'powerupType': 'HITCHHIKE',
          'body': "Nathan's Decoy redirected Anjali's Hitchhike to Shefali.",
          'actorUserId': 'user-1',
          'targetUserId': 'redirected-user',
          'metadata': {
            'attackerUserId': 'attacker',
            'decoyOwnerUserId': 'user-1',
            'redirectedUserId': 'redirected-user',
          },
          'createdAt': '2026-08-25T15:03:05.000Z',
        },
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeData.light(),
        home: RaceDetailScreen(
          authService: await _createAuthService(),
          raceId: 'race-activity-semantics',
          backendApiService: api,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.text(
        "Nathan's Decoy redirected Anjali's Hitchhike to Shefali.",
        findRichText: true,
      ),
      findsOneWidget,
    );
    final redirectText = find.text(
      "Nathan's Decoy redirected Anjali's Hitchhike to Shefali.",
      findRichText: true,
    );
    final terminalText = find.text(
      "Shefali's Compression Socks blocked the redirected Hitchhike.",
      findRichText: true,
    );
    expect(
      tester.getCenter(redirectText).dy,
      lessThan(tester.getCenter(terminalText).dy),
    );
    expect(
      _raceDetailSpanColor(tester, 'Wrong Turn'),
      AppPalette.light.feedAttack,
    );
    for (final name in ['Mirror', 'Compression Socks', 'Decoy', 'Hitchhike']) {
      expect(
        _raceDetailSpanColor(tester, name),
        AppPalette.light.feedPositive,
        reason: name,
      );
    }
  });

  testWidgets(
    'Timeline applies semantic color to redirected and blocked rows',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const redirected =
          "Nathan's Decoy redirected Anjali's Hitchhike to Shefali.";
      const blocked =
          "Shefali's Compression Socks blocked the redirected Hitchhike.";
      final api = _TimelineRaceApi(
        messages: const [
          {
            'kind': 'SYSTEM',
            'id': 'timeline-blocked',
            'createdAt': '2026-08-25T15:03:05.001Z',
            'body': blocked,
            'eventType': 'POWERUP_BLOCKED',
            'powerupType': 'HITCHHIKE',
            'actorUserId': 'user-1',
          },
          {
            'kind': 'SYSTEM',
            'id': 'timeline-redirected',
            'createdAt': '2026-08-25T15:03:05.000Z',
            'body': redirected,
            'eventType': 'POWERUP_REDIRECTED',
            'powerupType': 'HITCHHIKE',
            'actorUserId': 'user-1',
          },
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemeData.light(),
          home: RaceDetailScreen(
            authService: await _createAuthService(),
            raceId: 'race-timeline-semantics',
            backendApiService: api,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text(redirected, findRichText: true), findsOneWidget);
      expect(find.text(blocked, findRichText: true), findsOneWidget);
      expect(
        tester.getCenter(find.text(redirected, findRichText: true)).dy,
        lessThan(tester.getCenter(find.text(blocked, findRichText: true)).dy),
      );
      for (final name in ['Decoy', 'Compression Socks', 'Hitchhike']) {
        expect(
          _raceDetailSpanColor(tester, name),
          AppPalette.light.feedPositive,
          reason: name,
        );
      }
    },
  );

  testWidgets('missing timeline marker preserves the legacy tabs', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: RaceDetailScreen(
          authService: await _createAuthService(),
          raceId: 'race-legacy-timeline',
          backendApiService: _TimelineRaceApi(capable: false),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('race-timeline-heading')), findsNothing);
    expect(find.text('ACTIVITY'), findsOneWidget);
    expect(find.text('CHAT'), findsOneWidget);
  });

  testWidgets('active race keeps an observable payout unavailable state', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: RaceDetailScreen(
          authService: await _createAuthService(),
          raceId: 'race-missing-payout',
          backendApiService: _MissingPayoutRaceApi(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('race-payout-section')), findsNothing);
    expect(find.byKey(const Key('race-payout-unavailable')), findsNothing);
    expect(find.text('UNAVAILABLE'), findsNothing);
  });

  testWidgets(
    'private share refuses a response without strict approval marker',
    (tester) async {
      final api = _PrivateLegacyShareRaceApi();
      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: await _createAuthService(),
            raceId: 'race-private-legacy',
            backendApiService: api,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byIcon(Icons.ios_share).first);
      await tester.pump();

      expect(api.shareCalls, 1);
      expect(
        find.text('Update required to share this private race'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'pull-to-refresh recovers the failed-to-load state after a network error',
    (WidgetTester tester) async {
      final api = _FailsOnceThenLoadsRaceApi();
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [appRouteObserver],
          home: RaceDetailScreen(
            authService: await _createAuthService(),
            raceId: 'race-flaky-1',
            backendApiService: api,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Failed to load race'), findsOneWidget);
      expect(api.detailCalls, 1);

      // The failed state must still be a pull-to-refresh surface, not a dead
      // end — drag it down like a real pull gesture and let it settle.
      expect(find.byType(RefreshIndicator), findsOneWidget);
      await tester.fling(
        find.byType(RefreshIndicator),
        const Offset(0, 300),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      await tester.pump();

      expect(api.detailCalls, greaterThanOrEqualTo(2));
      expect(find.text('Failed to load race'), findsNothing);
      expect(find.text('Gold Sprint'), findsOneWidget);
    },
  );

  testWidgets(
    'failed-to-load panel shows the real error instead of a generic message',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [appRouteObserver],
          home: RaceDetailScreen(
            authService: await _createAuthService(),
            raceId: 'race-flaky-2',
            backendApiService: _AlwaysFailsWithMessageRaceApi(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Failed to load race'), findsOneWidget);
      // findsWidgets, not findsOneWidget: the same message also flashes as a
      // transient error toast — this assertion is about the PERSISTED copy
      // on the panel outliving that toast, not about there being exactly one
      // widget with this text on screen.
      expect(find.text('Race server is on a coffee break.'), findsWidgets);
      expect(find.text('Pull to retry.'), findsNothing);
    },
  );

  testWidgets(
    'TRY AGAIN and pull-to-refresh share one in-flight fetch, not two',
    (WidgetTester tester) async {
      final api = _SlowDetailsRaceApi();
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [appRouteObserver],
          home: RaceDetailScreen(
            authService: await _createAuthService(),
            raceId: 'race-slow-1',
            backendApiService: api,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Initial load fails fast, landing on the failed-load panel with its
      // TRY AGAIN button. Mash it twice in a row before the retry it starts
      // has a chance to resolve — the second tap must reuse the first
      // retry's in-flight fetch instead of starting a third request.
      expect(api.detailCalls, 1);
      expect(find.text('TRY AGAIN'), findsOneWidget);
      await tester.tap(find.text('TRY AGAIN'));
      await tester.pump();
      expect(api.detailCalls, 2);
      await tester.tap(find.text('TRY AGAIN'));
      await tester.pump();

      expect(
        api.detailCalls,
        2,
        reason:
            'A concurrent retry must reuse the in-flight fetch, not start another.',
      );

      api.detailsCompleter.complete(<String, dynamic>{
        'id': 'race-slow-1',
        'name': 'Gold Sprint',
        'status': 'ACTIVE',
        'targetSteps': 100000,
        'maxDurationDays': 7,
        'buyInAmount': 100,
        'payoutPreset': 'TOP3_70_20_10',
        'potCoins': 600,
        'heldPotCoins': 0,
        'projectedPotCoins': 600,
        'payouts': {'first': 420, 'second': 120, 'third': 60},
        'myStatus': 'ACCEPTED',
        'isCreator': false,
        'powerupsEnabled': false,
        'participants': const [
          {
            'userId': 'user-1',
            'displayName': 'Trail Walker',
            'status': 'ACCEPTED',
          },
        ],
      });
      await tester.pump();
      await tester.pump();

      expect(find.text('Gold Sprint'), findsOneWidget);
    },
  );

  testWidgets(
    'compact race waits to initialize streams until a covering route pops',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final bootstrap = Completer<RaceBootstrapResult>();
      final api = _CompactRaceRequestApi(bootstrapCompleter: bootstrap);

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [appRouteObserver],
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-compact',
            backendApiService: api,
          ),
        ),
      );
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('MODAL')),
          ),
        ),
      );
      await tester.pump();
      bootstrap.complete(
        RaceBootstrapResult(
          supported: true,
          race: api._race,
          progress: api._progress,
          globalPowerupInventory: const {'items': []},
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(api.streamCalls, isEmpty);
      navigator.pop();
      await tester.pump();
      await tester.pump();
      expect(api.streamCalls, [false]);
    },
  );

  testWidgets(
    'covered completed race performs its one stream read after route pop',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final bootstrap = Completer<RaceBootstrapResult>();
      final api = _CompactRaceRequestApi(
        bootstrapCompleter: bootstrap,
        raceStatus: 'COMPLETED',
      );

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [appRouteObserver],
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-compact',
            backendApiService: api,
          ),
        ),
      );
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('MODAL')),
          ),
        ),
      );
      await tester.pump();
      bootstrap.complete(
        RaceBootstrapResult(
          supported: true,
          race: api._race,
          progress: api._progress,
          globalPowerupInventory: const {'items': []},
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(api.streamCalls, isEmpty);
      navigator.pop();
      await tester.pump();
      await tester.pump();
      expect(api.streamCalls, [false]);
    },
  );

  testWidgets(
    'completed race loads progress omitted from its bootstrap response',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final api = _CompactRaceRequestApi(
        raceStatus: 'COMPLETED',
        bootstrapOmitsProgress: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-compact',
            backendApiService: api,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(api.bootstrapCalls, 1);
      expect(api.participantsProgressCalls, 1);
      expect(
        find.byKey(const Key('race-detail-completed-progress-error')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('race-detail-completed-progress-skeleton')),
        findsNothing,
      );
      expect(find.text('RACE COMPLETE'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'completed race retries an initial stream read discarded while covered',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final streams = Completer<RaceMessageStreamsResult>();
      final api = _CompactRaceRequestApi(
        raceStatus: 'COMPLETED',
        streamCompleter: streams,
      );

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [appRouteObserver],
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-compact',
            backendApiService: api,
          ),
        ),
      );
      await tester.pump();
      expect(api.streamCalls, [false]);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('MODAL')),
          ),
        ),
      );
      await tester.pump();
      streams.complete(
        RaceMessageStreamsResult(
          supported: true,
          systemResolved: true,
          systemStream: const {'messages': [], 'nextCursor': null},
          userResolved: false,
          chatWatermark: const {'recentIds': <String>[]},
        ),
      );
      await tester.pump();

      navigator.pop();
      await tester.pump();
      await tester.pump();
      expect(api.streamCalls, [false, false]);
      expect(api.readAcks, 1);
    },
  );

  testWidgets(
    'discarded initial stream retains malformed retry semantics after pop',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final streams = Completer<RaceMessageStreamsResult>();
      final api = _CompactRaceRequestApi(
        streamCompleter: streams,
        malformedStreams: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [appRouteObserver],
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-compact',
            backendApiService: api,
          ),
        ),
      );
      await tester.pump();
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('MODAL')),
          ),
        ),
      );
      await tester.pump();
      streams.complete(
        RaceMessageStreamsResult(
          supported: true,
          systemResolved: true,
          systemStream: const {'messages': [], 'nextCursor': null},
          userResolved: false,
          chatWatermark: const {'recentIds': <String>[]},
        ),
      );
      await tester.pump();
      navigator.pop();
      await tester.pump();
      await tester.pump();

      expect(find.text('Couldn’t load activity'), findsOneWidget);
      expect(find.text('TRY AGAIN'), findsOneWidget);
      expect(api.readAcks, 1);
    },
  );

  testWidgets(
    'discarded initial stream retains transport retry semantics after pop',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final streams = Completer<RaceMessageStreamsResult>();
      final api = _CompactRaceRequestApi(
        streamCompleter: streams,
        streamError: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [appRouteObserver],
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-compact',
            backendApiService: api,
          ),
        ),
      );
      await tester.pump();
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('MODAL')),
          ),
        ),
      );
      await tester.pump();
      streams.complete(
        RaceMessageStreamsResult(
          supported: true,
          systemResolved: true,
          systemStream: const {'messages': [], 'nextCursor': null},
          userResolved: false,
          chatWatermark: const {'recentIds': <String>[]},
        ),
      );
      await tester.pump();
      navigator.pop();
      await tester.pump();
      await tester.pump();

      expect(find.text('Couldn’t load activity'), findsOneWidget);
      expect(find.text('TRY AGAIN'), findsOneWidget);
      expect(api.readAcks, 1);
    },
  );

  testWidgets(
    'covered legacy fallback acknowledges initial Chat read after pop',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final legacyMessages = Completer<Map<String, dynamic>>();
      final api = _CompactRaceRequestApi(
        streamsUnsupported: true,
        legacyMessagesCompleter: legacyMessages,
      );
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [appRouteObserver],
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-compact',
            backendApiService: api,
          ),
        ),
      );
      await tester.pump();
      expect(api.legacyMessageCalls, 2);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('MODAL')),
          ),
        ),
      );
      await tester.pump();
      legacyMessages.complete(const {'messages': [], 'nextCursor': null});
      await tester.pump();
      expect(api.readAcks, 0);

      navigator.pop();
      await tester.pump();
      await tester.pump();

      expect(api.legacyMessageCalls, 4);
      expect(api.readAcks, 1);
    },
  );

  testWidgets(
    'return refresh does not resume streams if another route covers it',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final progress = Completer<RaceProgressResult>();
      final api = _CompactRaceRequestApi(progressCompleter: progress);

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [appRouteObserver],
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-compact',
            backendApiService: api,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(api.streamCalls, [false]);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('FIRST MODAL')),
          ),
        ),
      );
      await tester.pump();
      navigator.pop();
      await tester.pump();

      unawaited(
        navigator.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('SECOND MODAL')),
          ),
        ),
      );
      await tester.pump();
      progress.complete(
        RaceProgressResult(
          progress: api._progress,
          globalPowerupInventory: const {'items': []},
          hasCompactInventory: true,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));

      expect(api.streamCalls, [false]);
    },
  );

  testWidgets(
    'malformed initial message streams leave Activity in retry state',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final api = _CompactRaceRequestApi(malformedStreams: true);
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [appRouteObserver],
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-compact',
            backendApiService: api,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Couldn’t load activity'), findsOneWidget);
      expect(find.text('TRY AGAIN'), findsOneWidget);
    },
  );

  testWidgets(
    'transport-failed initial streams leave Activity in retry state',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final api = _CompactRaceRequestApi(streamError: true);
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [appRouteObserver],
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-compact',
            backendApiService: api,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Couldn’t load activity'), findsOneWidget);
      expect(find.text('TRY AGAIN'), findsOneWidget);
    },
  );

  testWidgets(
    'compact bootstrap avoids legacy reads and Chat stays lazy until tapped',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final api = _CompactRaceRequestApi();
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [appRouteObserver],
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-compact',
            backendApiService: api,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(api.bootstrapCalls, 1);
      expect(api.legacyDetailsCalls, 0);
      expect(api.legacyProgressCalls, 0);
      expect(api.streamCalls, [false]);

      await tester.ensureVisible(find.text('CHAT'));
      await tester.tap(find.text('CHAT'));
      await tester.pump();
      await tester.pump();
      expect(api.streamCalls, [false, true]);
      expect(api.readAcks, 2);

      await tester.tap(find.text('ACTIVITY'));
      await tester.pump();
      await tester.tap(find.text('CHAT'));
      await tester.pump();
      await tester.pump();

      expect(api.streamCalls, [false, true]);
    },
  );

  testWidgets(
    'unsupported bootstrap performs one legacy detail/progress pair',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final api = _CompactRaceRequestApi(bootstrapSupported: false);
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [appRouteObserver],
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-compact',
            backendApiService: api,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(api.bootstrapCalls, 1);
      expect(api.legacyDetailsCalls, 1);
      expect(api.legacyProgressCalls, 1);
    },
  );

  testWidgets(
    'RaceDetailScreen shows a progress skeleton while active race progress loads',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final backendApiService = _SlowProgressRaceBackendApiService();

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-loading-progress',
            backendApiService: backendApiService,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('race-detail-progress-skeleton')),
        findsOneWidget,
      );
      expect(find.text('Powerups are disabled for this race'), findsNothing);
      expect(find.text('No powerup activity yet'), findsNothing);

      backendApiService.progressCompleter.complete({
        'status': 'ACTIVE',
        'participants': const [
          {
            'userId': 'user-1',
            'displayName': 'Trail Walker',
            'totalSteps': 42000,
            'finishedAt': null,
          },
        ],
        'powerupData': const {
          'enabled': false,
          'inventory': [],
          'powerupSlots': 3,
          'queuedBoxCount': 0,
          'activeEffects': [],
        },
      });
      await tester.pump();

      expect(find.byType(HomeCourseTrack), findsOneWidget);
    },
  );

  testWidgets(
    'RaceDetailScreen shows a retry state when active race progress fails',
    (WidgetTester tester) async {
      final authService = await _createAuthService();

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-failing-progress',
            backendApiService: _FailingProgressRaceBackendApiService(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('race-detail-progress-error')),
        findsOneWidget,
      );
      expect(find.text('Couldn’t load race progress'), findsOneWidget);
      expect(find.text('TRY AGAIN'), findsOneWidget);
      expect(find.text('Powerups are disabled for this race'), findsNothing);
    },
  );

  testWidgets('RaceDetailScreen accepts a funded-race invite in one tap', (
    WidgetTester tester,
  ) async {
    final authService = await _createAuthService();
    final backendApiService = _FakeBackendApiService();

    await tester.pumpWidget(
      MaterialApp(
        home: RaceDetailScreen(
          authService: authService,
          raceId: 'race-1',
          backendApiService: backendApiService,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('ACCEPT'), findsOneWidget);

    // The race-day hero sits above the actions — scroll the button into
    // view before tapping.
    await tester.ensureVisible(find.text('ACCEPT'));
    await tester.pump();
    await tester.tap(find.text('ACCEPT'));
    await tester.pump();

    // Nothing is charged, so no buy-in sheet interrupts the accept.
    expect(find.textContaining('GOLD BUY-IN'), findsNothing);
    expect(find.text('LOCK IT IN'), findsNothing);

    // Bounded pumps instead of pumpAndSettle: the hero's spinning-coin
    // prize chip animates forever, so the tree never fully settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(backendApiService.respondCalls, 1);
  });

  testWidgets(
    'RaceDetailScreen shows the prize pool near the countdown for active paid races',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final backendApiService = _ActivePaidRaceBackendApiService();

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-2',
            backendApiService: backendApiService,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // The hero HUD stays as the quick action while the always-visible payout
      // section repeats the amount in the race body.
      expect(find.text('PRIZE POOL'), findsOneWidget);
      expect(find.text('600'), findsOneWidget);
      final prizePoolBoard = find.byKey(const Key('race-prize-pool-board'));
      expect(prizePoolBoard, findsOneWidget);

      await tester.tap(prizePoolBoard);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final prizePoolSummary = find.byKey(
        const Key('race-prize-pool-tier-list'),
      );
      expect(prizePoolSummary, findsOneWidget);
      expect(
        find.descendant(of: prizePoolSummary, matching: find.text('1ST')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: prizePoolSummary, matching: find.text('420')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: prizePoolSummary, matching: find.text('2ND')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: prizePoolSummary, matching: find.text('120')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: prizePoolSummary, matching: find.text('3RD')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: prizePoolSummary, matching: find.text('60')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('race-target-header')),
          matching: find.text('1ST'),
        ),
        findsNothing,
      );
      expect(find.byType(HomeCourseTrack), findsOneWidget);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    },
  );

  testWidgets(
    'RaceDetailScreen keeps active-race reward copy legible at night',
    (WidgetTester tester) async {
      final authService = await _createAuthService();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemeData.night(),
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-2',
            backendApiService: _FinishRewardRaceBackendApiService(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final rewardCopy = tester.widget<Text>(
        find.byKey(const Key('race-finish-reward-copy')),
      );
      expect(rewardCopy.style?.color, AppPalette.night.textLight);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'RaceDetailScreen scrolls every payout place in the structured sheet',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final backendApiService = _FieldScaledPayoutRaceBackendApiService();

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-2',
            backendApiService: backendApiService,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Open the prize-pool sheet from the hero chip: every place belongs to
      // one lazy, scrollable payout list.
      await tester.tap(find.byKey(const Key('race-prize-pool-board')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final summary = find.byKey(const Key('race-prize-pool-tier-list'));
      expect(summary, findsOneWidget);
      expect(
        find.descendant(of: summary, matching: find.text('1ST')),
        findsOneWidget,
      );
      expect(find.text('PAYOUTS'), findsOneWidget);
      expect(find.text('4TH'), findsOneWidget);
      expect(find.text('5TH'), findsOneWidget);
      expect(find.text('+2 MORE'), findsNothing);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    },
  );

  testWidgets(
    'RaceDetailScreen accepts active race numeric fields as doubles',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final backendApiService = _ActivePaidRaceBackendApiService(
        numericValuesAsDouble: true,
        powerupData: const {
          'enabled': true,
          'inventory': [],
          'powerupSlots': 3.0,
          'queuedBoxCount': 0.0,
          'activeEffects': [],
          'powerupStepInterval': 5000.0,
          'stepsUntilNextPowerup': 1240.0,
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-double-values',
            backendApiService: backendApiService,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(HomeCourseTrack), findsOneWidget);
      expect(find.text('PRIZE POOL'), findsOneWidget);
      expect(
        find.text('You earn a powerup every 5,000 steps. 1,240 to go.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'RaceDetailScreen shows the full next powerup helper without truncation',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final backendApiService = _ActivePaidRaceBackendApiService(
        powerupData: const {
          'enabled': true,
          'inventory': [],
          'powerupSlots': 3,
          'queuedBoxCount': 0,
          'activeEffects': [],
          'powerupStepInterval': 5000,
          'stepsUntilNextPowerup': 1240,
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-3',
            backendApiService: backendApiService,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final helper = find.text(
        'You earn a powerup every 5,000 steps. 1,240 to go.',
      );
      expect(helper, findsOneWidget);
      final helperText = tester.widget<Text>(helper);
      expect(helperText.maxLines, isNull);
      expect(helperText.overflow, isNot(TextOverflow.ellipsis));
    },
  );

  testWidgets(
    'RaceDetailScreen retains the last valid countdown when refresh omits it',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final backendApiService = _ActivePaidRaceBackendApiService(
        powerupData: const {
          'enabled': true,
          'inventory': [],
          'powerupSlots': 3,
          'queuedBoxCount': 0,
          'activeEffects': [],
          'powerupStepInterval': 5000,
          'stepsUntilNextPowerup': 1240,
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-refresh-countdown',
            backendApiService: backendApiService,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      const copy = 'You earn a powerup every 5,000 steps. 1,240 to go.';
      expect(find.text(copy), findsOneWidget);

      backendApiService.powerupData = const {
        'enabled': true,
        'inventory': [],
        'powerupSlots': 3,
        'queuedBoxCount': 0,
        'activeEffects': [],
        'powerupStepInterval': 5000,
      };
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, 300),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text(copy), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'RaceDetailScreen hides the next powerup helper when no next interval is available',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final backendApiService = _ActivePaidRaceBackendApiService(
        powerupData: const {
          'enabled': true,
          'inventory': [],
          'powerupSlots': 3,
          'queuedBoxCount': 0,
          'activeEffects': [],
          'powerupStepInterval': 5000,
          'stepsUntilNextPowerup': 0,
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-4',
            backendApiService: backendApiService,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.text('You earn a powerup every 5,000 steps. 1,240 to go.'),
        findsNothing,
      );
      expect(find.textContaining('You earn a powerup every'), findsNothing);
    },
  );

  testWidgets(
    'RaceDetailScreen stretches the waiting-for-creator card to the full pending board width',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final backendApiService = _PendingAcceptedRaceBackendApiService();

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-5',
            backendApiService: backendApiService,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // The current pending view exposes a stable key on the auto-start
      // waiting card; it must stretch to the full padded content width.
      final waitingCard = find.byKey(
        const Key('quick-race-auto-start-pending'),
      );
      expect(waitingCard, findsOneWidget);
      final screenWidth = tester.getSize(find.byType(RaceDetailScreen)).width;
      expect(
        tester.getSize(waitingCard).width,
        equals(screenWidth - 24), // 12px gutter each side
      );
    },
  );

  testWidgets(
    'creator can remove another participant only while the race is pending',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            key: const ValueKey('pending-removal-screen'),
            authService: await _createAuthService(),
            raceId: 'race-pending-removal',
            backendApiService: _PendingAcceptedRaceBackendApiService(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.person_remove), findsNWidgets(2));

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            key: const ValueKey('active-removal-screen'),
            authService: await _createAuthService(),
            raceId: 'race-active-removal',
            backendApiService: _ActivePaidRaceBackendApiService(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byIcon(Icons.person_remove),
        findsNothing,
        reason: 'Once a race starts, its participant roster is locked.',
      );
    },
  );
}
