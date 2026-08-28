import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/models/balance_config.dart';
import 'package:step_tracker/services/backend_api_service.dart';

/// Wire-contract tests for the admin balance-config and powerup-shop endpoints
/// (spec §5.1 / §5.2).
///
/// The screen tests drive a fake BackendApiService, so they never exercise the
/// real request body or the real status-code branching — exactly the two places
/// a contract mismatch would live. These assert what actually goes on the wire
/// and what comes back off it.
class _Scripted {
  const _Scripted(this.status, this.body);
  final int status;
  final String body;
}

class _CapturedRequest {
  _CapturedRequest(this.method, this.uri);
  final String method;
  final Uri uri;
  final StringBuffer body = StringBuffer();
  final Map<String, String> headers = {};
}

class _FakeHeaders implements HttpHeaders {
  _FakeHeaders(this.captured);
  final _CapturedRequest captured;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    captured.headers[name] = value.toString();
  }

  @override
  ContentType? contentType;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse(this._status, this._body);
  final int _status;
  final String _body;

  @override
  int get statusCode => _status;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([utf8.encode(_body)]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this.captured, this._script);
  final _CapturedRequest captured;
  final _Scripted _script;

  @override
  late final HttpHeaders headers = _FakeHeaders(captured);

  @override
  void write(Object? object) => captured.body.write(object);

  @override
  Future<HttpClientResponse> close() async =>
      _FakeResponse(_script.status, _script.body);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this._scripts);
  final List<_Scripted> _scripts;
  final List<_CapturedRequest> requests = [];
  int _i = 0;

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final captured = _CapturedRequest(method, url);
    requests.add(captured);
    final script = _scripts[_i < _scripts.length ? _i : _scripts.length - 1];
    _i += 1;
    return _FakeRequest(captured, script);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _bodyOf(_CapturedRequest r) =>
    jsonDecode(r.body.toString()) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (call) async => 'America/New_York',
        );
  });

  group('referral contest wire contract', () {
    test(
      'member discovery and entry use the dedicated additive endpoints',
      () async {
        final client = _FakeHttpClient([
          const _Scripted(
            200,
            '{"contest":null,"leaderboard":[],"entry":null,"standing":null,"share":null}',
          ),
          const _Scripted(201, '{"entry":{"status":"ELIGIBLE"}}'),
        ]);
        final api = BackendApiService(httpClient: client);

        await api.fetchCurrentGiveaway(identityToken: 'tok');
        await api.enterGiveaway(
          identityToken: 'tok',
          slug: 'bara-referral-2026-09',
          rulesVersion: '2026-09-v1',
          country: 'US',
          region: 'US-NY',
          ageConfirmed: true,
          residencyConfirmed: true,
          rulesAccepted: true,
        );

        expect(client.requests.first.uri.path, '/giveaways/current/me');
        expect(
          client.requests.last.uri.path,
          '/giveaways/bara-referral-2026-09/entries',
        );
        expect(_bodyOf(client.requests.last), {
          'rulesVersion': '2026-09-v1',
          'country': 'US',
          'region': 'US-NY',
          'ageConfirmed': true,
          'residencyConfirmed': true,
          'rulesAccepted': true,
        });
        expect(
          client.requests.last.body.toString(),
          isNot(contains('displayName')),
        );
        expect(
          client.requests.last.body.toString(),
          isNot(contains('dateOfBirth')),
        );
        expect(
          client.requests.last.body.toString(),
          isNot(contains('payment')),
        );
      },
    );

    test(
      'admin list, detail, and candidate cursors preserve opaque values',
      () async {
        final client = _FakeHttpClient(
          List.filled(3, const _Scripted(200, '{}')),
        );
        final api = BackendApiService(httpClient: client);

        await api.fetchAdminGiveaways(
          identityToken: 'tok',
          cursor: 'created:id/+',
          limit: 25,
        );
        await api.fetchAdminGiveawayDetail(
          identityToken: 'tok',
          contestId: 'contest/id',
        );
        await api.fetchAdminGiveawayCandidates(
          identityToken: 'tok',
          contestId: 'contest/id',
          cursor: 'rank:id/+',
          limit: 50,
        );

        expect(client.requests[0].uri.path, '/admin/giveaways');
        expect(client.requests[0].uri.queryParameters, {
          'limit': '25',
          'cursor': 'created:id/+',
        });
        expect(client.requests[1].uri.path, '/admin/giveaways/contest%2Fid');
        expect(
          client.requests[2].uri.path,
          '/admin/giveaways/contest%2Fid/candidates',
        );
        expect(client.requests[2].uri.queryParameters, {
          'limit': '50',
          'cursor': 'rank:id/+',
        });
      },
    );

    test(
      'admin mutation sends exact action body and UUID idempotency header',
      () async {
        final client = _FakeHttpClient([const _Scripted(200, '{}')]);
        final api = BackendApiService(httpClient: client);

        await api.mutateAdminGiveaway(
          identityToken: 'tok',
          contestId: 'contest-1',
          action: 'award-coins',
          idempotencyKey: 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
          body: const {'revision': 9},
        );

        final request = client.requests.single;
        expect(request.method, 'POST');
        expect(request.uri.path, '/admin/giveaways/contest-1/award-coins');
        expect(_bodyOf(request), {'revision': 9});
        expect(
          request.headers['Idempotency-Key'],
          'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
        );
      },
    );

    test('banner correction sends the exact audited contract', () async {
      final client = _FakeHttpClient([const _Scripted(200, '{}')]);
      final api = BackendApiService(httpClient: client);
      const key = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';

      await api.correctAdminGiveawayBanner(
        identityToken: 'tok',
        contestId: 'contest/id',
        idempotencyKey: key,
        revision: 8,
        bannerMessage: r'Corrected: win US$50 + 5,000 Bara coins.',
        reason: 'Corrected end-user wording without changing material terms.',
      );

      final request = client.requests.single;
      expect(request.method, 'POST');
      expect(
        request.uri.path,
        '/admin/giveaways/contest%2Fid/banner-correction',
      );
      expect(request.headers['Idempotency-Key'], key);
      expect(_bodyOf(request), {
        'revision': 8,
        'bannerMessage': r'Corrected: win US$50 + 5,000 Bara coins.',
        'reason': 'Corrected end-user wording without changing material terms.',
      });
    });

    test('admin create sends its UUID idempotency header', () async {
      final client = _FakeHttpClient([const _Scripted(201, '{}')]);
      final api = BackendApiService(httpClient: client);
      const key = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
      const body = <String, dynamic>{'slug': 'fall-referrals'};

      await api.createAdminGiveaway(
        identityToken: 'tok',
        idempotencyKey: key,
        body: body,
      );

      final request = client.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.path, '/admin/giveaways');
      expect(request.headers['Idempotency-Key'], key);
      expect(_bodyOf(request), body);
    });

    test('contest capability is present in every transport request', () async {
      final client = _FakeHttpClient([const _Scripted(200, '{}')]);
      final api = BackendApiService(httpClient: client);
      await api.fetchCurrentGiveaway(identityToken: 'tok');
      expect(
        client.requests.single.headers['X-Client-Features']!.split(','),
        contains('referral_contest_v1'),
      );
    });
  });

  // Batch 2026-08-09 item 10. The sectioned admin hub must not change what a
  // SHIPPED admin build asks for: an absent `sections` param is what makes the
  // backend run today's query set and nothing more.
  group('GET /admin/stats sections', () {
    test('no sections -> the bare legacy path, no query string', () async {
      final client = _FakeHttpClient([const _Scripted(200, '{"stats":{}}')]);
      final api = BackendApiService(httpClient: client);

      await api.fetchAdminStats(identityToken: 'tok');

      final request = client.requests.single;
      expect(request.uri.path, '/admin/stats');
      expect(request.uri.hasQuery, isFalse);
    });

    test('sections are sent as one comma-joined param', () async {
      final client = _FakeHttpClient([const _Scripted(200, '{"stats":{}}')]);
      final api = BackendApiService(httpClient: client);

      await api.fetchAdminStats(
        identityToken: 'tok',
        sections: const ['economy', 'ads'],
      );

      final request = client.requests.single;
      expect(request.uri.path, '/admin/stats');
      expect(request.uri.queryParameters['sections'], 'economy,ads');
    });

    test('a response without the requested block is not an error', () async {
      // An older backend ignores `sections` entirely. The caller must get the
      // legacy payload back, not an exception.
      final client = _FakeHttpClient([
        const _Scripted(200, '{"stats":{"users":{"total":3}}}'),
      ]);
      final api = BackendApiService(httpClient: client);

      final stats = await api.fetchAdminStats(
        identityToken: 'tok',
        sections: const ['economy'],
      );

      expect(stats['users'], {'total': 3});
      expect(stats['coinEconomy'], isNull);
    });

    test(
      'one dashboard section sends its validated window separately',
      () async {
        final client = _FakeHttpClient([const _Scripted(200, '{"stats":{}}')]);
        final api = BackendApiService(httpClient: client);

        await api.fetchAdminStats(
          identityToken: 'tok',
          sections: const ['dashboard-engagement'],
          window: '90d',
        );

        final request = client.requests.single;
        expect(request.uri.path, '/admin/stats');
        expect(request.uri.queryParameters, {
          'sections': 'dashboard-engagement',
          'window': '90d',
        });
      },
    );
  });

  group('admin metrics telemetry wire contract', () {
    test('foreground sends only the locked session envelope', () async {
      final client = _FakeHttpClient([
        const _Scripted(202, '{"recorded":true}'),
      ]);
      final api = BackendApiService(httpClient: client);

      await api.sendAdminMetricsForeground(
        identityToken: 'tok',
        sessionId: '01JABCDEFGHJKMNPQRSTVWXYZ12',
        occurredAt: DateTime.utc(2026, 8, 18, 14, 58),
        appVersion: '2.4.0',
      );

      final request = client.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.path, '/analytics/foreground');
      expect(_bodyOf(request), {
        'sessionId': '01JABCDEFGHJKMNPQRSTVWXYZ12',
        'occurredAt': '2026-08-18T14:58:00.000Z',
        'appVersion': '2.4.0',
      });
    });

    test('notification open sends only the opaque public id', () async {
      final client = _FakeHttpClient([
        const _Scripted(202, '{"attributed":true}'),
      ]);
      final api = BackendApiService(httpClient: client);

      await api.sendAdminMetricsNotificationOpen(
        identityToken: 'tok',
        notificationId: '01JABCDEFGHJKMNPQRSTVWXYZ12',
      );

      final request = client.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.path, '/analytics/notification-open');
      expect(_bodyOf(request), {
        'notificationId': '01JABCDEFGHJKMNPQRSTVWXYZ12',
      });
    });
  });

  group('PATCH /admin/settings/home-service-banner', () {
    test(
      'uses the atomic pair and preserves the server settings envelope',
      () async {
        final client = _FakeHttpClient([
          const _Scripted(
            200,
            '{"settings":{"bannerAdsEnabled":true,'
            '"homeServiceBannerEnabled":true,'
            '"homeServiceBannerMessage":"Step syncs may be delayed."}}',
          ),
        ]);
        final api = BackendApiService(httpClient: client);

        final settings = await api.updateAdminHomeServiceBanner(
          identityToken: 'tok',
          enabled: true,
          message: 'Step syncs may be delayed.',
        );

        final request = client.requests.single;
        expect(request.method, 'PATCH');
        expect(request.uri.path, '/admin/settings/home-service-banner');
        expect(_bodyOf(request), {
          'enabled': true,
          'message': 'Step syncs may be delayed.',
        });
        expect(settings, {
          'bannerAdsEnabled': true,
          'homeServiceBannerEnabled': true,
          'homeServiceBannerMessage': 'Step syncs may be delayed.',
        });
      },
    );
  });

  group('PATCH /admin/settings', () {
    test(
      'sends only the bannerAdsEnabled setting and reads the envelope',
      () async {
        final client = _FakeHttpClient([
          const _Scripted(200, '{"settings":{"bannerAdsEnabled":false}}'),
        ]);
        final api = BackendApiService(httpClient: client);

        final settings = await api.updateAdminSettings(
          identityToken: 'tok',
          bannerAdsEnabled: false,
        );

        final request = client.requests.single;
        expect(request.method, 'PATCH');
        expect(request.uri.path, '/admin/settings');
        expect(_bodyOf(request), {'bannerAdsEnabled': false});
        expect(settings, {'bannerAdsEnabled': false});
      },
    );
  });

  group('/admin/settings/active-competition-limit', () {
    test('GET and PATCH consume the dedicated direct envelope exactly', () async {
      final client = _FakeHttpClient([
        const _Scripted(
          200,
          '{"activeCompetitionLimit":17,"minimum":1,"maximum":20,"updatedAt":null}',
        ),
        const _Scripted(
          200,
          '{"activeCompetitionLimit":16,"minimum":1,"maximum":20,"updatedAt":"2026-08-28T12:00:00.000Z"}',
        ),
      ]);
      final api = BackendApiService(httpClient: client);

      final loaded = await api.fetchAdminActiveCompetitionLimit(
        identityToken: 'tok',
      );
      final saved = await api.updateAdminActiveCompetitionLimit(
        identityToken: 'tok',
        activeCompetitionLimit: 16,
      );

      expect(client.requests[0].method, 'GET');
      expect(
        client.requests[0].uri.path,
        '/admin/settings/active-competition-limit',
      );
      expect(loaded['activeCompetitionLimit'], 17);
      expect(client.requests[1].method, 'PATCH');
      expect(
        client.requests[1].uri.path,
        '/admin/settings/active-competition-limit',
      );
      expect(_bodyOf(client.requests[1]), {'activeCompetitionLimit': 16});
      expect(saved['activeCompetitionLimit'], 16);
      expect(saved['maximum'], 20);
    });
  });

  group('PATCH /admin/powerup-shop/items/:itemId', () {
    test('sends ONLY the keys that were provided', () async {
      final client = _FakeHttpClient([
        const _Scripted(
          200,
          '{"item":{"id":"i1","sku":"S","name":"N",'
          '"powerupType":"LEECH","priceCoins":300,"active":true,'
          '"testOnly":false,"sortOrder":4}}',
        ),
      ]);
      final api = BackendApiService(httpClient: client);

      await api.updateAdminPowerupShopItem(
        identityToken: 'tok',
        itemId: 'item-leech',
        priceCoins: 300,
      );

      final request = client.requests.single;
      expect(request.method, 'PATCH');
      expect(request.uri.path, '/admin/powerup-shop/items/item-leech');
      // No null-valued keys: the backend rejects a non-integer priceCoins and
      // a non-boolean active/testOnly with a 400, so a JSON `null` for an
      // untouched field would be a self-inflicted failure.
      expect(_bodyOf(request), {'priceCoins': 300});
    });

    test('sends every provided key, including false booleans', () async {
      final client = _FakeHttpClient([
        const _Scripted(
          200,
          '{"item":{"id":"i1","sku":"S","name":"N",'
          '"powerupType":"LEECH","priceCoins":300,"active":false,'
          '"testOnly":false,"sortOrder":0}}',
        ),
      ]);
      final api = BackendApiService(httpClient: client);

      await api.updateAdminPowerupShopItem(
        identityToken: 'tok',
        itemId: 'i1',
        active: false,
        testOnly: false,
        sortOrder: 0,
      );

      // `false` and `0` are real values, not absences.
      expect(_bodyOf(client.requests.single), {
        'active': false,
        'testOnly': false,
        'sortOrder': 0,
      });
    });

    test(
      'refuses an all-null update instead of sending an empty body',
      () async {
        final client = _FakeHttpClient([const _Scripted(200, '{}')]);
        final api = BackendApiService(httpClient: client);

        await expectLater(
          api.updateAdminPowerupShopItem(identityToken: 'tok', itemId: 'i1'),
          throwsA(isA<ApiException>()),
        );
        // §5.1 requires >= 1 key; the request never leaves the device.
        expect(client.requests, isEmpty);
      },
    );
  });

  group('GET /admin/powerup-shop/items', () {
    test('404 -> null (old backend), not an exception', () async {
      final api = BackendApiService(
        httpClient: _FakeHttpClient([const _Scripted(404, '{"error":"nope"}')]),
      );
      expect(
        await api.fetchAdminPowerupShopItems(identityToken: 'tok'),
        isNull,
      );
    });

    test('skips catalog rows this build cannot render safely', () async {
      final api = BackendApiService(
        httpClient: _FakeHttpClient([
          const _Scripted(
            200,
            '{"items":['
            '{"id":"ok","sku":"S","name":"N","powerupType":"LEECH",'
            '"priceCoins":300,"active":true,"testOnly":false,"sortOrder":1},'
            '{"sku":"no-id","priceCoins":10},'
            '{"id":"no-price","sku":"S"}]}',
          ),
        ]),
      );

      final items = await api.fetchAdminPowerupShopItems(identityToken: 'tok');
      expect(items, hasLength(1));
      expect(items!.single.id, 'ok');
    });
  });

  group('GET /admin/balance-config', () {
    test('404 -> null so the editor can say "unsupported"', () async {
      final api = BackendApiService(
        httpClient: _FakeHttpClient([const _Scripted(404, '')]),
      );
      expect(await api.fetchAdminBalanceConfig(identityToken: 'tok'), isNull);
    });

    test('parses version, config and the bounds table', () async {
      final api = BackendApiService(
        httpClient: _FakeHttpClient([
          const _Scripted(
            200,
            '{"version":7,"config":{"schemaVersion":1},'
            '"note":"n","createdBy":"u","boundOverride":false,'
            '"createdAt":"2026-07-20T12:00:00.000Z",'
            '"bounds":{"dailyBox.streakCap":[7,90],"bad":"nope"}}',
          ),
        ]),
      );

      final config = await api.fetchAdminBalanceConfig(identityToken: 'tok');
      expect(config!.version, 7);
      expect(config.config['schemaVersion'], 1);
      expect(config.bounds['dailyBox.streakCap'], [7.0, 90.0]);
      // A malformed bound entry is dropped, not allowed to poison the table.
      expect(config.bounds.containsKey('bad'), isFalse);
    });
  });

  group('PUT /admin/balance-config', () {
    Future<BalanceConfigSaveResult> put(_Scripted script) {
      final api = BackendApiService(httpClient: _FakeHttpClient([script]));
      return api.saveAdminBalanceConfig(
        identityToken: 'tok',
        expectedVersion: 7,
        config: const {'schemaVersion': 1},
        note: 'why',
      );
    }

    test('sends expectedVersion, config, note and the ack flag', () async {
      final client = _FakeHttpClient([const _Scripted(201, '{"version":8}')]);
      final api = BackendApiService(httpClient: client);

      await api.saveAdminBalanceConfig(
        identityToken: 'tok',
        expectedVersion: 7,
        config: const {'schemaVersion': 1},
        note: 'raise coin ranges',
      );

      final request = client.requests.single;
      expect(request.method, 'PUT');
      expect(request.uri.path, '/admin/balance-config');
      expect(_bodyOf(request), {
        'expectedVersion': 7,
        'config': {'schemaVersion': 1},
        'note': 'raise coin ranges',
        'acknowledgeBoundWarnings': false,
      });
    });

    test(
      '409 -> conflict carrying currentVersion and the server config',
      () async {
        final result = await put(
          const _Scripted(
            409,
            '{"error":"stale_version","currentVersion":9,'
            '"config":{"schemaVersion":1,"dailyBox":{"streakCap":45}}}',
          ),
        );

        expect(result.status, BalanceConfigSaveStatus.conflict);
        expect(result.currentVersion, 9);
        expect((result.config!['dailyBox'] as Map)['streakCap'], 45);
      },
    );

    test('422 -> parsed bound warnings', () async {
      final result = await put(
        const _Scripted(
          422,
          '{"error":"bound_warnings","warnings":['
          '{"path":"dailyBox.streakCap","value":200,"bound":[7,90],'
          '"message":"out of range"}]}',
        ),
      );

      expect(result.status, BalanceConfigSaveStatus.boundWarnings);
      expect(result.warnings.single.path, 'dailyBox.streakCap');
      expect(result.warnings.single.bound, [7.0, 90.0]);
      expect(result.warnings.single.message, 'out of range');
    });

    test('422 with no readable warnings degrades to an error, never an '
        'acknowledge dialog with nothing to acknowledge', () async {
      final result = await put(
        const _Scripted(422, '{"error":"bound_warnings","warnings":[]}'),
      );
      expect(result.status, BalanceConfigSaveStatus.error);
    });

    test('400 hard validation is a terminal error, not overridable', () async {
      final result = await put(
        const _Scripted(400, '{"error":"positionOdds.first must sum to 1"}'),
      );
      expect(result.status, BalanceConfigSaveStatus.error);
      expect(result.message, contains('must sum to 1'));
    });

    test('201 reports the new version', () async {
      final result = await put(const _Scripted(201, '{"version":8}'));
      expect(result.status, BalanceConfigSaveStatus.saved);
      expect(result.version, 8);
    });
  });

  group('POST /admin/balance-config/rollback', () {
    test(
      'sends the target and expected versions and shares 409 semantics',
      () async {
        final client = _FakeHttpClient([
          const _Scripted(
            409,
            '{"error":"stale_version","currentVersion":11,'
            '"config":{"schemaVersion":1}}',
          ),
        ]);
        final api = BackendApiService(httpClient: client);

        final result = await api.rollbackAdminBalanceConfig(
          identityToken: 'tok',
          version: 6,
          expectedVersion: 8,
        );

        final request = client.requests.single;
        expect(request.method, 'POST');
        expect(request.uri.path, '/admin/balance-config/rollback');
        expect(_bodyOf(request), {'version': 6, 'expectedVersion': 8});
        expect(result.status, BalanceConfigSaveStatus.conflict);
        expect(result.currentVersion, 11);
      },
    );
  });

  group('GET /admin/balance-config/versions', () {
    test('an unreadable history is empty, never a crash', () async {
      final api = BackendApiService(
        httpClient: _FakeHttpClient([const _Scripted(500, 'not json')]),
      );
      expect(
        await api.fetchAdminBalanceConfigVersions(identityToken: 'tok'),
        isEmpty,
      );
    });

    test('parses rows and drops ones without a version', () async {
      final api = BackendApiService(
        httpClient: _FakeHttpClient([
          const _Scripted(
            200,
            '{"versions":['
            '{"version":7,"note":"n","active":true,"boundOverride":false},'
            '{"note":"no version"}]}',
          ),
        ]),
      );

      final versions = await api.fetchAdminBalanceConfigVersions(
        identityToken: 'tok',
      );
      expect(versions, hasLength(1));
      expect(versions.single.version, 7);
      expect(versions.single.active, isTrue);
    });
  });

  group('POST /inbox/read-all', () {
    test(
      'sends an empty body and parses the authoritative combined count',
      () async {
        final client = _FakeHttpClient([
          const _Scripted(
            200,
            '{"readAlertCount":7,"readThreadCount":2,"unreadCount":1,"totalUnreadCount":3}',
          ),
        ]);
        final api = BackendApiService(httpClient: client);

        final result = await api.markInboxReadAll(identityToken: 'tok');

        final request = client.requests.single;
        expect(request.method, 'POST');
        expect(request.uri.path, '/inbox/read-all');
        expect(_bodyOf(request), isEmpty);
        expect(result.readAlertCount, 7);
        expect(result.readThreadCount, 2);
        expect(result.unreadCount, 1);
        expect(result.totalUnreadCount, 3);
      },
    );

    test(
      'rejects a missing or malformed totalUnreadCount without a fallback',
      () async {
        for (final body in <String>[
          '{"unreadCount":0}',
          '{"totalUnreadCount":-1}',
          '{"totalUnreadCount":1.5}',
          '{"totalUnreadCount":"0"}',
          '[]',
        ]) {
          final api = BackendApiService(
            httpClient: _FakeHttpClient([_Scripted(200, body)]),
          );

          await expectLater(
            api.markInboxReadAll(identityToken: 'tok'),
            throwsA(isA<ApiException>()),
            reason: body,
          );
        }
      },
    );
  });
}
