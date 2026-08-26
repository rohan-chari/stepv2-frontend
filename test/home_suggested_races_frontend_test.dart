import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/home_race_suggestion.dart';
import 'package:step_tracker/models/loadable.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/screens/tabs/home_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

const _daily = <String, dynamic>{
  'kind': 'FEATURED_RACE',
  'id': 'daily',
  'seedKind': 'DAILY_10K',
  'name': 'Daily 10K',
  'status': 'ACTIVE',
  'endsAt': '2036-08-12T04:00:00.000Z',
  'participantCount': 42,
  'maxParticipants': 100,
  'isFull': false,
  'powerupsEnabled': true,
  'prizePool': null,
  'finishReward': null,
  'joinAction': 'JOIN',
};

const _public = <String, dynamic>{
  'kind': 'PUBLIC_RACE',
  'id': 'public',
  'name': 'Lunch Break Sprint',
  'status': 'PENDING',
  'maxDurationDays': 1,
  'endsAt': null,
  'startedAt': null,
  'participantCount': 3,
  'maxParticipants': 10,
  'buyInAmount': 0,
  'payoutPreset': 'TOP_HALF_GRADED',
  'powerupsEnabled': true,
  'prizePool': null,
  'isTeamRace': false,
  'teamSize': null,
  'teamAName': null,
  'teamBName': null,
  'teams': null,
  'joinAction': 'JOIN',
};

const _tournament = <String, dynamic>{
  'kind': 'TOURNAMENT',
  'id': 'tournament',
  'seedKind': 'DAILY_DASH',
  'name': 'Daily Dash',
  'status': 'PENDING',
  'bracketSize': 8,
  'matchupDurationDays': 1,
  'acceptedCount': 5,
  'buyInAmount': 0,
  'potCoins': 800,
  'prizePool': null,
  'powerupsEnabled': true,
  'powerupStepInterval': 2000,
  'createdAt': '2026-08-11T20:00:00.000Z',
  'joinAction': 'JOIN',
};

const _weeklyShowdownTournament = <String, dynamic>{
  'kind': 'TOURNAMENT',
  'id': 'weekly-showdown-tournament',
  'seedKind': 'WEEKLY_SHOWDOWN',
  'name': '8 Racer Tourney',
  'status': 'PENDING',
  'bracketSize': 8,
  'matchupDurationDays': 2,
  'acceptedCount': 3,
  'buyInAmount': 0,
  'potCoins': 0,
  'prizePool': {'coins': 800},
  'powerupsEnabled': false,
  'powerupStepInterval': null,
  'createdAt': '2026-08-11T20:00:00.000Z',
  'joinAction': 'JOIN',
};

class _Script {
  const _Script(this.status, this.body);
  final int status;
  final String body;
}

class _Headers implements HttpHeaders {
  final values = <String, String>{};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name] = value.toString();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.uri, this.script);
  @override
  final Uri uri;
  final _Script script;
  final _Headers headersImpl = _Headers();
  @override
  HttpHeaders get headers => headersImpl;
  @override
  Future<HttpClientResponse> close() async => _Response(script);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.script);
  final _Script script;
  @override
  int get statusCode => script.status;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(utf8.encode(script.body)).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Http extends Fake implements HttpClient {
  _Http(this.scripts);
  final List<_Script> scripts;
  final requests = <_Request>[];
  Duration? _connectionTimeout;
  @override
  set connectionTimeout(Duration? value) => _connectionTimeout = value;
  @override
  Duration? get connectionTimeout => _connectionTimeout;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final request = _Request(url, scripts.removeAt(0));
    requests.add(request);
    return request;
  }
}

class _Api extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchDailyRewardStatus({
    required String identityToken,
    required String localDate,
  }) async => const {'claimedToday': true};
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'identity',
    'auth_user_identifier': 'platform-user',
    'auth_session_token': 'session',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Walker',
    'auth_profile_photo_prompt_dismissed_at': '2026-08-01T00:00:00Z',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
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
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.3.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('HomeRaceSuggestion parser and merge store', () {
    test('strictly parses every kind and drops malformed required fields', () {
      expect(
        HomeRaceSuggestion.tryParse(_daily)?.kind,
        HomeRaceSuggestionKind.featuredRace,
      );
      expect(
        HomeRaceSuggestion.tryParse(_public)?.kind,
        HomeRaceSuggestionKind.publicRace,
      );
      expect(
        HomeRaceSuggestion.tryParse(_tournament)?.kind,
        HomeRaceSuggestionKind.tournament,
      );
      expect(
        HomeRaceSuggestion.tryParse({..._public, 'participantCount': null}),
        isNull,
      );
      expect(
        HomeRaceSuggestion.tryParse({..._daily, 'endsAt': 'nope'}),
        isNull,
      );
      expect(
        HomeRaceSuggestion.tryParse({..._tournament, 'joinable': true}),
        isNotNull,
      );
    });

    test(
      'partial merge replaces resolved categories and retains unresolved',
      () {
        final store = HomeSuggestedRacesStore();
        final first = store.beginRefresh();
        store.apply(
          first,
          HomeSuggestedRacesRefresh(
            featuredRaces: [HomeRaceSuggestion.tryParse(_daily)!],
            publicRaces: [HomeRaceSuggestion.tryParse(_public)!],
            tournaments: [HomeRaceSuggestion.tryParse(_tournament)!],
          ),
        );
        final second = store.beginRefresh();
        store.apply(
          second,
          const HomeSuggestedRacesRefresh(featuredRaces: [], tournaments: []),
        );
        expect(store.state.data!.map((e) => e.id), ['public']);
      },
    );

    test('stale generation and tombstoned joined card cannot resurrect', () {
      final store = HomeSuggestedRacesStore();
      final old = store.beginRefresh();
      final fresh = store.beginRefresh();
      store.apply(
        fresh,
        HomeSuggestedRacesRefresh(
          publicRaces: [HomeRaceSuggestion.tryParse(_public)!],
        ),
      );
      store.tombstone(HomeRaceSuggestion.tryParse(_public)!);
      expect(store.state.data, isEmpty);
      expect(
        store.apply(
          old,
          HomeSuggestedRacesRefresh(
            publicRaces: [HomeRaceSuggestion.tryParse(_public)!],
          ),
        ),
        isFalse,
      );
      final unresolved = store.beginRefresh();
      store.apply(unresolved, const HomeSuggestedRacesRefresh());
      expect(store.state.data, isEmpty);
    });

    test('ordered merge keeps the complete 1+1+4+4 category sequence', () {
      final store = HomeSuggestedRacesStore();
      final generation = store.beginRefresh();
      final daily = HomeRaceSuggestion.tryParse(_daily)!;
      final weekly = HomeRaceSuggestion.tryParse({
        ..._daily,
        'id': 'weekly',
        'seedKind': 'WEEKLY_50K',
        'name': 'Weekly 50K',
      })!;
      final public = List.generate(
        4,
        (index) =>
            HomeRaceSuggestion.tryParse({..._public, 'id': 'public-$index'})!,
      );
      final tournaments = List.generate(
        4,
        (index) => HomeRaceSuggestion.tryParse({
          ..._tournament,
          'id': 'tournament-$index',
        })!,
      );

      store.apply(
        generation,
        HomeSuggestedRacesRefresh(
          featuredRaces: [daily, weekly],
          publicRaces: public,
          tournaments: tournaments,
        ),
      );

      expect(store.state.data!.map((item) => item.id), [
        'daily',
        'weekly',
        'public-0',
        'public-1',
        'public-2',
        'public-3',
        'tournament-0',
        'tournament-1',
        'tournament-2',
        'tournament-3',
      ]);
    });
  });

  group('BackendApiService suggested races', () {
    test(
      'supported 200 parses resolution bits and malformed cards defensively',
      () async {
        final http = _Http([
          _Script(
            200,
            jsonEncode({
              'suggestions': [
                _daily,
                _public,
                {..._tournament, 'id': null},
              ],
              'resolved': {
                'featuredRaces': true,
                'publicRaces': false,
                'tournaments': true,
              },
            }),
          ),
        ]);
        final api = BackendApiService(httpClient: http);
        final result = await api.fetchHomeSuggestedRaces(identityToken: 't');
        expect(result.featuredRaces!.map((e) => e.id), ['daily']);
        expect(result.publicRaces, isNull);
        expect(result.tournaments, isEmpty);
        expect(api.homeSuggestedRacesSupport, EndpointSupport.supported);
        expect(
          http.requests.single.headersImpl.values['X-Client-Features'],
          contains('home_suggested_races'),
        );
      },
    );

    test(
      'only definite 404 selects and caches concurrent legacy fallback',
      () async {
        final http = _Http([
          const _Script(404, '{"error":"missing"}'),
          _Script(
            200,
            jsonEncode({
              'races': [
                {..._daily, 'raceId': 'daily'}..remove('id'),
              ],
            }),
          ),
          _Script(
            200,
            jsonEncode({
              'races': [_public],
            }),
          ),
          _Script(
            200,
            jsonEncode({
              'featured': [
                {..._tournament, 'joinable': true},
              ],
              'tournaments': [
                {..._tournament, 'id': 'not-joinable'},
              ],
            }),
          ),
        ]);
        final api = BackendApiService(httpClient: http);
        final result = await api.fetchHomeSuggestedRaces(identityToken: 't');
        expect(http.requests.map((r) => r.uri.path), [
          '/home/suggested-races',
          '/races/featured',
          '/races/public',
          '/tournaments/public',
        ]);
        expect(result.featuredRaces!.map((e) => e.id), ['daily']);
        expect(result.publicRaces!.map((e) => e.id), ['public']);
        expect(result.tournaments!.map((e) => e.id), ['tournament']);
        expect(api.homeSuggestedRacesSupport, EndpointSupport.unsupported);
      },
    );

    test(
      'legacy joinable tournament without createdAt remains discoverable',
      () async {
        final firstLegacyTournament = {..._tournament, 'joinable': true}
          ..remove('createdAt');
        final secondLegacyTournament = {
          ...firstLegacyTournament,
          'id': 'tournament-2',
        };
        final http = _Http([
          const _Script(404, '{"error":"missing"}'),
          const _Script(404, '{"error":"missing"}'),
          const _Script(404, '{"error":"missing"}'),
          _Script(
            200,
            jsonEncode({
              'featured': [firstLegacyTournament],
              'tournaments': [secondLegacyTournament],
            }),
          ),
        ]);
        final api = BackendApiService(httpClient: http);

        final result = await api.fetchHomeSuggestedRaces(identityToken: 't');

        expect(result.tournaments!.map((item) => item.id), [
          'tournament',
          'tournament-2',
        ]);
        expect(result.tournaments!.map((item) => item.createdAt), [
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          DateTime.fromMillisecondsSinceEpoch(1, isUtc: true),
        ]);
      },
    );

    test('500 retains state and never fans out', () async {
      final http = _Http([const _Script(500, '{"error":"boom"}')]);
      final api = BackendApiService(httpClient: http);
      final result = await api.fetchHomeSuggestedRaces(identityToken: 't');
      expect(result.anyResolved, isFalse);
      expect(http.requests, hasLength(1));
      expect(api.homeSuggestedRacesSupport, EndpointSupport.supported);
    });
  });

  group('real Home suggested carousel', () {
    testWidgets('renders strict order, semantics, and partial next card', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final auth = await _auth();
      final suggestions = [_daily, _public, _tournament]
          .map(HomeRaceSuggestion.tryParse)
          .whereType<HomeRaceSuggestion>()
          .toList();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeTab(
              stepData: StepData(steps: 4000, date: DateTime(2026, 8, 11)),
              isLoading: false,
              error: null,
              healthAuthorized: true,
              notificationsState: true,
              displayName: 'Walker',
              authService: auth,
              backendApiService: _Api(),
              onRefresh: () async {},
              onEnableHealth: () {},
              onEnableNotifications: () {},
              onDisplayNameChanged: () {},
              friendsSteps: const [],
              raceCard: const {'state': 'EMPTY'},
              suggestedRacesState: Loadable.success(suggestions),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
      await tester.pump();

      expect(find.text('SUGGESTED RACES'), findsOneWidget);
      expect(find.text('RACES'), findsNothing);
      final dailyX = tester.getTopLeft(find.text('DAILY')).dx;
      final publicX = tester.getTopLeft(find.text('PUBLIC')).dx;
      expect(dailyX, lessThan(publicX));
      final publicName = find.text('LUNCH BREAK SPRINT');
      expect(publicName, findsOneWidget);
      expect(
        (tester.getTopLeft(find.text('PUBLIC')).dy -
                tester.getTopLeft(publicName).dy)
            .abs(),
        lessThan(10),
        reason: 'PUBLIC belongs inline with the race name, not in its own row',
      );
      expect(
        find.byKey(const Key('home-suggestion-FEATURED_RACE-daily')),
        findsOneWidget,
      );
      expect(
        tester
            .getSize(
              find.byKey(
                const Key('home-suggestion-surface-FEATURED_RACE-daily'),
              ),
            )
            .height,
        136,
        reason: 'suggested race tickets should not frame empty vertical space',
      );
      expect(
        find.bySemanticsLabel(RegExp('Daily.*Daily 10K.*Join Daily 10K')),
        findsOneWidget,
      );
    });

    testWidgets('renders the canonical Weekly Showdown tournament card', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final auth = await _auth();
      final suggestion = HomeRaceSuggestion.tryParse(
        _weeklyShowdownTournament,
      )!;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 1600),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: HomeTab(
                stepData: StepData(steps: 4000, date: DateTime(2026, 8, 11)),
                isLoading: false,
                error: null,
                healthAuthorized: true,
                notificationsState: true,
                displayName: 'Walker',
                authService: auth,
                backendApiService: _Api(),
                onRefresh: () async {},
                onEnableHealth: () {},
                onEnableNotifications: () {},
                onDisplayNameChanged: () {},
                friendsSteps: const [],
                raceCard: const {'state': 'EMPTY'},
                suggestedRacesState: Loadable.success([suggestion]),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      // Other fixed Home chrome predates this carousel and overflows at 2x.
      // Clear that known frame-level exception so this assertion isolates the
      // newly revealed prize-bearing suggestion ticket.
      tester.takeException();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
      await tester.pump();

      expect(
        find.byKey(
          const Key('home-suggestion-TOURNAMENT-weekly-showdown-tournament'),
        ),
        findsOneWidget,
      );
      expect(find.text('8 RACER TOURNEY'), findsOneWidget);
      expect(find.text('2-DAY MATCHUPS · 3/8 IN'), findsOneWidget);
      expect(find.text('800 COIN PRIZE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('only the tapped card shows in-flight progress at 1.3x text', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final auth = await _auth();
      final suggestions = [_daily, _public]
          .map(HomeRaceSuggestion.tryParse)
          .whereType<HomeRaceSuggestion>()
          .toList();
      final pending = Completer<void>();
      final joining = <String>{};
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 1600),
              textScaler: TextScaler.linear(1.3),
            ),
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return HomeTab(
                  stepData: StepData(steps: 4000, date: DateTime(2026, 8, 11)),
                  isLoading: false,
                  error: null,
                  healthAuthorized: true,
                  notificationsState: true,
                  displayName: 'Walker',
                  authService: auth,
                  backendApiService: _Api(),
                  onRefresh: () async {},
                  onEnableHealth: () {},
                  onEnableNotifications: () {},
                  onDisplayNameChanged: () {},
                  friendsSteps: const [],
                  suggestedRacesState: Loadable.success(suggestions),
                  joiningSuggestionKeys: joining,
                  onJoinSuggestion: (suggestion) async {
                    update(() => joining.add(suggestion.stableKey));
                    await pending.future;
                    update(() => joining.remove(suggestion.stableKey));
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('home-suggestion-join-FEATURED_RACE-daily')),
      );
      await tester.pump();
      expect(find.text('JOINING...'), findsOneWidget);
      expect(find.text('JOIN'), findsOneWidget);
      expect(tester.takeException(), isNull);
      pending.complete();
      await tester.pump();
    });

    testWidgets('loading, empty, and error keep the discovery footprint', (
      tester,
    ) async {
      Future<void> pump(Loadable<List<HomeRaceSuggestion>> state) async {
        final auth = await _auth();
        await tester.pumpWidget(
          MaterialApp(
            home: HomeTab(
              stepData: StepData(steps: 1, date: DateTime(2026, 8, 11)),
              isLoading: false,
              error: null,
              healthAuthorized: true,
              notificationsState: true,
              displayName: 'Walker',
              authService: auth,
              backendApiService: _Api(),
              onRefresh: () async {},
              onEnableHealth: () {},
              onEnableNotifications: () {},
              onDisplayNameChanged: () {},
              friendsSteps: const [],
              suggestedRacesState: state,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
      }

      await pump(const Loadable.loading());
      expect(
        find.byKey(const Key('home-suggestion-skeleton-0')),
        findsOneWidget,
      );
      await pump(const Loadable.success([]));
      expect(find.text('NO SUGGESTED RACES'), findsOneWidget);
      expect(find.text('BROWSE ALL'), findsOneWidget);
      await pump(const Loadable.error('offline'));
      expect(find.text('TRY AGAIN'), findsOneWidget);
    });

    testWidgets('header and empty actions share the Public Races route', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final auth = await _auth();
      var opens = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: HomeTab(
            stepData: StepData(steps: 1, date: DateTime(2026, 8, 11)),
            isLoading: false,
            error: null,
            healthAuthorized: true,
            notificationsState: true,
            displayName: 'Walker',
            authService: auth,
            backendApiService: _Api(),
            onRefresh: () async {},
            onEnableHealth: () {},
            onEnableNotifications: () {},
            onDisplayNameChanged: () {},
            friendsSteps: const [],
            suggestedRacesState: const Loadable.success([]),
            onOpenPublicRaces: () => opens++,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
      await tester.pump();
      await tester.tap(find.text('VIEW ALL'));
      await tester.tap(find.text('BROWSE ALL'));
      expect(opens, 2);
    });
  });
}
