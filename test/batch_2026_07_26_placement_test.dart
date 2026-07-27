import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/utils/race_participant_display.dart';
import 'package:step_tracker/utils/team_race.dart';
import 'package:step_tracker/widgets/leaderboard_plank.dart';

/// Items 12 + 16 (client half) — race detail must render the SERVER placement
/// from `GET /races/:id/progress` (contract §5 C1) instead of the array index,
/// and must fall back to the existing client comparator when the field is
/// absent (older backend). Plus F-16f: the team-total fallback must not count a
/// stealthed member's hidden `null` total as zero.

class _ProgressApi extends BackendApiService {
  _ProgressApi({required this.progress, this.race});

  final Map<String, dynamic> progress;
  final Map<String, dynamic>? race;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async {
    return {
      'id': raceId,
      'name': 'Standings Race',
      'status': 'ACTIVE',
      'targetSteps': 100000,
      'maxDurationDays': 7,
      'buyInAmount': 0,
      'payoutPreset': 'WINNER_TAKES_ALL',
      'potCoins': 0,
      'heldPotCoins': 0,
      'projectedPotCoins': 0,
      'payouts': const {'first': 0, 'second': 0, 'third': 0},
      'myStatus': 'ACCEPTED',
      'isCreator': false,
      'powerupsEnabled': false,
      'endsAt': '2026-12-10T12:00:00.000Z',
      'participants': const [
        {'userId': 'u1', 'displayName': 'Ann', 'status': 'ACCEPTED'},
        {'userId': 'u2', 'displayName': 'Bob', 'status': 'ACCEPTED'},
        {'userId': 'u3', 'displayName': 'Cat', 'status': 'ACCEPTED'},
      ],
      ...?race,
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async => progress;

  @override
  Future<Map<String, dynamic>> fetchRaceFeed({
    String? cursor,
    required String identityToken,
    required String raceId,
  }) async => const {'events': []};

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async =>
      const {'coins': 0, 'heldCoins': 0};
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'u2',
    'auth_display_name': 'Bob',
    'auth_coins': 0,
    'auth_held_coins': 0,
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Future<void> _pumpDetail(WidgetTester tester, BackendApiService api) async {
  await tester.binding.setSurfaceSize(const Size(500, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: RaceDetailScreen(
        authService: await _auth(),
        raceId: 'race-1',
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Rank the plank widget rendered for [name] was given (0-based, as the plank
/// expects — server placement 1 => rank 0).
int _rankOf(WidgetTester tester, String name) {
  final planks = tester.widgetList<LeaderboardPlank>(
    find.byType(LeaderboardPlank),
  );
  return planks.firstWhere((p) => p.name == name).rank;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('orderRaceParticipantsForDisplay (contract §5 C1)', () {
    test('server placement wins when every row carries one', () {
      final ordered = orderRaceParticipantsForDisplay([
        {'userId': 'u1', 'totalSteps': 10, 'placement': 3},
        {'userId': 'u2', 'totalSteps': 5, 'placement': 1},
        {'userId': 'u3', 'totalSteps': 7, 'placement': 2},
      ]);
      expect(ordered.map((p) => p['userId']), ['u2', 'u3', 'u1']);
    });

    test('an absent placement falls back to the existing client comparator', () {
      final raw = [
        {'userId': 'u1', 'totalSteps': 10},
        {'userId': 'u2', 'totalSteps': 5},
        {'userId': 'u3', 'totalSteps': 7},
      ];
      expect(
        orderRaceParticipantsForDisplay(raw).map((p) => p['userId']),
        sortRaceParticipantsForDisplay(raw).map((p) => p['userId']),
      );
    });

    test('a partially-placed payload also falls back (all-or-nothing)', () {
      final raw = [
        {'userId': 'u1', 'totalSteps': 10, 'placement': 2},
        {'userId': 'u2', 'totalSteps': 5},
      ];
      expect(
        orderRaceParticipantsForDisplay(raw).map((p) => p['userId']),
        sortRaceParticipantsForDisplay(raw).map((p) => p['userId']),
      );
    });

    test('serverPlacementOf reads defensively', () {
      expect(serverPlacementOf(<String, dynamic>{}), isNull);
      expect(serverPlacementOf({'placement': null}), isNull);
      expect(serverPlacementOf({'placement': 'first'}), isNull);
      expect(serverPlacementOf({'placement': 2}), 2);
    });
  });

  group('race detail renders the server placement', () {
    testWidgets('server placement beats the array index', (tester) async {
      // Deliberately adversarial: the array order and the step order both
      // disagree with the server's ranking.
      final api = _ProgressApi(
        progress: const {
          'status': 'ACTIVE',
          'myPlacement': 1,
          'participants': [
            {
              'userId': 'u1',
              'displayName': 'Ann',
              'totalSteps': 9000,
              'placement': 3,
            },
            {
              'userId': 'u2',
              'displayName': 'Bob',
              'totalSteps': 1000,
              'placement': 1,
            },
            {
              'userId': 'u3',
              'displayName': 'Cat',
              'totalSteps': 5000,
              'placement': 2,
            },
          ],
        },
      );
      await _pumpDetail(tester, api);

      expect(_rankOf(tester, 'Bob'), 0);
      expect(_rankOf(tester, 'Cat'), 1);
      expect(_rankOf(tester, 'Ann'), 2);
    });

    testWidgets('an older backend (no placement) keeps the client sort', (
      tester,
    ) async {
      final api = _ProgressApi(
        progress: const {
          'status': 'ACTIVE',
          'participants': [
            {'userId': 'u1', 'displayName': 'Ann', 'totalSteps': 9000},
            {'userId': 'u2', 'displayName': 'Bob', 'totalSteps': 1000},
            {'userId': 'u3', 'displayName': 'Cat', 'totalSteps': 5000},
          ],
        },
      );
      await _pumpDetail(tester, api);

      // Client comparator: most steps first, and nothing crashes on the
      // missing field.
      expect(_rankOf(tester, 'Ann'), 0);
      expect(_rankOf(tester, 'Cat'), 1);
      expect(_rankOf(tester, 'Bob'), 2);
    });
  });

  group('F-16f — a stealthed member is not counted as zero steps', () {
    test('teamTotal skips hidden totals instead of coercing them to 0', () {
      final participants = <Map<String, dynamic>>[
        {'team': 'TEAM_A', 'totalSteps': 5000},
        {'team': 'TEAM_A', 'totalSteps': null, 'stealthed': true},
      ];
      // The honest answer is "unknown", not 5000 — the fallback must say so.
      expect(TeamRace.teamTotalOrNull(participants, RaceTeam.teamA), isNull);
      // With no hidden member it still totals normally.
      expect(
        TeamRace.teamTotalOrNull([
          {'team': 'TEAM_A', 'totalSteps': 5000},
          {'team': 'TEAM_A', 'totalSteps': 1000},
        ], RaceTeam.teamA),
        6000,
      );
    });
  });

  group('item 16 — teams.asOf staleness affordance', () {
    test('teamsAsOf reads the additive field defensively', () {
      expect(TeamRace.teamsAsOf(<String, dynamic>{}), isNull);
      expect(TeamRace.teamsAsOf({'teams': null}), isNull);
      expect(TeamRace.teamsAsOf({'teams': {'asOf': null}}), isNull);
      expect(TeamRace.teamsAsOf({'teams': {'asOf': 'not-a-date'}}), isNull);
      expect(
        TeamRace.teamsAsOf({
          'teams': {'asOf': '2026-07-26T12:00:00.000Z'},
        }),
        DateTime.parse('2026-07-26T12:00:00.000Z'),
      );
    });

    test('the label degrades to null when asOf is absent', () {
      final now = DateTime.parse('2026-07-26T12:30:00.000Z');
      expect(TeamRace.teamsAsOfLabel(<String, dynamic>{}, now: now), isNull);
      expect(
        TeamRace.teamsAsOfLabel({
          'teams': {'asOf': '2026-07-26T12:29:40.000Z'},
        }, now: now),
        'as of just now',
      );
      expect(
        TeamRace.teamsAsOfLabel({
          'teams': {'asOf': '2026-07-26T12:25:00.000Z'},
        }, now: now),
        'as of 5 min ago',
      );
      expect(
        TeamRace.teamsAsOfLabel({
          'teams': {'asOf': '2026-07-26T10:30:00.000Z'},
        }, now: now),
        'as of 2 h ago',
      );
    });
  });
}
