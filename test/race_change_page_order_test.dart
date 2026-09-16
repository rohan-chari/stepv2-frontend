import 'dart:async';
import 'package:step_tracker/services/race_change_refresh.dart';

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
  final List<int> requestedOffsets = [];
  final changes = StreamController<RaceChangeSignal>.broadcast();
  int generation = 12;
  String label = 'Racer';
  @override
  Stream<RaceChangeSignal> watchRaceChanges({
    required String identityToken,
    required String raceId,
  }) => changes.stream;

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
    final participants = [
      for (var index = offset; index < offset + 15; index++)
        {
          ..._progressParticipant('u$index', index + 1),
          'displayName': '$label u$index',
        },
    ];
    return {
      'status': 'ACTIVE',
      'participants': participants,
      'pagination': {
        'offset': offset,
        'limit': 15,
        'total': 500,
        'hasMore': offset + 15 < 500,
        'nextOffset': offset + 15,
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
      ...{
        'projectionGeneration': generation,
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
    return RaceBootstrapResult(
      supported: true,
      race: _race(),
      progress: _progress(offset: 0),
      projectionMetadata: const RaceProjectionMetadata(
        generation: 12,
        asOf: '2026-08-22T12:00:00.000Z',
        source: 'authoritative',
      ),
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
        'total': 500,
        'hasMore': offset + limit < 500,
        'nextOffset': offset + limit,
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
  auth.applyBackendUser({
    'featureFlags': {'raceEventDrivenRefreshEnabled': true},
  }, authoritative: true);
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
  setUp(
    () => PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'bara',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    ),
  );
  testWidgets(
    'event refresh retains selected page and rejects older projection after newer score',
    (tester) async {
      final api = _PageProjectionApi();
      await _pumpRace(tester, api);
      final next = find.byKey(const Key('standings-next-page'));
      await tester.scrollUntilVisible(
        next,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      await tester.tap(next);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.text('@Racer u15'), findsWidgets);
      expect(find.text('16-30 of 500'), findsOneWidget);
      api.generation = 13;
      api.label = 'Current';
      api.changes.add(RaceChangeSignal.invalidated);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(api.requestedOffsets, [15, 15]);
      expect(find.text('@Current u15'), findsWidgets);
      expect(find.text('16-30 of 500'), findsOneWidget);
      api.generation = 12;
      api.label = 'Stale';
      api.changes.add(RaceChangeSignal.invalidated);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(api.requestedOffsets, [15, 15, 15]);
      expect(find.text('@Current u15'), findsWidgets);
      expect(find.text('@Stale u15'), findsNothing);
      expect(find.text('16-30 of 500'), findsOneWidget);
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await api.changes.close();
      await tester.pump();
    },
  );
}
