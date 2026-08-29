import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/loadable.dart';
import 'package:step_tracker/screens/tabs/races_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';

class _FavoriteApi extends BackendApiService {
  final List<(String, bool)> raceCalls = [];
  final List<(String, bool)> tournamentCalls = [];
  bool failTournamentFavorite = false;

  @override
  Future<Map<String, dynamic>> updateRaceFavorite({
    required String identityToken,
    required String raceId,
    required bool favorite,
  }) async {
    raceCalls.add((raceId, favorite));
    return {
      'raceId': raceId,
      'isFavorite': favorite,
      'favoritedAt': favorite ? '2026-08-29T14:00:00.000Z' : null,
    };
  }

  @override
  Future<Map<String, dynamic>> updateTournamentFavorite({
    required String identityToken,
    required String tournamentId,
    required bool favorite,
  }) async {
    tournamentCalls.add((tournamentId, favorite));
    if (failTournamentFavorite) {
      throw const ApiException('Could not update favorite. Try again.');
    }
    return {
      'tournamentId': tournamentId,
      'isFavorite': favorite,
      'favoritedAt': favorite ? '2026-08-29T14:01:00.000Z' : null,
    };
  }
}

class _DeferredRaceFavoriteApi extends _FavoriteApi {
  final result = Completer<Map<String, dynamic>>();
  bool _defer = true;

  @override
  Future<Map<String, dynamic>> updateRaceFavorite({
    required String identityToken,
    required String raceId,
    required bool favorite,
  }) {
    raceCalls.add((raceId, favorite));
    if (_defer) {
      _defer = false;
      return result.future;
    }
    return Future.value({
      'raceId': raceId,
      'isFavorite': favorite,
      'favoritedAt': favorite ? '2026-08-29T14:00:00.000Z' : null,
    });
  }
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Map<String, dynamic> _race(
  String id, {
  String status = 'ACTIVE',
  bool team = false,
  bool favorite = false,
  String? endsAt,
}) => {
  'id': id,
  'name': id,
  'status': status,
  'myStatus': 'ACCEPTED',
  'maxDurationDays': 7,
  'participantCount': 2,
  'isTeamRace': team,
  'endsAt': endsAt ?? '2026-09-05T00:00:00.000Z',
  'isFavorite': favorite,
};

Map<String, dynamic> _tournament(
  String id, {
  String status = 'ACTIVE',
  bool favorite = false,
}) => {
  'id': id,
  'name': id,
  'status': status,
  'myStatus': 'ACCEPTED',
  'bracketSize': 8,
  'currentRound': status == 'ACTIVE' ? 1 : 0,
  'isFavorite': favorite,
  if (status == 'ACTIVE') 'myCurrentMatch': const {'raceId': 'match-1'},
};

Future<void> _pump(
  WidgetTester tester, {
  required Map<String, dynamic> data,
  BackendApiService? api,
  GlobalKey? tutorialCardKey,
  GlobalKey? tutorialBoxKey,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = const Size(430, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppThemeData.light(),
      home: Scaffold(
        body: RacesTab(
          authService: await _auth(),
          racesState: Loadable.success(data),
          friendsSteps: const [],
          onRacesChanged: () async {},
          backendApiService: api,
          tutorialCardKey: tutorialCardKey,
          tutorialBoxKey: tutorialBoxKey,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (call) async => 'America/New_York',
        );
  });

  testWidgets('pinned section renders mixed groups before invites and pills', (
    tester,
  ) async {
    await _pump(
      tester,
      api: _FavoriteApi(),
      data: {
        'active': [
          _race(
            'classic-active',
            favorite: true,
            endsAt: '2026-09-02T00:00:00Z',
          ),
          _race('team-active', team: true, favorite: true),
        ],
        'pending': [
          _race('classic-pending', status: 'PENDING', favorite: true),
        ],
        'completed': const [],
        'tournaments': [_tournament('tournament-active', favorite: true)],
      },
    );

    expect(find.byKey(const Key('pinned-section-header')), findsOneWidget);
    expect(find.byKey(const Key('pinned-group-classic')), findsOneWidget);
    expect(find.byKey(const Key('pinned-group-teams')), findsOneWidget);
    expect(find.byKey(const Key('pinned-group-tournaments')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('pinned-group-classic'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('personal-state-active'))).dy,
      ),
    );
    expect(
      find.byKey(const Key('pinned-race-row-classic-active')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('pinned-race-row-team-active')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('pinned-tournament-row-tournament-active')),
      findsOneWidget,
    );
  });

  testWidgets('empty pinned groups and section emit no spacer content', (
    tester,
  ) async {
    await _pump(
      tester,
      data: {
        'active': [_race('not-pinned')],
        'pending': const [],
        'completed': const [],
        'tournaments': [
          _tournament('malformed-favorite', favorite: false)
            ..['isFavorite'] = 'true',
        ],
      },
    );
    expect(find.byKey(const Key('pinned-section-header')), findsNothing);
    expect(find.byKey(const Key('pinned-group-classic')), findsNothing);
    expect(find.byKey(const Key('pinned-group-teams')), findsNothing);
    expect(find.byKey(const Key('pinned-group-tournaments')), findsNothing);
    expect(find.text('not-pinned'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pinned ordering does not reorder the originating active shelf', (
    tester,
  ) async {
    await _pump(
      tester,
      data: {
        'active': [
          _race('shelf-first', endsAt: '2026-09-01T00:00:00Z'),
          _race('shelf-second', endsAt: '2026-09-03T00:00:00Z'),
        ],
        'pending': const [],
        'completed': const [],
        'tournaments': const [],
      },
    );
    final shelfFirst = find.byKey(const Key('race-card-header-shelf-first'));
    final shelfSecond = find.byKey(const Key('race-card-header-shelf-second'));
    expect(shelfFirst, findsOneWidget);
    expect(shelfSecond, findsOneWidget);
    expect(
      tester.getTopLeft(shelfFirst).dy,
      lessThan(tester.getTopLeft(shelfSecond).dy),
    );
  });

  testWidgets('ordinary pin updates both copies and coalesces repeated taps', (
    tester,
  ) async {
    final api = _DeferredRaceFavoriteApi();
    await _pump(
      tester,
      api: api,
      data: {
        'active': [_race('race-1')],
        'pending': const [],
        'completed': const [],
      },
    );

    final shelfStar = find.byKey(const Key('race-favorite-race-1'));
    await tester.tap(shelfStar);
    await tester.tap(shelfStar, warnIfMissed: false);
    await tester.pump();
    expect(api.raceCalls, [('race-1', true)]);
    api.result.complete({
      'raceId': 'race-1',
      'isFavorite': true,
      'favoritedAt': '2026-08-29T14:00:00.000Z',
    });
    await tester.pump();
    expect(find.byKey(const Key('pinned-section-header')), findsOneWidget);
    expect(find.byKey(const Key('pinned-race-row-race-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('pinned-race-favorite-race-1')));
    await tester.pump();
    expect(api.raceCalls, [('race-1', true), ('race-1', false)]);
    expect(find.byKey(const Key('pinned-section-header')), findsNothing);
    expect(
      tester
          .getSemantics(shelfStar)
          .getSemanticsData()
          .flagsCollection
          .isToggled,
      Tristate.isFalse,
    );
  });

  testWidgets('tournament pin uses its own API and rolls back on failure', (
    tester,
  ) async {
    final api = _FavoriteApi();
    await _pump(
      tester,
      api: api,
      data: {
        'active': const [],
        'pending': const [],
        'completed': const [],
        'tournaments': [_tournament('tournament-1')],
      },
    );

    await tester.tap(find.byKey(const Key('tournament-favorite-tournament-1')));
    await tester.pump();
    expect(api.tournamentCalls, [('tournament-1', true)]);
    expect(find.byKey(const Key('pinned-section-header')), findsOneWidget);

    api.failTournamentFavorite = true;
    await tester.tap(
      find.byKey(const Key('pinned-tournament-favorite-tournament-1')),
    );
    await tester.pump();
    expect(find.byKey(const Key('pinned-section-header')), findsOneWidget);
    expect(find.text('Could not update favorite. Try again.'), findsOneWidget);
  });

  testWidgets('tutorial anchors stay on the original shelf card', (
    tester,
  ) async {
    final cardKey = GlobalKey();
    final boxKey = GlobalKey();
    await _pump(
      tester,
      data: {
        'active': [_race('tutorial-race', favorite: true)],
        'pending': const [],
        'completed': const [],
        'tournaments': const [],
      },
      tutorialCardKey: cardKey,
      tutorialBoxKey: boxKey,
    );
    expect(find.byKey(cardKey), findsOneWidget);
    expect(find.byKey(boxKey), findsOneWidget);
    expect(
      find.byKey(const Key('pinned-race-row-tutorial-race')),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byKey(cardKey),
        matching: find.byKey(const Key('pinned-race-row-tutorial-race')),
      ),
      findsNothing,
    );
  });

  testWidgets('missing favorite fields remain unpinned in narrow night mode', (
    tester,
  ) async {
    final race = _race('missing-race')..remove('isFavorite');
    final tournament = _tournament('missing-tournament')..remove('isFavorite');
    await _pump(
      tester,
      theme: AppThemeData.night(),
      data: {
        'active': [race],
        'pending': const [],
        'completed': const [],
        'tournaments': [tournament],
      },
    );
    expect(find.byKey(const Key('pinned-section-header')), findsNothing);
    expect(find.text('missing-race'), findsOneWidget);
    expect(
      find.byKey(const Key('tournament-row-missing-tournament')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  test('tournament favorite API sends the exact PUT contract', () async {
    final http = _FakeHttpClient(
      responseBody:
          '{"tournamentId":"tournament-1","isFavorite":true,"favoritedAt":"2026-08-29T14:01:00.000Z"}',
    );
    final api = BackendApiService(httpClient: http);
    final payload = await api.updateTournamentFavorite(
      identityToken: 'token',
      tournamentId: 'tournament-1',
      favorite: true,
    );
    expect(http.lastRequest.method, 'PUT');
    expect(
      http.lastRequest.uri.path,
      endsWith('/tournaments/tournament-1/favorite'),
    );
    expect(http.lastRequest.jsonBody, {'favorite': true});
    expect(payload['tournamentId'], 'tournament-1');
    expect(payload['isFavorite'], isTrue);
    expect(payload['favoritedAt'], '2026-08-29T14:01:00.000Z');
  });

  test(
    'only a plain 404 marks tournament favorite route unsupported',
    () async {
      final plain404 = BackendApiService(
        httpClient: _FakeHttpClient(
          statusCode: 404,
          responseBody: '{"error":"Not found"}',
        ),
      );
      await expectLater(
        plain404.updateTournamentFavorite(
          identityToken: 'token',
          tournamentId: 'tournament-1',
          favorite: true,
        ),
        throwsA(isA<ApiException>()),
      );
      expect(plain404.tournamentFavoriteSupport, EndpointSupport.unsupported);

      final coded404 = BackendApiService(
        httpClient: _FakeHttpClient(
          statusCode: 404,
          responseBody: '{"error":"Not a member","code":"NOT_MEMBER"}',
        ),
      );
      await expectLater(
        coded404.updateTournamentFavorite(
          identityToken: 'token',
          tournamentId: 'tournament-1',
          favorite: true,
        ),
        throwsA(isA<ApiException>()),
      );
      expect(coded404.tournamentFavoriteSupport, EndpointSupport.unknown);
    },
  );
}

class _CapturedRequest {
  _CapturedRequest(this.method, this.uri);

  final String method;
  final Uri uri;
  final StringBuffer body = StringBuffer();

  Map<String, dynamic> get jsonBody =>
      jsonDecode(body.toString()) as Map<String, dynamic>;
}

class _FakeHeaders implements HttpHeaders {
  @override
  ContentType? contentType;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse(this.statusCode, this.body);

  @override
  final int statusCode;
  final String body;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.fromIterable([utf8.encode(body)]).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this.captured, this.response);

  final _CapturedRequest captured;
  final _FakeResponse response;

  @override
  final HttpHeaders headers = _FakeHeaders();

  @override
  void write(Object? object) => captured.body.write(object);

  @override
  Future<HttpClientResponse> close() async => response;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient({this.statusCode = 200, this.responseBody = '{}'});

  final int statusCode;
  final String responseBody;
  final requests = <_CapturedRequest>[];

  @override
  Duration? connectionTimeout;

  _CapturedRequest get lastRequest => requests.last;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final captured = _CapturedRequest(method, url);
    requests.add(captured);
    return _FakeRequest(captured, _FakeResponse(statusCode, responseBody));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
