import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(
    this.statusCode,
    Map<String, dynamic>? body, {
    Map<String, String> headers = const {},
  }) : headers = _ResponseHeaders(headers),
       _bytes = body == null ? const [] : utf8.encode(jsonEncode(body));

  @override
  final int statusCode;
  final List<int> _bytes;

  @override
  final HttpHeaders headers;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(_bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request extends Fake implements HttpClientRequest {
  _Request(this.response);

  final HttpClientResponse response;
  final Map<String, String> capturedHeaders = {};

  @override
  final HttpHeaders headers = _Headers();

  @override
  Future<HttpClientResponse> close() async => response;

  @override
  void write(Object? object) {}
}

class _Headers extends Fake implements HttpHeaders {
  final Map<String, Object> values = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = value;
  }

  @override
  set contentType(ContentType? value) {
    if (value != null) values[HttpHeaders.contentTypeHeader] = value.toString();
  }
}

class _ResponseHeaders extends Fake implements HttpHeaders {
  _ResponseHeaders(Map<String, String> values)
    : values = {
        for (final entry in values.entries)
          entry.key.toLowerCase(): entry.value,
      };

  final Map<String, String> values;

  @override
  String? value(String name) => values[name.toLowerCase()];
}

class _Http extends Fake implements HttpClient {
  _Http(this.responses);

  final List<HttpClientResponse> responses;
  final List<Uri> uris = [];
  final List<_Request> requests = [];
  int _index = 0;

  @override
  set connectionTimeout(Duration? value) {}

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    uris.add(url);
    final request = _Request(responses[_index++]);
    requests.add(request);
    return request;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (_) async => 'America/New_York',
        );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.bara.app',
      version: '2.3.3',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  test(
    'typed Detour target context preserves mask and targeting metadata',
    () async {
      final http = _Http([
        _Response(200, const {
          'contract': 'race-powerup-target-context-v1',
          'participants': [
            {
              'userId': 'masked-rival',
              'displayName': '???',
              'profilePhotoUrl': null,
              'team': null,
              'forfeitedAt': null,
              'stealthed': true,
              'targetable': true,
            },
          ],
          'powerupData': {
            'powerupSlots': 3,
            'inventory': [],
            'queuedBoxCount': 0,
            'myPlacement': null,
          },
        }),
      ]);

      final result = await BackendApiService(httpClient: http)
          .fetchRacePowerupTargetContext(
            identityToken: 'token',
            raceId: 'race-1',
            powerupType: 'LEG_CRAMP',
          );
      final participant = (result['participants'] as List).single as Map;
      expect(participant['displayName'], '???');
      expect(participant['stealthed'], isTrue);
      expect(participant['targetable'], isTrue);
      expect(participant.containsKey('totalSteps'), isFalse);
    },
  );

  test(
    'compact race bootstrap rejects a naked lean participant page',
    () async {
      Map<String, dynamic> payload(Map<String, dynamic> participant) => {
        'contract': 'race-bootstrap-compact-v1',
        'race': {
          'status': 'ACTIVE',
          'isTeamRace': false,
          'acceptedCount': 1,
          'participantUserIds': ['user-1'],
          'myStatus': 'ACCEPTED',
          'myTotalSteps': 1200,
          'participantsPagination': {
            'offset': 0,
            'limit': 15,
            'total': 1,
            'hasMore': false,
            'nextOffset': 1,
          },
        },
        'progress': {
          'status': 'ACTIVE',
          'participants': [participant],
          'pagination': {
            'offset': 0,
            'limit': 15,
            'total': 1,
            'hasMore': false,
            'nextOffset': 1,
          },
        },
      };

      final missingPresentationHttp = _Http([
        _Response(
          200,
          payload(const {
            'userId': 'user-1',
            'displayName': 'River',
            'totalSteps': 1200,
          }),
        ),
      ]);
      final missingPresentationApi = BackendApiService(
        httpClient: missingPresentationHttp,
      );
      final rejected = await missingPresentationApi.fetchRaceBootstrap(
        identityToken: 'token',
        raceId: 'race-1',
        participantsLimit: 15,
      );
      expect(rejected.supported, isFalse);

      final hydratedHttp = _Http([
        _Response(
          200,
          payload(const {
            'userId': 'user-1',
            'displayName': 'River',
            'totalSteps': 1200,
            'animal': 'corgi_puppy',
            'accessories': [
              {'assetKey': 'sunglasses'},
              {'assetKey': 'beaver_tail'},
            ],
          }),
        ),
      ]);
      final hydratedApi = BackendApiService(httpClient: hydratedHttp);
      final accepted = await hydratedApi.fetchRaceBootstrap(
        identityToken: 'token',
        raceId: 'race-1',
        participantsLimit: 15,
      );
      expect(accepted.supported, isTrue);
      final row = (accepted.progress!['participants'] as List).single as Map;
      expect(row['animal'], 'corgi_puppy');
      expect(row['accessories'], hasLength(2));
    },
  );

  test('race bootstrap caches only a definite 404 as unsupported', () async {
    final http = _Http([
      _Response(404, const {'error': 'Not found'}),
    ]);
    final api = BackendApiService(httpClient: http);

    final first = await api.fetchRaceBootstrap(
      identityToken: 'token',
      raceId: 'race-1',
    );
    final second = await api.fetchRaceBootstrap(
      identityToken: 'token',
      raceId: 'race-1',
    );

    expect(first.supported, isFalse);
    expect(second.supported, isFalse);
    expect(http.uris, hasLength(1));
    expect(http.uris.single.path, '/races/race-1/bootstrap');
  });

  test('compact progress safely retains a missing inventory block', () async {
    final http = _Http([
      _Response(200, const {
        'contract': 'race-progress-compact-v1',
        'progress': {'status': 'ACTIVE'},
        'globalPowerupInventory': null,
      }),
    ]);
    final api = BackendApiService(httpClient: http);

    final result = await api.fetchRaceProgressCompact(
      identityToken: 'token',
      raceId: 'race-1',
    );

    expect(result.progress['status'], 'ACTIVE');
    expect(result.globalPowerupInventory, isNull);
    expect(result.hasCompactInventory, isFalse);
    expect(http.uris.single.queryParameters['view'], 'compact-v1');
  });

  test('compact progress rejects a malformed inventory envelope', () async {
    final http = _Http([
      _Response(200, const {
        'contract': 'race-progress-compact-v1',
        'progress': {'status': 'ACTIVE'},
        'globalPowerupInventory': {'items': 'malformed'},
      }),
    ]);
    final api = BackendApiService(httpClient: http);

    final result = await api.fetchRaceProgressCompact(
      identityToken: 'token',
      raceId: 'race-1',
    );

    expect(result.globalPowerupInventory, isNull);
    expect(result.hasCompactInventory, isFalse);
  });

  test(
    'participants-v1 preserves the viewer globalEvent without new request params',
    () async {
      final http = _Http([
        _Response(200, const {
          'progress': {
            'status': 'ACTIVE',
            'globalEvent': {
              'active': true,
              'multiplier': 2,
              'endsAt': '2026-08-20T15:47:00.000Z',
            },
            'participants': [
              {
                'userId': 'user-1',
                'displayName': 'River',
                'totalSteps': 1200,
                'animal': 'corgi_puppy',
                'accessories': <Map<String, dynamic>>[],
              },
            ],
          },
          'pagination': {
            'offset': 0,
            'limit': 15,
            'total': 1,
            'hasMore': false,
            'nextOffset': 1,
          },
        }),
      ]);
      final api = BackendApiService(httpClient: http);

      final result = await api.fetchRaceProgressParticipants(
        identityToken: 'token',
        raceId: 'race-1',
        limit: 15,
      );

      expect(result.progress['globalEvent'], const {
        'active': true,
        'multiplier': 2,
        'endsAt': '2026-08-20T15:47:00.000Z',
      });
      expect(http.uris.single.queryParameters, const {
        'view': 'participants-v1',
        'offset': '0',
        'limit': '15',
      });
      final headers = http.requests.single.headers as _Headers;
      expect(headers.values['x-timezone'], 'America/New_York');
    },
  );

  test(
    'home race-card preserves the viewer globalEvent on its existing request',
    () async {
      final http = _Http([
        _Response(200, const {
          'state': 'EMPTY',
          'globalEvent': {
            'active': true,
            'multiplier': 2,
            'endsAt': '2026-08-20T15:47:00.000Z',
          },
        }),
      ]);
      final api = BackendApiService(httpClient: http);

      final result = await api.fetchHomeRaceCard(identityToken: 'token');

      expect(result['globalEvent'], const {
        'active': true,
        'multiplier': 2,
        'endsAt': '2026-08-20T15:47:00.000Z',
      });
      expect(http.uris.single.path, '/home/race-card');
      expect(
        http.uris.single.queryParameters.keys,
        unorderedEquals(const ['view', 'homeActiveRaces', 'localDate']),
      );
      final headers = http.requests.single.headers as _Headers;
      expect(headers.values['x-timezone'], 'America/New_York');
    },
  );

  test(
    'paged race progress falls back when lean rows lack presentation',
    () async {
      final http = _Http([
        _Response(200, const {
          'progress': {
            'status': 'ACTIVE',
            'participants': [
              {'userId': 'user-1', 'displayName': 'River', 'totalSteps': 1200},
            ],
          },
          'pagination': {
            'offset': 0,
            'limit': 15,
            'total': 1,
            'hasMore': false,
            'nextOffset': 1,
          },
        }),
        _Response(200, const {
          'contract': 'race-progress-compact-v1',
          'progress': {
            'status': 'ACTIVE',
            'participants': [
              {
                'userId': 'user-1',
                'displayName': 'River',
                'totalSteps': 1200,
                'animal': 'corgi_puppy',
                'accessories': [
                  {'assetKey': 'sunglasses'},
                  {'assetKey': 'beaver_tail'},
                ],
              },
            ],
          },
        }),
      ]);
      final api = BackendApiService(httpClient: http);

      final result = await api.fetchRaceProgressParticipants(
        identityToken: 'token',
        raceId: 'race-1',
        limit: 15,
      );

      expect(result.participantsPagination, isNull);
      final row = (result.progress['participants'] as List).single as Map;
      expect(row['animal'], 'corgi_puppy');
      expect(row['accessories'], hasLength(2));
      expect(http.uris, hasLength(2));
      expect(http.uris.first.queryParameters['view'], 'participants-v1');
      expect(http.uris.last.queryParameters['view'], 'compact-v1');
    },
  );

  test('message streams rejects malformed resolved stream envelopes', () async {
    final http = _Http([
      _Response(200, const {
        'contract': 'race-message-streams-v1',
        'requested': {'SYSTEM': true, 'USER': false},
        'resolved': {'SYSTEM': true, 'USER': false},
        'streams': {'SYSTEM': <String, dynamic>{}, 'USER': null},
        'chatWatermark': null,
      }),
    ]);
    final api = BackendApiService(httpClient: http);

    final result = await api.fetchRaceMessageStreams(
      identityToken: 'token',
      raceId: 'race-1',
      includeUser: false,
    );

    expect(result.malformed, isTrue);
  });

  test('message streams caches 404 but not malformed success', () async {
    final malformedHttp = _Http([
      _Response(200, const {'contract': 'wrong'}),
      _Response(200, const {'contract': 'wrong'}),
    ]);
    final malformedApi = BackendApiService(httpClient: malformedHttp);

    final first = await malformedApi.fetchRaceMessageStreams(
      identityToken: 'token',
      raceId: 'race-1',
      includeUser: false,
    );
    final second = await malformedApi.fetchRaceMessageStreams(
      identityToken: 'token',
      raceId: 'race-1',
      includeUser: false,
    );
    expect(first.malformed, isTrue);
    expect(second.malformed, isTrue);
    expect(malformedHttp.uris, hasLength(2));

    final oldHttp = _Http([
      _Response(404, const {'error': 'Not found'}),
    ]);
    final oldApi = BackendApiService(httpClient: oldHttp);
    expect(
      (await oldApi.fetchRaceMessageStreams(
        identityToken: 'token',
        raceId: 'race-1',
        includeUser: false,
      )).supported,
      isFalse,
    );
    expect(
      (await oldApi.fetchRaceMessageStreams(
        identityToken: 'token',
        raceId: 'race-1',
        includeUser: true,
      )).supported,
      isFalse,
    );
    expect(oldHttp.uris, hasLength(1));
  });

  test(
    'compact existing views send their exact immutable contract names',
    () async {
      final http = _Http([
        _Response(200, const {}),
        _Response(200, const {'user': <String, dynamic>{}}),
        _Response(200, const {}),
        _Response(200, const {'races': []}),
        _Response(200, const {}),
        _Response(200, const {}),
        _Response(200, const {}),
        _Response(200, const {}),
      ]);
      final api = BackendApiService(httpClient: http);

      await api.fetchFriends(identityToken: 'token');
      await api.fetchMe(identityToken: 'token');
      await api.fetchGetCoinsStatus(
        identityToken: 'token',
        localDate: '2026-08-13',
      );
      await api.fetchPublicRaceBrowser(identityToken: 'token');
      await api.fetchRankedV2(identityToken: 'token');
      await api.fetchStats(identityToken: 'token');
      await api.fetchTournament(identityToken: 'token', tournamentId: 't-1');
      await api.fetchHomeRaceCard(identityToken: 'token');

      expect(http.uris.first.path, '/friends');
      expect(
        http.uris.map((uri) => uri.queryParameters['view']).toList(),
        const [
          'summary-v1',
          'shell-v1',
          'get-coins-v1',
          'browser-v1',
          'compact-v1',
          'profile-v1',
          'detail-v1',
          'shell-v1',
        ],
      );
    },
  );

  test('shop bootstrap rejects malformed mandatory cosmetics', () async {
    final http = _Http([
      _Response(200, const {
        'contract': 'shop-bootstrap-v1',
        'cosmetics': <String, dynamic>{
          'coins': 1,
          'ownedItemIds': <String>[],
          'equipped': <String, dynamic>{},
          'adUnlock': <String, dynamic>{},
          'items': <Map<String, dynamic>>[
            {
              'id': 'broken',
              'sku': 'BROKEN',
              'name': 'Broken',
              'description': 'Bad row',
              'slot': 'HEAD',
              'priceCoins': 'malformed',
              'assetKey': 'broken',
              'owned': false,
              'equipped': false,
            },
          ],
        },
        'resolved': {'powerups': true, 'inventory': true},
        'powerups': {'coins': 1, 'items': [], 'adUnlock': {}},
        'inventory': {'items': []},
      }),
    ]);
    final api = BackendApiService(httpClient: http);

    await expectLater(
      api.fetchShopBootstrap(identityToken: 'token', localDate: '2026-08-13'),
      throwsA(isA<ApiException>()),
    );
  });

  test('shop bootstrap accepts an unavailable ad-unlock policy', () async {
    final http = _Http([
      _Response(200, const {
        'contract': 'shop-bootstrap-v1',
        'cosmetics': {
          'coins': 1,
          'ownedItemIds': <String>[],
          'equipped': <String, dynamic>{},
          'items': <Map<String, dynamic>>[],
        },
        'resolved': {'powerups': true, 'inventory': true},
        'powerups': {'coins': 1, 'items': <Map<String, dynamic>>[]},
        'inventory': {'items': <Map<String, dynamic>>[]},
      }),
    ]);
    final api = BackendApiService(httpClient: http);

    final result = await api.fetchShopBootstrap(
      identityToken: 'token',
      localDate: '2026-08-13',
    );

    expect(result.supported, isTrue);
    expect(result.powerups, isNotNull);
  });

  test('shop bootstrap caches 404 and starts all legacy reads', () async {
    final http = _Http([
      _Response(404, const {'error': 'Not found'}),
      _Response(200, const {'coins': 9, 'items': []}),
      _Response(200, const {'coins': 9, 'items': []}),
      _Response(200, const {'items': []}),
      _Response(200, const {'coins': 9, 'items': []}),
      _Response(200, const {'coins': 9, 'items': []}),
      _Response(200, const {'items': []}),
    ]);
    final api = BackendApiService(httpClient: http);

    final first = await api.fetchShopBootstrap(
      identityToken: 'token',
      localDate: '2026-08-13',
    );
    final second = await api.fetchShopBootstrap(
      identityToken: 'token',
      localDate: '2026-08-13',
    );

    expect(first.supported, isFalse);
    expect(second.supported, isFalse);
    expect(first.cosmetics['coins'], 9);
    expect(
      http.uris.where((uri) => uri.path == '/shop/bootstrap'),
      hasLength(1),
    );
    expect(http.uris.where((uri) => uri.path == '/shop/catalog'), hasLength(2));
    expect(
      http.uris.where((uri) => uri.path == '/shop/powerups'),
      hasLength(2),
    );
    expect(
      http.uris.where((uri) => uri.path == '/powerups/inventory'),
      hasLength(2),
    );
  });

  test(
    'version policy reuses a persisted body only after a validating 304',
    () async {
      SharedPreferences.setMockInitialValues({
        'http_etag_version_policy_etag': '"policy-1"',
        'http_etag_version_policy_body': jsonEncode({
          'minSupportedVersion': '2.0.0',
        }),
      });
      final http = _Http([_Response(304, null)]);
      final api = BackendApiService(httpClient: http);

      final result = await api.fetchVersionPolicy();

      expect(result['minSupportedVersion'], '2.0.0');
      final headers = http.requests.single.headers as _Headers;
      expect(headers.values['if-none-match'], '"policy-1"');
    },
  );

  test('cacheless 304 retries once without a validator', () async {
    SharedPreferences.setMockInitialValues({
      'http_etag_version_policy_etag': '"orphan"',
    });
    final http = _Http([
      _Response(304, null),
      _Response(
        200,
        const {'minSupportedVersion': '2.0.0'},
        headers: const {'etag': '"policy-2"'},
      ),
    ]);
    final api = BackendApiService(httpClient: http);

    final result = await api.fetchVersionPolicy();

    expect(result['minSupportedVersion'], '2.0.0');
    expect(http.requests, hasLength(2));
    expect(
      (http.requests.first.headers as _Headers).values['if-none-match'],
      '"orphan"',
    );
    expect(
      (http.requests.last.headers as _Headers).values['if-none-match'],
      isNull,
    );
  });
}
