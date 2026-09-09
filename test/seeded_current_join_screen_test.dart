import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:step_tracker/screens/public_races_screen.dart';
import 'package:step_tracker/services/race_detail_navigation.dart';
import 'package:step_tracker/services/interstitial_ad_service.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/featured_race_card.dart';

final _start = DateTime.now().toUtc().subtract(const Duration(hours: 1));
final _end = _start.add(const Duration(days: 1));
Map<String, dynamic> _projection({
  String state = 'JOINABLE',
  DateTime? start,
  DateTime? end,
}) => {
  'version': 1,
  'state': state,
  'windowStart': (start ?? _start).toIso8601String(),
  'windowEnd': (end ?? _end).toIso8601String(),
  'raceId': state == 'JOINED' ? 'owned-race' : null,
  'participantCount': state == 'JOINED' ? 3 : null,
  'scoringStartsAt': state == 'JOINED' ? _start.toIso8601String() : null,
};
Map<String, dynamic> _card({String seed = 'DAILY_10K'}) => {
  'seedKind': seed,
  'name': 'Challenge',
  'bucketPrivate': true,
  'myStatus': 'ELECTED',
  'raceId': null,
  'currentJoin': _projection(),
  'endsAt': _end.toIso8601String(),
  'isFull': true,
};
Map<String, dynamic> _receipt({String seed = 'DAILY_10K'}) => {
  'joined': true,
  'alreadyJoined': false,
  'seedKind': seed,
  'raceId': 'owned-race',
  'participantId': 'participant',
  'windowStart': _start.toIso8601String(),
  'windowEnd': _end.toIso8601String(),
  'joinedAt': DateTime.now().toUtc().toIso8601String(),
  'scoringStartsAt': DateTime.now().toUtc().toIso8601String(),
  'raceStatus': 'ACTIVE',
};

class _Auth extends AuthService {
  String? account = 'user-1';
  @override
  String? get userId => account;
  @override
  String? get authToken => account == null ? null : 'token-$account';
  void switchTo(String? value) {
    account = value;
    notifyListeners();
  }
}

class _Api extends BackendApiService {
  List<Map<String, dynamic>> cards = [_card()];
  Future<Map<String, dynamic>> Function()? fetch;
  Future<Map<String, dynamic>> Function(String, String)? join;
  final requests = <Map<String, String>>[];
  int publicJoins = 0;
  int upcomingJoins = 0;
  @override
  Future<Map<String, dynamic>> fetchPublicRaceBrowser({
    required String identityToken,
  }) async {
    if (fetch != null) return fetch!();
    return {
      'contract': 'public-race-browser-v1',
      'resolved': {'featuredRaces': true, 'tournaments': true, 'mine': true},
      'races': [],
      'featuredRaces': cards,
      'tournaments': {'featured': [], 'public': [], 'mine': []},
    };
  }

  // This method is deliberately present before the production method: the red
  // screen test proves the old screen never uses current admission.
  @override
  Future<Map<String, dynamic>> joinCurrentSeededChallenge({
    required String identityToken,
    required String seedKind,
    required String requestId,
  }) async {
    requests.add({'seed': seedKind, 'id': requestId, 'token': identityToken});
    return join == null ? _receipt(seed: seedKind) : join!(seedKind, requestId);
  }

  @override
  Future<Map<String, dynamic>> assignSeededRaceBucket({
    required String identityToken,
    required String seedKind,
  }) async {
    upcomingJoins++;
    return {'elected': true};
  }

  @override
  Future<Map<String, dynamic>> joinPublicRace({
    required String identityToken,
    required String raceId,
    bool onboarding = false,
  }) async {
    publicJoins++;
    return {};
  }
}

class _Navigator extends Fake implements RaceDetailNavigator {
  final opened = <String>[];
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #push) {
      opened.add(invocation.namedArguments[#raceId] as String);
      return Future.value(RaceDetailRouteResult.backExit);
    }
    return super.noSuchMethod(invocation);
  }
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _screen(
  WidgetTester tester,
  _Api api, {
  _Auth? auth,
  RaceDetailNavigator? navigator,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: PublicRacesScreen(
        authService: auth ?? _Auth(),
        backendApiService: api,
        raceDetailNavigator: navigator,
      ),
    ),
  );
  await _frames(tester);
}

Future<void> _refresh(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await _frames(tester);
}

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final seed in ['DAILY_10K', 'WEEKLY_50K']) {
      testWidgets(
        '$platform $seed current Join overrides future election/full and loading becomes VIEW without navigation',
        (tester) async {
          final pending = Completer<Map<String, dynamic>>();
          final api = _Api()
            ..cards = [_card(seed: seed)]
            ..join = (_, _) => pending.future;
          await _screen(tester, api);
          expect(find.text('JOIN'), findsOneWidget);
          await tester.tap(find.text('JOIN'));
          await _frames(tester);
          expect(find.text('JOINING…'), findsOneWidget);
          await tester.tap(find.text('JOINING…'));
          expect(api.requests, hasLength(1));
          expect(
            api.requests.single['id'],
            matches(
              RegExp(
                r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
              ),
            ),
          );
          pending.complete(_receipt(seed: seed));
          await _frames(tester);
          expect(find.text('VIEW'), findsOneWidget);
          expect(find.byType(PublicRacesScreen), findsOneWidget);
          expect(api.upcomingJoins, 0);
          expect(api.publicJoins, 0);
          expect(find.text('0 racing'), findsNothing);
        },
        variant: TargetPlatformVariant({platform}),
      );
    }
  }
  testWidgets(
    'network retry reuses UUID and committed Join survives failed refresh',
    (tester) async {
      final api = _Api();
      var attempts = 0;
      api.join = (_, _) async {
        if (attempts++ == 0) throw TimeoutException('lost response');
        api.fetch = () async => throw const ApiException('Offline');
        return _receipt();
      };
      await _screen(tester, api);
      await tester.tap(find.text('JOIN'));
      await _frames(tester);
      expect(find.text('JOIN'), findsOneWidget);
      await tester.tap(find.text('JOIN'));
      await _frames(tester);
      expect(api.requests, hasLength(2));
      expect(api.requests[0]['id'], api.requests[1]['id']);
      expect(find.text('VIEW'), findsOneWidget);
    },
  );
  testWidgets('malformed success reconciles without false success', (
    tester,
  ) async {
    final api = _Api()
      ..join = (_, _) async => {'joined': true, 'raceId': 'owned-race'};
    await _screen(tester, api);
    await tester.tap(find.text('JOIN'));
    await _frames(tester);
    expect(find.text('VIEW'), findsNothing);
    expect(find.text("You're in!"), findsNothing);
    expect(find.text('JOIN'), findsOneWidget);
  });
  for (final bad in [
    null,
    {},
    {'version': 2, 'state': 'JOINABLE'},
    {..._projection(), 'state': 'FUTURE'},
    {..._projection(), 'windowEnd': 42},
    {..._projection(state: 'JOINED'), 'raceId': null},
  ]) {
    testWidgets(
      'malformed projection $bad never sends private public/upcoming writes',
      (tester) async {
        final api = _Api()
          ..cards = [
            {..._card(), 'myStatus': null, 'currentJoin': bad},
          ];
        await _screen(tester, api);
        expect(find.text('UNAVAILABLE'), findsOneWidget);
        expect(find.text('JOIN'), findsNothing);
        expect(api.requests, isEmpty);
        expect(api.upcomingJoins, 0);
        expect(api.publicJoins, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('forfeit and unavailable projections cannot rejoin', (
    tester,
  ) async {
    final api = _Api()
      ..cards = [
        {..._card(), 'currentJoin': _projection(state: 'FORFEITED')},
      ];
    await _screen(tester, api);
    expect(find.text('JOIN'), findsNothing);
    api.cards = [
      {
        ..._card(),
        'currentJoin': {
          ..._projection(state: 'UNAVAILABLE'),
          'reason': 'ACCOUNT_INELIGIBLE',
        },
      },
    ];
    await _refresh(tester);
    expect(find.text('UNAVAILABLE'), findsOneWidget);
    expect(api.requests, isEmpty);
  });
  testWidgets('account change ignores in-flight Join and old discovery', (
    tester,
  ) async {
    final auth = _Auth();
    final pending = Completer<Map<String, dynamic>>();
    final api = _Api()..join = (_, _) => pending.future;
    await _screen(tester, api, auth: auth);
    await tester.tap(find.text('JOIN'));
    await _frames(tester);
    auth.switchTo('user-2');
    await _frames(tester);
    pending.complete(_receipt());
    await _frames(tester);
    expect(find.text('VIEW'), findsNothing);
    expect(find.text('JOIN'), findsOneWidget);
    api.join = (_, _) async => _receipt();
    await tester.tap(find.text('JOIN'));
    await _frames(tester);
    expect(api.requests[0]['id'], isNot(api.requests[1]['id']));
    expect(api.requests[1]['token'], 'token-user-2');
  });
  testWidgets('changed window ignores old receipt and generates new attempt', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>>();
    final api = _Api()..join = (_, _) => pending.future;
    await _screen(tester, api);
    await tester.tap(find.text('JOIN'));
    await _frames(tester);
    final newStart = _start.add(const Duration(days: 1));
    final newEnd = _end.add(const Duration(days: 1));
    api.cards = [
      {..._card(), 'currentJoin': _projection(start: newStart, end: newEnd)},
    ];
    await _refresh(tester);
    pending.complete(_receipt());
    await _frames(tester);
    expect(find.text('VIEW'), findsNothing);
    expect(find.text('JOIN'), findsOneWidget);
    api.join = (_, _) async => {'bad': true};
    await tester.tap(find.text('JOIN'));
    await _frames(tester);
    expect(api.requests[0]['id'], isNot(api.requests[1]['id']));
  });
  testWidgets('completed receipt gives factual feedback without current VIEW', (
    tester,
  ) async {
    final api = _Api()
      ..join = (_, _) async => {..._receipt(), 'raceStatus': 'COMPLETED'};
    await _screen(tester, api);
    await tester.tap(find.text('JOIN'));
    await _frames(tester);
    expect(find.text('VIEW'), findsNothing);
    expect(find.text("You're in!"), findsNothing);
    expect(
      find.text('That challenge has ended. Current challenges refreshed.'),
      findsOneWidget,
    );
  });
  testWidgets('dispose ignores outstanding Join', (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    final api = _Api()..join = (_, _) => pending.future;
    await _screen(tester, api);
    await tester.tap(find.text('JOIN'));
    await _frames(tester);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    pending.complete(_receipt());
    await _frames(tester);
    expect(tester.takeException(), isNull);
  });
  for (final already in [false, true]) {
    testWidgets(
      'VIEW opens own assigned race only after deliberate tap (already $already)',
      (tester) async {
        final navigator = _Navigator();
        final api = _Api();
        if (already) {
          api.cards = [
            {..._card(), 'currentJoin': _projection(state: 'JOINED')},
          ];
        }
        await _screen(tester, api, navigator: navigator);
        if (!already) {
          await tester.tap(find.text('JOIN'));
          await _frames(tester);
        }
        expect(navigator.opened, isEmpty);
        await tester.tap(find.text('VIEW'));
        await _frames(tester);
        expect(navigator.opened, ['owned-race']);
        expect(api.requests, hasLength(already ? 0 : 1));
      },
    );
  }
  testWidgets('newer discovery generation excludes late prior response', (
    tester,
  ) async {
    final api = _Api();
    await _screen(tester, api);
    final stale = Completer<Map<String, dynamic>>();
    api.fetch = () => stale.future;
    await _refresh(tester);
    api.fetch = null;
    api.cards = [
      {..._card(), 'currentJoin': _projection(state: 'JOINED')},
    ];
    await _refresh(tester);
    expect(find.text('VIEW'), findsOneWidget);
    stale.complete({
      'contract': 'public-race-browser-v1',
      'resolved': {'featuredRaces': true, 'tournaments': true, 'mine': true},
      'races': [],
      'featuredRaces': [_card()],
      'tournaments': {'featured': [], 'public': [], 'mine': []},
    });
    await _frames(tester);
    expect(find.text('VIEW'), findsOneWidget);
    expect(find.text('JOIN'), findsNothing);
  });
  testWidgets('logout clears cards before a stale discovery response arrives', (
    tester,
  ) async {
    final auth = _Auth();
    final api = _Api();
    await _screen(tester, api, auth: auth);
    final stale = Completer<Map<String, dynamic>>();
    api.fetch = () => stale.future;
    await _refresh(tester);
    auth.switchTo(null);
    await _frames(tester);
    stale.complete({
      'contract': 'public-race-browser-v1',
      'resolved': {'featuredRaces': true, 'tournaments': true, 'mine': true},
      'races': [],
      'featuredRaces': [
        {..._card(), 'currentJoin': _projection(state: 'JOINED')},
      ],
      'tournaments': {'featured': [], 'public': [], 'mine': []},
    });
    await _frames(tester);
    expect(find.byType(FeaturedRaceCard), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'known forfeit received during Join cannot be overwritten by its older receipt',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      final api = _Api()..join = (_, _) => pending.future;
      await _screen(tester, api);
      await tester.tap(find.text('JOIN'));
      await _frames(tester);
      api.cards = [
        {..._card(), 'currentJoin': _projection(state: 'FORFEITED')},
      ];
      await _refresh(tester);
      pending.complete(_receipt());
      await _frames(tester);
      expect(find.text('VIEW'), findsNothing);
      expect(find.text('JOIN'), findsNothing);
      expect(find.text("You're in!"), findsNothing);
    },
  );
  testWidgets(
    'unavailable refresh stays in the existing card and never writes',
    (tester) async {
      final api = _Api()
        ..cards = [
          {..._card(), 'myStatus': null, 'currentJoin': null},
        ];
      await _screen(tester, api);
      await tester.tap(find.text('UNAVAILABLE'));
      await _frames(tester);
      expect(
        find.text('Current challenge unavailable. Refreshing to check again.'),
        findsOneWidget,
      );
      expect(api.requests, isEmpty);
      expect(api.publicJoins, 0);
      expect(api.upcomingJoins, 0);
    },
  );
  testWidgets('committed Join survives an empty stale featured response', (
    tester,
  ) async {
    final api = _Api()..join = (_, _) async => _receipt();
    await _screen(tester, api);
    api.cards = [];
    await tester.tap(find.text('JOIN'));
    await _frames(tester);
    expect(find.text('VIEW'), findsOneWidget);
  });
  testWidgets(
    'server advancing the window during admission does not call an active race ended',
    (tester) async {
      final nextStart = _start.add(const Duration(days: 1));
      final nextEnd = _end.add(const Duration(days: 1));
      final api = _Api()
        ..join = (_, _) async => {
          ..._receipt(),
          'windowStart': nextStart.toIso8601String(),
          'windowEnd': nextEnd.toIso8601String(),
          'joinedAt': nextStart.toIso8601String(),
          'scoringStartsAt': nextStart.toIso8601String(),
        };
      await _screen(tester, api);
      await tester.tap(find.text('JOIN'));
      await _frames(tester);
      expect(
        find.text('Challenge timing changed. Refreshing your entry.'),
        findsOneWidget,
      );
      expect(
        find.text('That challenge has ended. Current challenges refreshed.'),
        findsNothing,
      );
    },
  );
  testWidgets(
    'replaced screen dependencies invalidate an in-flight old generation',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      final auth = _Auth();
      final oldApi = _Api()..join = (_, _) => pending.future;
      await _screen(tester, oldApi, auth: auth);
      await tester.tap(find.text('JOIN'));
      await _frames(tester);
      final newApi = _Api();
      await _screen(tester, newApi, auth: auth);
      pending.complete(_receipt());
      await _frames(tester);
      expect(find.text('VIEW'), findsNothing);
      expect(find.text('JOIN'), findsOneWidget);
      await tester.tap(find.text('JOIN'));
      await _frames(tester);
      expect(newApi.requests, hasLength(1));
    },
  );
  testWidgets(
    'a cached previous window cannot erase committed current membership',
    (tester) async {
      final api = _Api();
      await _screen(tester, api);
      await tester.tap(find.text('JOIN'));
      await _frames(tester);
      api.cards = [
        {
          ..._card(),
          'currentJoin': _projection(
            start: _start.subtract(const Duration(days: 1)),
            end: _end.subtract(const Duration(days: 1)),
          ),
        },
      ];
      await _refresh(tester);
      expect(find.text('VIEW'), findsOneWidget);
      expect(find.text('JOIN'), findsNothing);
    },
  );
  testWidgets(
    'LEGACY card with additive projection uses current admission, preserving old fields',
    (tester) async {
      final api = _Api()
        ..cards = [
          {
            ..._card(),
            'bucketPrivate': false,
            'raceId': 'legacy-public-id',
            'myStatus': null,
          },
        ];
      await _screen(tester, api);
      expect(find.text('JOIN'), findsOneWidget);
      await tester.tap(find.text('JOIN'));
      await _frames(tester);
      expect(api.requests, hasLength(1));
      expect(api.publicJoins, 0);
      expect(api.upcomingJoins, 0);
      expect(find.text('VIEW'), findsOneWidget);
    },
  );
  for (final projection in [
    null,
    {'version': 42, 'state': 'JOINABLE'},
  ]) {
    testWidgets(
      'LEGACY malformed-present $projection cannot fall through to public Join',
      (tester) async {
        final api = _Api()
          ..cards = [
            {
              ..._card(),
              'bucketPrivate': false,
              'raceId': 'legacy-public-id',
              'myStatus': null,
              'isFull': false,
              'currentJoin': projection,
            },
          ];
        await _screen(tester, api);
        expect(find.text('UNAVAILABLE'), findsOneWidget);
        expect(find.text('JOIN'), findsNothing);
        expect(api.publicJoins, 0);
        expect(api.upcomingJoins, 0);
      },
    );
  }
  testWidgets('LEGACY missing projection retains original public Join path', (
    tester,
  ) async {
    final card = {
      ..._card(),
      'bucketPrivate': false,
      'raceId': 'legacy-public-id',
      'myStatus': null,
      'isFull': false,
    }..remove('currentJoin');
    final api = _Api()..cards = [card];
    await _screen(tester, api);
    await tester.tap(find.text('JOIN'));
    await _frames(tester);
    expect(api.publicJoins, 1);
    expect(api.requests, isEmpty);
    expect(api.upcomingJoins, 0);
  });
  testWidgets('committed receipt does not borrow an old public group count', (
    tester,
  ) async {
    final api = _Api();
    await _screen(tester, api);
    await tester.tap(find.text('JOIN'));
    await _frames(tester);
    api.cards = [
      {
        ..._card(),
        'bucketPrivate': false,
        'raceId': 'other-public-race',
        'myStatus': 'ACCEPTED',
        'participantCount': 29,
      }..remove('currentJoin'),
    ];
    await _refresh(tester);
    expect(find.text('VIEW'), findsOneWidget);
    expect(find.text('29 racing'), findsNothing);
  });
  testWidgets('null optional card values remain readable', (tester) async {
    final api = _Api()
      ..cards = [
        {
          ..._card(),
          'name': 99,
          'finishReward': {42: 'bad', 'pool': 'bad'},
          'participantCount': 'bad',
        },
      ];
    await _screen(tester, api);
    expect(find.byType(FeaturedRaceCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
