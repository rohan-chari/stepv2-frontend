import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/race_results_ack_queue.dart';

class _AckApi extends BackendApiService {
  final List<({List<String> ids, bool capability})> calls = [];
  int failuresRemaining = 0;
  Completer<void>? requestStarted;
  Completer<void>? requestGate;

  @override
  Future<void> markRaceResultsSeenStrict({
    required String identityToken,
    required List<String> raceIds,
    required bool racePayoutDoubleCapability,
  }) async {
    calls.add((
      ids: List<String>.of(raceIds),
      capability: racePayoutDoubleCapability,
    ));
    if (requestStarted != null && !requestStarted!.isCompleted) {
      requestStarted!.complete();
    }
    if (requestGate != null) await requestGate!.future;
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw const ApiException('offline');
    }
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  String seededRecord({String raceId = 'old-race', bool capability = true}) =>
      jsonEncode([
        {
          'version': 2,
          'userId': 'user-1',
          'backendBaseUrl': 'https://api.example',
          'raceIds': [raceId],
          'racePayoutDoubleCapability': capability,
          'queuedAt': '2026-08-12T00:00:00.000Z',
        },
      ]);

  test(
    'durable queue partitions capability and chunks sorted IDs at 50',
    () async {
      final api = _AckApi();
      final queue = RaceResultsAcknowledgementQueue(backendApiService: api);
      final capableIds = [for (var i = 59; i >= 0; i--) 'race-$i'];

      await queue.hydrate();
      await queue.enqueue(
        userId: 'user-1',
        backendBaseUrl: 'https://api.example',
        raceIds: capableIds,
        racePayoutDoubleCapability: true,
      );
      await queue.enqueue(
        userId: 'user-1',
        backendBaseUrl: 'https://api.example',
        raceIds: const ['legacy-race'],
        racePayoutDoubleCapability: false,
      );

      expect(
        queue.suppressedRaceIds(
          userId: 'user-1',
          backendBaseUrl: 'https://api.example',
        ),
        containsAll(<String>[...capableIds, 'legacy-race']),
      );

      await queue.replayMatching(
        identityToken: 'token',
        userId: 'user-1',
        backendBaseUrl: 'https://api.example',
      );

      expect(api.calls, hasLength(3));
      expect(api.calls.where((c) => c.capability), hasLength(2));
      expect(api.calls.where((c) => !c.capability).single.ids, ['legacy-race']);
      expect(
        api.calls.first.ids,
        orderedEquals([...api.calls.first.ids]..sort()),
      );
      expect(api.calls.first.ids, hasLength(50));
      expect(await queue.debugRecords(), isEmpty);
    },
  );

  test(
    'non-2xx retains only the unacknowledged partition across restart',
    () async {
      final api = _AckApi()..failuresRemaining = 1;
      var queue = RaceResultsAcknowledgementQueue(backendApiService: api);
      await queue.hydrate();
      await queue.enqueue(
        userId: 'user-1',
        backendBaseUrl: 'https://api.example',
        raceIds: const ['race-b', 'race-a', 'race-a'],
        racePayoutDoubleCapability: true,
      );
      await queue.enqueue(
        userId: 'other-user',
        backendBaseUrl: 'https://api.example',
        raceIds: const ['other-race'],
        racePayoutDoubleCapability: true,
      );

      await queue.replayMatching(
        identityToken: 'token',
        userId: 'user-1',
        backendBaseUrl: 'https://api.example',
      );
      expect(await queue.debugRecords(), hasLength(2));

      queue = RaceResultsAcknowledgementQueue(backendApiService: api);
      await queue.hydrate();
      await queue.replayMatching(
        identityToken: 'token',
        userId: 'user-1',
        backendBaseUrl: 'https://api.example',
      );

      final remaining = await queue.debugRecords();
      expect(remaining, hasLength(1));
      expect(remaining.single.userId, 'other-user');
      expect(api.calls.last.capability, isTrue);
      expect(api.calls.last.ids, ['race-a', 'race-b']);
    },
  );

  test('legacy records decode as tokenless and are never upgraded', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      RaceResultsAcknowledgementQueue.preferencesKey:
          '[{"version":1,"userId":"user-1","backendBaseUrl":"https://api.example","raceIds":["old-race"],"queuedAt":"2026-08-12T00:00:00.000Z"}]',
    });
    final api = _AckApi();
    final queue = RaceResultsAcknowledgementQueue(backendApiService: api);
    await queue.hydrate();
    await queue.replayMatching(
      identityToken: 'token',
      userId: 'user-1',
      backendBaseUrl: 'https://api.example',
    );

    expect(api.calls.single.capability, isFalse);
  });

  test(
    'preference failure keeps session suppression and sends immediately',
    () async {
      final api = _AckApi();
      final queue = RaceResultsAcknowledgementQueue(
        backendApiService: api,
        persistenceWriter: (_) async => false,
      );
      await queue.hydrate();
      final durable = await queue.enqueue(
        userId: 'user-1',
        backendBaseUrl: 'https://api.example',
        raceIds: const ['race-a'],
        racePayoutDoubleCapability: true,
        identityToken: 'token',
      );
      await Future<void>.delayed(Duration.zero);

      expect(durable, isFalse);
      expect(
        queue.suppressedRaceIds(
          userId: 'user-1',
          backendBaseUrl: 'https://api.example',
        ),
        contains('race-a'),
      );
      expect(api.calls.single.ids, ['race-a']);
      expect(api.calls.single.capability, isTrue);
    },
  );

  test(
    'enqueue waits for replay clear so a new capability partition is not dropped',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        RaceResultsAcknowledgementQueue.preferencesKey: seededRecord(),
      });
      final api = _AckApi();
      final clearStarted = Completer<void>();
      final releaseClear = Completer<void>();
      final queue = RaceResultsAcknowledgementQueue(
        backendApiService: api,
        persistenceWriter: (value) async {
          final records = jsonDecode(value) as List<dynamic>;
          if (records.isEmpty) {
            if (!clearStarted.isCompleted) clearStarted.complete();
            await releaseClear.future;
          }
          return true;
        },
      );
      await queue.hydrate();

      final replay = queue.replayMatching(
        identityToken: 'old-token',
        userId: 'user-1',
        backendBaseUrl: 'https://api.example',
      );
      await clearStarted.future;

      var enqueueCompleted = false;
      final enqueue = queue
          .enqueue(
            userId: 'user-1',
            backendBaseUrl: 'https://api.example',
            raceIds: const ['new-tokenless-race'],
            racePayoutDoubleCapability: false,
          )
          .whenComplete(() => enqueueCompleted = true);
      await Future<void>.delayed(Duration.zero);

      expect(enqueueCompleted, isFalse);
      releaseClear.complete();
      await Future.wait<void>([replay, enqueue]);

      final records = await queue.debugRecords();
      expect(records, hasLength(1));
      expect(records.single.raceIds, ['new-tokenless-race']);
      expect(records.single.racePayoutDoubleCapability, isFalse);
    },
  );

  test(
    'replay waits for enqueue persistence and cannot resurrect acknowledged IDs',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        RaceResultsAcknowledgementQueue.preferencesKey: seededRecord(),
      });
      final api = _AckApi();
      final enqueuePersistStarted = Completer<void>();
      final releaseEnqueuePersist = Completer<void>();
      final queue = RaceResultsAcknowledgementQueue(
        backendApiService: api,
        persistenceWriter: (value) async {
          final records = jsonDecode(value) as List<dynamic>;
          final ids = records
              .whereType<Map>()
              .expand((record) => (record['raceIds'] as List<dynamic>))
              .whereType<String>()
              .toSet();
          if (ids.contains('new-race') && !enqueuePersistStarted.isCompleted) {
            enqueuePersistStarted.complete();
            await releaseEnqueuePersist.future;
          }
          return true;
        },
      );
      await queue.hydrate();

      final enqueue = queue.enqueue(
        userId: 'user-1',
        backendBaseUrl: 'https://api.example',
        raceIds: const ['new-race'],
        racePayoutDoubleCapability: true,
      );
      await enqueuePersistStarted.future;

      var replayCompleted = false;
      final replay = queue
          .replayMatching(
            identityToken: 'old-token',
            userId: 'user-1',
            backendBaseUrl: 'https://api.example',
          )
          .whenComplete(() => replayCompleted = true);
      await Future<void>.delayed(Duration.zero);

      expect(replayCompleted, isFalse);
      expect(api.calls, isEmpty);
      releaseEnqueuePersist.complete();
      await Future.wait<void>([enqueue, replay]);

      expect(api.calls.single.ids, ['new-race', 'old-race']);
      expect(await queue.debugRecords(), isEmpty);
    },
  );

  test(
    'auth context is checked before request and again before durable clear',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        RaceResultsAcknowledgementQueue.preferencesKey: seededRecord(),
      });
      final api = _AckApi();
      final queue = RaceResultsAcknowledgementQueue(backendApiService: api);
      await queue.hydrate();
      var contextIsCurrent = false;

      await queue.replayMatching(
        identityToken: 'old-token',
        userId: 'user-1',
        backendBaseUrl: 'https://api.example',
        isAuthenticatedContextCurrent: () => contextIsCurrent,
      );
      expect(api.calls, isEmpty);
      expect(await queue.debugRecords(), hasLength(1));

      contextIsCurrent = true;
      api.requestStarted = Completer<void>();
      api.requestGate = Completer<void>();
      final replay = queue.replayMatching(
        identityToken: 'old-token',
        userId: 'user-1',
        backendBaseUrl: 'https://api.example',
        isAuthenticatedContextCurrent: () => contextIsCurrent,
      );
      await api.requestStarted!.future;
      contextIsCurrent = false;
      api.requestGate!.complete();
      await replay;

      expect(api.calls.single.ids, ['old-race']);
      expect(await queue.debugRecords(), hasLength(1));
    },
  );
}
