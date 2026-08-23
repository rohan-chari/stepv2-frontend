import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/race_progress_projection.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/app_route_observer.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _PageProjectionApi extends BackendApiService {
  _PageProjectionApi({
    this.bootstrapCompleter,
    this.failBootstrap = false,
    this.empty = false,
    this.includeProjectionMetadata = true,
  });

  final Completer<RaceBootstrapResult>? bootstrapCompleter;
  final bool failBootstrap;
  final bool empty;
  final bool includeProjectionMetadata;
  final List<int> requestedOffsets = [];

  Map<String, dynamic> _race() => {
    'id': 'weekly-race',
    'name': 'Weekly Sprint',
    'seedKind': 'WEEKLY',
    'status': 'ACTIVE',
    'maxDurationDays': 7,
    'buyInAmount': 100,
    'payoutPreset': 'TOP3_70_20_10',
    'potCoins': 500,
    'projectedPotCoins': 500,
    'payoutTiers': const [
      {'placement': 1, 'amount': 350},
      {'placement': 2, 'amount': 100},
      {'placement': 3, 'amount': 50},
    ],
    'payouts': {'first': 350, 'second': 100, 'third': 50},
    'myStatus': 'ACCEPTED',
    'isCreator': false,
    'powerupsEnabled': false,
    'endsAt': '2126-04-10T12:00:00.000Z',
    'participants': [
      for (var index = 0; index < 15; index++) _participant('u$index'),
    ],
    'participantsPagination': const {
      'offset': 0,
      'limit': 15,
      'total': 500,
      'hasMore': true,
      'nextOffset': 15,
    },
    'acceptedCount': 500,
  };

  Map<String, dynamic> _progress({required int offset}) {
    final participants = empty
        ? const <Map<String, dynamic>>[]
        : [
            for (var index = offset; index < offset + 15; index++)
              _progressParticipant('u$index', index + 1),
          ];
    return {
      'status': 'ACTIVE',
      'participants': participants,
      'pagination': {
        'offset': offset,
        'limit': 15,
        'total': empty ? 0 : 500,
        'hasMore': !empty && offset + 15 < 500,
        'nextOffset': empty ? 0 : offset + 15,
      },
      // This is the backend requester overlay. The viewer is deliberately not
      // present in page 0, but their authoritative placement still is.
      'myPlacement': 500,
      'powerupData': {
        'enabled': false,
        'inventory': [],
        'powerupSlots': 3,
        'queuedBoxCount': 0,
        'activeEffects': [],
      },
      if (includeProjectionMetadata) ...{
        'projectionGeneration': 12,
        'asOf': '2026-08-22T12:00:00.000Z',
        'projectionSource': 'authoritative',
      },
    };
  }

  @override
  Future<RaceBootstrapResult> fetchRaceBootstrap({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async {
    if (failBootstrap) {
      throw const ApiException('Projection server unavailable.');
    }
    final pending = bootstrapCompleter;
    if (pending != null) return pending.future;
    return RaceBootstrapResult(
      supported: true,
      race: _race(),
      progress: _progress(offset: 0),
      projectionMetadata: includeProjectionMetadata
          ? const RaceProjectionMetadata(
              generation: 12,
              asOf: '2026-08-22T12:00:00.000Z',
              source: 'authoritative',
            )
          : null,
    );
  }

  @override
  Future<RaceProgressResult> fetchRaceProgressParticipants({
    required String identityToken,
    required String raceId,
    int offset = 0,
    int limit = 10,
  }) async {
    requestedOffsets.add(offset);
    return RaceProgressResult(
      progress: _progress(offset: offset),
      hasCompactInventory: false,
      participantsPagination: {
        'offset': offset,
        'limit': limit,
        'total': empty ? 0 : 500,
        'hasMore': !empty && offset + limit < 500,
        'nextOffset': empty ? 0 : offset + limit,
      },
    );
  }

  @override
  Future<RaceMessageStreamsResult> fetchRaceMessageStreams({
    required String identityToken,
    required String raceId,
    required bool includeUser,
    int limit = 50,
  }) async => const RaceMessageStreamsResult(
    supported: true,
    systemResolved: true,
    systemStream: {'messages': [], 'nextCursor': null},
    userResolved: true,
    userStream: {'messages': [], 'nextCursor': null},
    chatWatermark: {'recentIds': <String>[]},
  );

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async =>
      const {'coins': 320, 'heldCoins': 0};
}

Map<String, dynamic> _participant(String id) => {
  'userId': id,
  'displayName': 'Racer $id',
  'status': 'ACCEPTED',
  'accessories': const [],
};

Map<String, dynamic> _progressParticipant(String id, int placement) => {
  ..._participant(id),
  'totalSteps': 500000 - placement,
  'placement': placement,
  'finishedAt': null,
};

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'token',
    'auth_user_identifier': 'apple-user',
    'auth_session_token': 'session',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
  });
  final service = AuthService();
  await service.restoreSession();
  return service;
}

Future<void> _pumpRace(WidgetTester tester, _PageProjectionApi api) async {
  final auth = await _auth();
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [appRouteObserver],
      home: RaceDetailScreen(
        authService: auth,
        raceId: 'weekly-race',
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
  // Advance explicitly; pumpAndSettle is unsafe while the ACTIVE screen's
  // countdown and polling timers are live.
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.bara.app',
      version: '2.3.5',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('weekly race page projection parsing', () {
    test(
      'accepts the additive metadata and ignores malformed platform values',
      () {
        expect(
          RaceProjectionMetadata.tryParse({
            'projectionGeneration': 12,
            'asOf': '2026-08-22T12:00:00.000Z',
            'projectionSource': 'authoritative',
          }),
          const RaceProjectionMetadata(
            generation: 12,
            asOf: '2026-08-22T12:00:00.000Z',
            source: 'authoritative',
          ),
        );
        expect(
          RaceProjectionMetadata.tryParse({
            'projectionGeneration': {'unexpected': true},
            'asOf': 12,
            'projectionSource': 'future-source',
          }),
          isNull,
        );
      },
    );

    test(
      'missing optional projection metadata is an ordinary legacy response',
      () {
        expect(RaceProjectionMetadata.tryParse(const {}), isNull);
        expect(
          RaceProjectionMetadata.tryParse(const {'projectionGeneration': 12}),
          const RaceProjectionMetadata(generation: 12),
        );
      },
    );
  });

  group('race detail page states', () {
    testWidgets(
      'loads page 0 and requests the next page without changing the UI',
      (tester) async {
        final api = _PageProjectionApi();
        await _pumpRace(tester, api);

        expect(find.text('@Racer u0'), findsWidgets);
        expect(find.text('@Racer u15'), findsNothing);
        final nextPage = find.byKey(const Key('standings-next-page'));
        await tester.scrollUntilVisible(
          nextPage,
          400,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pump();
        await tester.tap(nextPage);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));

        expect(api.requestedOffsets, [15]);
        expect(find.text('@Racer u0'), findsNothing);
        expect(find.text('@Racer u15'), findsWidgets);
        expect(find.text('16-30 of 500'), findsOneWidget);
      },
    );

    testWidgets(
      'uses the requester placement overlay when its row is off-page',
      (tester) async {
        await _pumpRace(tester, _PageProjectionApi());

        final prizePool = find.byKey(const Key('race-prize-pool-board'));
        await tester.ensureVisible(prizePool);
        await tester.pump();
        await tester.tap(prizePool);
        await tester.pump();
        expect(find.byKey(const Key('race-prize-pool-sheet')), findsOneWidget);
        expect(
          find.text('You’re 500th. 497 places from the cut'),
          findsOneWidget,
        );
        expect(find.text('@Racer u0'), findsWidgets);
        expect(find.text('@Racer user-1'), findsNothing);
      },
    );

    testWidgets('renders a stable empty page when projection rows are empty', (
      tester,
    ) async {
      await _pumpRace(tester, _PageProjectionApi(empty: true));

      expect(find.byKey(const Key('standings-next-page')), findsOneWidget);
      expect(find.text('0-0 of 0'), findsOneWidget);
      expect(find.text('@Racer u0'), findsNothing);
    });

    testWidgets('keeps the loading state while bootstrap is pending', (
      tester,
    ) async {
      final completer = Completer<RaceBootstrapResult>();
      final api = _PageProjectionApi(bootstrapCompleter: completer);
      await _pumpRace(tester, api);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('@Racer u0'), findsNothing);

      completer.complete(
        RaceBootstrapResult(
          supported: true,
          race: api._race(),
          progress: api._progress(offset: 0),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('@Racer u0'), findsWidgets);
    });

    testWidgets('shows the existing error state when the page cannot load', (
      tester,
    ) async {
      await _pumpRace(tester, _PageProjectionApi(failBootstrap: true));

      expect(find.text('Failed to load race'), findsOneWidget);
      expect(find.text('Projection server unavailable.'), findsWidgets);
      expect(find.text('TRY AGAIN'), findsOneWidget);
    });

    testWidgets('renders without optional projection metadata', (tester) async {
      final api = _PageProjectionApi(includeProjectionMetadata: false);
      await _pumpRace(tester, api);

      expect(find.text('Weekly Sprint'), findsOneWidget);
      expect(find.text('@Racer u0'), findsWidgets);
      expect(find.byKey(const Key('standings-next-page')), findsOneWidget);
    });
  });
}
