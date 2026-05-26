import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/race_feed_service.dart';

class _FakeRaceFeedApi extends BackendApiService {
  Completer<Map<String, dynamic>>? fetchCompleter;
  List<Map<String, dynamic>> nextFetchMessages = const [];
  String? nextCursor;
  String? lastKind;
  String? lastCursor;
  int fetchCount = 0;

  @override
  Future<Map<String, dynamic>> fetchRaceMessages({
    required String identityToken,
    required String raceId,
    String? cursor,
    int? limit,
    String? kind,
  }) {
    fetchCount += 1;
    lastKind = kind;
    lastCursor = cursor;
    final completer = fetchCompleter;
    if (completer != null) return completer.future;
    return Future.value({
      'messages': nextFetchMessages,
      'nextCursor': nextCursor,
    });
  }
}

Map<String, dynamic> _event(String id, {String? createdAt}) {
  return {
    'id': id,
    'kind': 'SYSTEM',
    'body': 'Alice used Leg Cramp on Bob',
    'eventType': 'POWERUP_USED',
    'powerupType': 'LEG_CRAMP',
    'actorUserId': 'user-2',
    'targetUserId': 'user-3',
    'createdAt': createdAt ?? '2026-05-18T20:00:00.000Z',
  };
}

Future<AuthService> _authService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loadInitial fetches with kind=SYSTEM and parses events', () async {
    final api = _FakeRaceFeedApi()
      ..nextFetchMessages = [_event('evt-1')]
      ..nextCursor = null;
    final service = RaceFeedService(
      authService: await _authService(),
      raceId: 'race-1',
      api: api,
    );

    await service.loadInitial();

    expect(api.lastKind, 'SYSTEM');
    expect(service.events, hasLength(1));
    expect(service.events.single.id, 'evt-1');
    expect(service.events.single.eventType, 'POWERUP_USED');
    expect(service.events.single.powerupType, 'LEG_CRAMP');
    expect(service.hasMore, isFalse);
  });

  test('hasMore is true when nextCursor is present', () async {
    final api = _FakeRaceFeedApi()
      ..nextFetchMessages = [_event('evt-1')]
      ..nextCursor = 'cursor-abc';
    final service = RaceFeedService(
      authService: await _authService(),
      raceId: 'race-1',
      api: api,
    );

    await service.loadInitial();
    expect(service.hasMore, isTrue);
  });

  test('loadMore appends older events using the cursor', () async {
    final api = _FakeRaceFeedApi()
      ..nextFetchMessages = [_event('evt-2', createdAt: '2026-05-18T20:00:02.000Z')]
      ..nextCursor = 'cursor-1';
    final service = RaceFeedService(
      authService: await _authService(),
      raceId: 'race-1',
      api: api,
    );
    await service.loadInitial();

    api.nextFetchMessages = [
      _event('evt-1', createdAt: '2026-05-18T20:00:00.000Z'),
    ];
    api.nextCursor = null;
    await service.loadMore();

    expect(api.lastCursor, 'cursor-1');
    expect(service.events.map((e) => e.id), ['evt-2', 'evt-1']);
    expect(service.hasMore, isFalse);
  });

  test('refreshTop merges new events by id and re-sorts newest-first', () async {
    final api = _FakeRaceFeedApi()
      ..nextFetchMessages = [_event('evt-1', createdAt: '2026-05-18T20:00:00.000Z')]
      ..nextCursor = null;
    final service = RaceFeedService(
      authService: await _authService(),
      raceId: 'race-1',
      api: api,
    );
    await service.loadInitial();

    api.nextFetchMessages = [
      _event('evt-2', createdAt: '2026-05-18T20:00:05.000Z'),
      _event('evt-1', createdAt: '2026-05-18T20:00:00.000Z'),
    ];
    await service.refreshTop();

    expect(service.events.map((e) => e.id), ['evt-2', 'evt-1']);
  });

  test('refreshTop is a no-op when no new events arrive', () async {
    final api = _FakeRaceFeedApi()
      ..nextFetchMessages = [_event('evt-1')]
      ..nextCursor = null;
    final service = RaceFeedService(
      authService: await _authService(),
      raceId: 'race-1',
      api: api,
    );
    await service.loadInitial();

    var notified = 0;
    service.addListener(() => notified += 1);
    api.nextFetchMessages = [_event('evt-1')];
    await service.refreshTop();

    expect(service.events, hasLength(1));
    expect(notified, 0);
  });

  test('loadInitial after dispose does not throw or notify', () async {
    final api = _FakeRaceFeedApi()
      ..fetchCompleter = Completer<Map<String, dynamic>>();
    final service = RaceFeedService(
      authService: await _authService(),
      raceId: 'race-1',
      api: api,
    );

    final future = service.loadInitial();
    service.dispose();
    api.fetchCompleter!.complete({
      'messages': [_event('evt-1')],
      'nextCursor': null,
    });
    await future;

    expect(service.events, isEmpty);
  });

  test('lastError is set when fetch throws', () async {
    final api = _FakeRaceFeedApi()
      ..fetchCompleter = Completer<Map<String, dynamic>>();
    final service = RaceFeedService(
      authService: await _authService(),
      raceId: 'race-1',
      api: api,
    );

    final future = service.loadInitial();
    api.fetchCompleter!.completeError(const ApiException('boom'));
    await future;

    expect(service.lastError, isNotNull);
    expect(service.events, isEmpty);
  });
}
