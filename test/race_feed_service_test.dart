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
  int privateFetchCount = 0;
  List<Map<String, dynamic>> nextPrivateEvents = const [];
  String? nextPrivateCursor;
  String? lastPrivateCursor;
  Completer<PrivateRaceImpactFeedPage>? privateFetchCompleter;

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

  @override
  Future<PrivateRaceImpactFeedPage> fetchPrivateRaceImpactFeed({
    required String identityToken,
    required String raceId,
    String? cursor,
    int limit = 50,
  }) async {
    privateFetchCount += 1;
    lastPrivateCursor = cursor;
    final pending = privateFetchCompleter;
    privateFetchCompleter = null;
    if (pending != null) return pending.future;
    return PrivateRaceImpactFeedPage(
      events: nextPrivateEvents,
      nextCursor: nextPrivateCursor,
    );
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

Map<String, dynamic> _privateEvent(
  String id, {
  String? sourceFeedEventId,
  String? createdAt,
}) => {
  'id': 'impact:$id',
  'eventType': 'EFFECT_IMPACT',
  'powerupType': 'LEG_CRAMP',
  'description': 'You lost 25 synced steps to Leg Cramp.',
  'sourceFeedEventId': sourceFeedEventId,
  'impactScope': 'ACTIVE_SYNCED_SNAPSHOT',
  'createdAt': createdAt ?? '2026-05-18T20:00:00.000Z',
};

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
      ..nextFetchMessages = [
        _event('evt-2', createdAt: '2026-05-18T20:00:02.000Z'),
      ]
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

  test(
    'refreshTop merges new events by id and re-sorts newest-first',
    () async {
      final api = _FakeRaceFeedApi()
        ..nextFetchMessages = [
          _event('evt-1', createdAt: '2026-05-18T20:00:00.000Z'),
        ]
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
    },
  );

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

  test('shared refresh never polls the private impact feed', () async {
    final api = _FakeRaceFeedApi()..nextFetchMessages = [_event('evt-1')];
    final service = RaceFeedService(
      authService: await _authService(),
      raceId: 'race-1',
      api: api,
    );

    await service.loadInitial();
    expect(api.privateFetchCount, 1);

    await service.refreshTop();

    expect(api.privateFetchCount, 1);
  });

  test(
    'private impact deterministically replaces its shared source row',
    () async {
      final api = _FakeRaceFeedApi()
        ..nextFetchMessages = [_event('shared-direct')]
        ..nextPrivateEvents = const [
          {
            'id': 'impact:private-direct',
            'eventType': 'EFFECT_IMPACT',
            'powerupType': 'LEG_CRAMP',
            'description': 'You lost 25 synced steps to Leg Cramp.',
            'sourceFeedEventId': 'shared-direct',
            'impactScope': 'ACTIVE_SYNCED_SNAPSHOT',
            'createdAt': '2026-05-18T20:00:00.000Z',
          },
        ];
      final service = RaceFeedService(
        authService: await _authService(),
        raceId: 'race-1',
        api: api,
      );

      await service.loadInitial();

      expect(service.events.map((event) => event.id), [
        'impact:private-direct',
      ]);
    },
  );

  test('source replacement also applies on top refresh', () async {
    final api = _FakeRaceFeedApi()..nextFetchMessages = [_event('old-shared')];
    final service = RaceFeedService(
      authService: await _authService(),
      raceId: 'race-1',
      api: api,
    );
    await service.loadInitial();

    api.nextFetchMessages = [
      _event('shared-direct', createdAt: '2026-05-18T20:00:05.000Z'),
      _event('old-shared'),
    ];
    await service.refreshTop();
    expect(service.events.map((event) => event.id), [
      'shared-direct',
      'old-shared',
    ]);

    api.nextPrivateEvents = [
      _privateEvent(
        'private-direct',
        sourceFeedEventId: 'shared-direct',
        createdAt: '2026-05-18T20:00:05.000Z',
      ),
    ];
    await service.refreshPrivateTop();

    expect(service.events.map((event) => event.id), [
      'impact:private-direct',
      'old-shared',
    ]);
  });

  test(
    'loadMore advances both cursors and suppresses an older shared row',
    () async {
      final api = _FakeRaceFeedApi()
        ..nextFetchMessages = [
          _event('new-shared', createdAt: '2026-05-18T20:00:10.000Z'),
        ]
        ..nextCursor = 'shared-cursor-1'
        ..nextPrivateEvents = [
          _privateEvent('new-private', createdAt: '2026-05-18T20:00:09.000Z'),
        ]
        ..nextPrivateCursor = 'private-cursor-1';
      final service = RaceFeedService(
        authService: await _authService(),
        raceId: 'race-1',
        api: api,
      );
      await service.loadInitial();

      api
        ..nextFetchMessages = [
          _event('older-direct', createdAt: '2026-05-18T19:00:00.000Z'),
        ]
        ..nextCursor = null
        ..nextPrivateEvents = [
          _privateEvent(
            'older-private',
            sourceFeedEventId: 'older-direct',
            createdAt: '2026-05-18T19:00:00.000Z',
          ),
        ]
        ..nextPrivateCursor = null;

      await service.loadMore();

      expect(api.lastCursor, 'shared-cursor-1');
      expect(api.lastPrivateCursor, 'private-cursor-1');
      expect(service.events.map((event) => event.id), [
        'new-shared',
        'impact:new-private',
        'impact:older-private',
      ]);
      expect(service.hasMore, isFalse);
    },
  );

  test('top refresh preserves both load-older cursors', () async {
    final api = _FakeRaceFeedApi()
      ..nextFetchMessages = [
        _event('shared-new', createdAt: '2026-05-18T20:00:10.000Z'),
      ]
      ..nextCursor = 'shared-bottom-cursor'
      ..nextPrivateEvents = [
        _privateEvent('private-new', createdAt: '2026-05-18T20:00:09.000Z'),
      ]
      ..nextPrivateCursor = 'private-bottom-cursor';
    final service = RaceFeedService(
      authService: await _authService(),
      raceId: 'race-1',
      api: api,
    );
    await service.loadInitial();

    api
      ..nextCursor = 'shared-top-cursor'
      ..nextPrivateCursor = 'private-top-cursor';
    await service.refreshTop();
    await service.refreshPrivateTop();

    api
      ..nextFetchMessages = const []
      ..nextPrivateEvents = const []
      ..nextCursor = null
      ..nextPrivateCursor = null;
    await service.loadMore();

    expect(api.lastCursor, 'shared-bottom-cursor');
    expect(api.lastPrivateCursor, 'private-bottom-cursor');
  });

  test(
    'terminal replacement removes active snapshots before final rows',
    () async {
      final api = _FakeRaceFeedApi()
        ..nextFetchMessages = [_event('shared')]
        ..nextPrivateEvents = [
          _privateEvent('active', createdAt: '2026-05-18T20:00:00.000Z'),
        ];
      final service = RaceFeedService(
        authService: await _authService(),
        raceId: 'race-1',
        api: api,
      );
      await service.loadInitial();
      expect(
        service.events.map((event) => event.id),
        contains('impact:active'),
      );

      api.nextPrivateEvents = [
        {
          ..._privateEvent('final', createdAt: '2026-05-18T21:00:00.000Z'),
          'impactScope': null,
        },
      ];
      await service.replacePrivateImpactStream();

      expect(service.events.map((event) => event.id), [
        'impact:final',
        'shared',
      ]);
      expect(
        service.events.map((event) => event.id),
        isNot(contains('impact:active')),
      );
    },
  );

  test(
    'terminal replacement restores a shared row suppressed by active impact',
    () async {
      final api = _FakeRaceFeedApi()
        ..nextFetchMessages = [
          _event('shared-direct', createdAt: '2026-05-18T20:00:00.000Z'),
        ]
        ..nextPrivateEvents = [
          _privateEvent(
            'active-direct',
            sourceFeedEventId: 'shared-direct',
            createdAt: '2026-05-18T20:00:00.000Z',
          ),
        ];
      final service = RaceFeedService(
        authService: await _authService(),
        raceId: 'race-1',
        api: api,
      );

      await service.loadInitial();
      expect(service.events.map((event) => event.id), ['impact:active-direct']);

      api.nextPrivateEvents = [
        {
          ..._privateEvent('final', createdAt: '2026-05-18T21:00:00.000Z'),
          'impactScope': null,
        },
      ];
      await service.replacePrivateImpactStream();

      expect(service.events.map((event) => event.id), [
        'impact:final',
        'shared-direct',
      ]);
    },
  );

  test(
    'stale active private response cannot land after terminal replacement',
    () async {
      final api = _FakeRaceFeedApi();
      final service = RaceFeedService(
        authService: await _authService(),
        raceId: 'race-1',
        api: api,
      );
      service.applyInitialStream({
        'messages': [_event('shared')],
        'nextCursor': null,
      });

      final staleCompleter = Completer<PrivateRaceImpactFeedPage>();
      api.privateFetchCompleter = staleCompleter;
      final staleRefresh = service.refreshPrivateTop();

      api.nextPrivateEvents = [
        {
          ..._privateEvent('final', createdAt: '2026-05-18T21:00:00.000Z'),
          'impactScope': null,
        },
      ];
      await service.replacePrivateImpactStream();
      staleCompleter.complete(
        PrivateRaceImpactFeedPage(
          events: [
            _privateEvent('active', createdAt: '2026-05-18T20:00:00.000Z'),
          ],
        ),
      );
      await staleRefresh;

      expect(service.events.map((event) => event.id), [
        'impact:final',
        'shared',
      ]);
      expect(
        service.events.map((event) => event.id),
        isNot(contains('impact:active')),
      );
    },
  );

  test(
    'stale active private load-more cannot land after terminal replacement',
    () async {
      final api = _FakeRaceFeedApi()
        ..nextPrivateEvents = [
          _privateEvent('active', createdAt: '2026-05-18T20:00:00.000Z'),
        ]
        ..nextPrivateCursor = 'private-cursor-1';
      final service = RaceFeedService(
        authService: await _authService(),
        raceId: 'race-1',
        api: api,
      );
      await service.loadInitial();

      final staleCompleter = Completer<PrivateRaceImpactFeedPage>();
      api.privateFetchCompleter = staleCompleter;
      final staleLoadMore = service.loadMore();
      await Future<void>.delayed(Duration.zero);

      api
        ..nextPrivateEvents = [
          {
            ..._privateEvent('final', createdAt: '2026-05-18T21:00:00.000Z'),
            'impactScope': null,
          },
        ]
        ..nextPrivateCursor = null;
      await service.replacePrivateImpactStream();

      staleCompleter.complete(
        PrivateRaceImpactFeedPage(
          events: [
            _privateEvent(
              'older-active',
              createdAt: '2026-05-18T19:00:00.000Z',
            ),
          ],
        ),
      );
      await staleLoadMore;

      expect(service.events.map((event) => event.id), ['impact:final']);
    },
  );

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

  test(
    'malformed private expiry row never suppresses valid shared copy',
    () async {
      final api = _FakeRaceFeedApi()
        ..nextFetchMessages = [_event('shared-expiry')]
        ..nextPrivateEvents = const [
          {
            'id': 'impact:malformed-expiry',
            'eventType': 'EFFECT_IMPACT',
            'powerupType': 'LEG_CRAMP',
            'description': '',
            'sourceFeedEventId': 'shared-expiry',
            'createdAt': '2026-05-18T20:00:00.000Z',
          },
        ];
      final service = RaceFeedService(
        authService: await _authService(),
        raceId: 'race-1',
        api: api,
      );

      await service.loadInitial();

      expect(service.events.map((event) => event.id), ['shared-expiry']);
    },
  );
}
