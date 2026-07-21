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
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
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
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
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
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
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

  group('PATCH /admin/powerup-shop/items/:itemId', () {
    test('sends ONLY the keys that were provided', () async {
      final client = _FakeHttpClient([
        const _Scripted(200, '{"item":{"id":"i1","sku":"S","name":"N",'
            '"powerupType":"LEECH","priceCoins":300,"active":true,'
            '"testOnly":false,"sortOrder":4}}'),
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
        const _Scripted(200, '{"item":{"id":"i1","sku":"S","name":"N",'
            '"powerupType":"LEECH","priceCoins":300,"active":false,'
            '"testOnly":false,"sortOrder":0}}'),
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

    test('refuses an all-null update instead of sending an empty body', () async {
      final client = _FakeHttpClient([const _Scripted(200, '{}')]);
      final api = BackendApiService(httpClient: client);

      await expectLater(
        api.updateAdminPowerupShopItem(identityToken: 'tok', itemId: 'i1'),
        throwsA(isA<ApiException>()),
      );
      // §5.1 requires >= 1 key; the request never leaves the device.
      expect(client.requests, isEmpty);
    });
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
          const _Scripted(200, '{"items":['
              '{"id":"ok","sku":"S","name":"N","powerupType":"LEECH",'
              '"priceCoins":300,"active":true,"testOnly":false,"sortOrder":1},'
              '{"sku":"no-id","priceCoins":10},'
              '{"id":"no-price","sku":"S"}]}'),
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
          const _Scripted(200, '{"version":7,"config":{"schemaVersion":1},'
              '"note":"n","createdBy":"u","boundOverride":false,'
              '"createdAt":"2026-07-20T12:00:00.000Z",'
              '"bounds":{"dailyBox.streakCap":[7,90],"bad":"nope"}}'),
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

    test('409 -> conflict carrying currentVersion and the server config',
        () async {
      final result = await put(
        const _Scripted(409, '{"error":"stale_version","currentVersion":9,'
            '"config":{"schemaVersion":1,"dailyBox":{"streakCap":45}}}'),
      );

      expect(result.status, BalanceConfigSaveStatus.conflict);
      expect(result.currentVersion, 9);
      expect((result.config!['dailyBox'] as Map)['streakCap'], 45);
    });

    test('422 -> parsed bound warnings', () async {
      final result = await put(
        const _Scripted(422, '{"error":"bound_warnings","warnings":['
            '{"path":"dailyBox.streakCap","value":200,"bound":[7,90],'
            '"message":"out of range"}]}'),
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
    test('sends the target and expected versions and shares 409 semantics',
        () async {
      final client = _FakeHttpClient([
        const _Scripted(409, '{"error":"stale_version","currentVersion":11,'
            '"config":{"schemaVersion":1}}'),
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
    });
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
          const _Scripted(200, '{"versions":['
              '{"version":7,"note":"n","active":true,"boundOverride":false},'
              '{"note":"no version"}]}'),
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
}
