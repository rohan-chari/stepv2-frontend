import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/race_stream_coordinator.dart';

class _StreamsApi extends BackendApiService {
  _StreamsApi({
    this.unsupported = false,
    this.omitWatermark = false,
    this.incrementingChat = false,
    this.initialCompleter,
    this.readAckCompleter,
  });

  final bool unsupported;
  final bool omitWatermark;
  final bool incrementingChat;
  final Completer<RaceMessageStreamsResult>? initialCompleter;
  final Completer<Map<String, dynamic>>? readAckCompleter;
  final List<bool> includeUserCalls = [];
  int legacyUserCalls = 0;
  int legacySystemCalls = 0;
  int readAcks = 0;
  int privateFeedCalls = 0;
  int _chatSequence = 0;

  @override
  Future<RaceMessageStreamsResult> fetchRaceMessageStreams({
    required String identityToken,
    required String raceId,
    required bool includeUser,
    int limit = 50,
  }) async {
    includeUserCalls.add(includeUser);
    final pending = initialCompleter;
    if (includeUserCalls.length == 1 && pending != null) return pending.future;
    if (unsupported) return RaceMessageStreamsResult.unsupported;
    final chatId = 'chat-${++_chatSequence}';
    return RaceMessageStreamsResult(
      supported: true,
      systemResolved: true,
      systemStream: const {
        'messages': [
          {
            'id': 'event-1',
            'kind': 'SYSTEM',
            'body': 'A race event',
            'createdAt': '2026-08-13T12:00:00.000Z',
          },
        ],
        'nextCursor': null,
      },
      userResolved: includeUser,
      userStream: includeUser
          ? {
              'messages': [
                {
                  'id': incrementingChat ? chatId : 'chat-1',
                  'kind': 'USER',
                  'body': 'Hello',
                  'createdAt': '2026-08-13T12:00:00.000Z',
                },
              ],
              'nextCursor': null,
            }
          : null,
      chatWatermark: omitWatermark
          ? null
          : const {
              'latestId': 'chat-1',
              'recentIds': ['chat-1'],
            },
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
    if (kind == 'USER') legacyUserCalls++;
    if (kind == 'SYSTEM') legacySystemCalls++;
    return const {'messages': [], 'nextCursor': null};
  }

  @override
  Future<Map<String, dynamic>> markRaceChatRead({
    required String identityToken,
    required String raceId,
  }) async {
    readAcks++;
    final pending = readAckCompleter;
    if (pending != null) return pending.future;
    return const {};
  }

  @override
  Future<PrivateRaceImpactFeedPage> fetchPrivateRaceImpactFeed({
    required String identityToken,
    required String raceId,
    String? cursor,
    int limit = 50,
  }) async {
    privateFeedCalls += 1;
    return PrivateRaceImpactFeedPage.empty;
  }
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'identity',
    'auth_session_token': 'session',
    'auth_backend_user_id': 'user-1',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.bara.app',
      version: '2.3.3',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  test(
    'initializes Activity and watermark without constructing Chat',
    () async {
      final api = _StreamsApi();
      final coordinator = RaceStreamCoordinator(
        authService: await _auth(),
        raceId: 'race-1',
        api: api,
      );

      await coordinator.initialize(live: false);

      expect(api.includeUserCalls, [false]);
      expect(coordinator.feed.events, hasLength(1));
      expect(coordinator.chat, isNull);
      expect(coordinator.chatHasUnread, isFalse);
      expect(api.readAcks, 1);
      expect(api.privateFeedCalls, 1);
      coordinator.dispose();
    },
  );

  test(
    'first Chat open performs one combined read and applies USER rows',
    () async {
      final api = _StreamsApi();
      final coordinator = RaceStreamCoordinator(
        authService: await _auth(),
        raceId: 'race-1',
        api: api,
      );
      await coordinator.initialize(live: false);

      await coordinator.openChat();

      expect(api.includeUserCalls, [false, true]);
      expect(api.privateFeedCalls, 1);
      expect(coordinator.chat?.messages.single.body, 'Hello');
      coordinator.dispose();
    },
  );

  test('unsupported endpoint restores both legacy initial services', () async {
    final api = _StreamsApi(unsupported: true);
    final coordinator = RaceStreamCoordinator(
      authService: await _auth(),
      raceId: 'race-1',
      api: api,
    );

    await coordinator.initialize(live: false);

    expect(coordinator.legacyMode, isTrue);
    expect(api.legacyUserCalls, 1);
    expect(api.legacySystemCalls, 1);
    await coordinator.openChat();
    expect(api.legacyUserCalls, 1);
    coordinator.dispose();
  });

  test('pending read acknowledgement never blocks streams or Chat', () async {
    final readAck = Completer<Map<String, dynamic>>();
    final api = _StreamsApi(readAckCompleter: readAck);
    final coordinator = RaceStreamCoordinator(
      authService: await _auth(),
      raceId: 'race-1',
      api: api,
    );

    await coordinator
        .initialize(live: false)
        .timeout(const Duration(milliseconds: 100));
    await coordinator.openChat().timeout(const Duration(milliseconds: 100));

    expect(api.includeUserCalls, [false, true]);
    expect(coordinator.chat?.isLoading, isFalse);
    expect(api.readAcks, 2);
    coordinator.dispose();
  });

  test(
    'legacy resume catches up both streams without retrying compact',
    () async {
      final api = _StreamsApi(unsupported: true);
      final coordinator = RaceStreamCoordinator(
        authService: await _auth(),
        raceId: 'race-1',
        api: api,
      );
      await coordinator.initialize(live: true);
      coordinator.pause();

      await coordinator.resume();

      expect(api.includeUserCalls, [false]);
      expect(api.legacySystemCalls, 2);
      expect(api.legacyUserCalls, 2);
      coordinator.dispose();
    },
  );

  test('initial missing watermark acknowledges read exactly once', () async {
    final api = _StreamsApi(omitWatermark: true);
    final coordinator = RaceStreamCoordinator(
      authService: await _auth(),
      raceId: 'race-1',
      api: api,
    );

    await coordinator.initialize(live: false);

    expect(api.readAcks, 1);
    coordinator.dispose();
  });

  test(
    'resume restores visible Chat before applying the catch-up stream',
    () async {
      final api = _StreamsApi(incrementingChat: true);
      final coordinator = RaceStreamCoordinator(
        authService: await _auth(),
        raceId: 'race-1',
        api: api,
      );
      await coordinator.initialize(live: true);
      await coordinator.openChat();
      coordinator.pause();

      await coordinator.resume(chatVisible: true);

      expect(coordinator.chat?.hasUnread, isFalse);
      coordinator.dispose();
    },
  );

  test(
    'Chat opened during initialization drains the queued USER read',
    () async {
      final initial = Completer<RaceMessageStreamsResult>();
      final api = _StreamsApi(initialCompleter: initial);
      final coordinator = RaceStreamCoordinator(
        authService: await _auth(),
        raceId: 'race-1',
        api: api,
      );

      final initialize = coordinator.initialize(live: false);
      await Future<void>.delayed(Duration.zero);
      final openChat = coordinator.openChat();
      initial.complete(
        RaceMessageStreamsResult(
          supported: true,
          systemResolved: true,
          systemStream: const {'messages': [], 'nextCursor': null},
          userResolved: false,
          chatWatermark: const {'recentIds': <String>[]},
        ),
      );
      await Future.wait([initialize, openChat]);

      expect(api.includeUserCalls, [false, true]);
      expect(coordinator.chat?.isLoading, isFalse);
      expect(coordinator.chat?.messages.single.body, 'Hello');
      coordinator.dispose();
    },
  );

  test(
    'Chat opened during a 404 initializes through legacy USER read',
    () async {
      final initial = Completer<RaceMessageStreamsResult>();
      final api = _StreamsApi(initialCompleter: initial);
      final coordinator = RaceStreamCoordinator(
        authService: await _auth(),
        raceId: 'race-1',
        api: api,
      );

      final initialize = coordinator.initialize(live: false);
      await Future<void>.delayed(Duration.zero);
      final openChat = coordinator.openChat();
      initial.complete(RaceMessageStreamsResult.unsupported);
      await Future.wait([initialize, openChat]);

      expect(coordinator.legacyMode, isTrue);
      expect(api.legacySystemCalls, 1);
      expect(api.legacyUserCalls, 1);
      expect(coordinator.chat?.isLoading, isFalse);
      expect(api.readAcks, 1);
      coordinator.dispose();
    },
  );
}
