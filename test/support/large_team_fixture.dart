import 'package:step_tracker/services/backend_api_service.dart';

class LargeTeamFixtureApi extends BackendApiService {
  LargeTeamFixtureApi({
    this.status = 'PENDING',
    this.complete = true,
    this.partialProgress = false,
  });
  final String status;
  final bool complete;
  final bool partialProgress;
  final roster = <Map<String, dynamic>>[
    for (final side in ['A', 'B'])
      for (var i = 0; i < 10; i++)
        {
          'userId': '$side$i',
          'displayName': '$side racer $i',
          'status': 'ACCEPTED',
          'team': 'TEAM_$side',
          'totalSteps': 1000 - i,
          'accessories': <Map<String, dynamic>>[],
        },
  ];
  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async => {
    'id': raceId,
    'name': 'Large Team Race',
    'status': status,
    'isTeamRace': true,
    'teamSize': 10,
    'teamAName': 'Gold',
    'teamBName': 'Green',
    'myStatus': 'ACCEPTED',
    'myTeam': 'TEAM_A',
    'isCreator': false,
    'powerupsEnabled': false,
    'maxDurationDays': 7,
    'buyInAmount': 0,
    'potCoins': 0,
    'payoutPreset': 'WINNER_TAKES_ALL',
    'endsAt': '2026-09-10T12:00:00Z',
    'acceptedCount': 20,
    'teamAAcceptedCount': 10,
    'teamBAcceptedCount': 10,
    'participants': roster.take(15).toList(),
    if (complete) 'teamRosterComplete': true,
    if (complete) 'teamAcceptedParticipants': roster,
  };
  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async => {
    'status': status,
    'participants': partialProgress ? roster.take(15).toList() : roster,
    'teams': {
      'teamA': {'totalSteps': 10045, 'memberCount': 10},
      'teamB': {'totalSteps': 10045, 'memberCount': 10},
    },
    'powerupData': {'enabled': false, 'inventory': [], 'activeEffects': []},
  };
  @override
  Future<Map<String, dynamic>> fetchRaceFeed({
    required String identityToken,
    required String raceId,
    String? cursor,
    int limit = 50,
  }) async => {'events': [], 'hasMore': false};
}
