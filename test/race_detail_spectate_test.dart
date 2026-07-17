import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// Relaxed race-view auth: a tournament participant can open ANY matchup race in
// their bracket read-only. The viewer knows it's spectate mode because their
// userId isn't among the race's two participants — the screen then shows a
// SPECTATING banner and hides every write affordance (powerups, forfeit; chat
// composer goes read-only).

class _SpectateMatchupApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async {
    return {
      'id': raceId,
      'name': 'Daily Dash — Semifinals',
      'status': 'ACTIVE',
      'isTeamRace': false,
      'maxDurationDays': 1,
      'buyInAmount': 0,
      'potCoins': 0,
      // The viewer (user-1) is NOT one of these two racers → spectating.
      'myStatus': null,
      'isCreator': false,
      'powerupsEnabled': true,
      'endsAt': '2026-08-10T12:00:00.000Z',
      'tournamentId': 'tour-1',
      'tournamentRoundLabel': 'SEMIFINALS',
      'tournamentName': 'Daily Dash',
      'participants': const [
        {'userId': 'emersonz', 'displayName': 'emersonz', 'status': 'ACCEPTED'},
        {'userId': 'shefalig', 'displayName': 'ShefaliG', 'status': 'ACCEPTED'},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async {
    return {
      'status': 'ACTIVE',
      'participants': const [
        {'userId': 'emersonz', 'displayName': 'emersonz', 'totalSteps': 8200, 'finishedAt': null},
        {'userId': 'shefalig', 'displayName': 'ShefaliG', 'totalSteps': 7100, 'finishedAt': null},
      ],
      'powerupData': const {
        'enabled': true,
        'inventory': [],
        'powerupSlots': 3,
        'queuedBoxCount': 0,
        'activeEffects': [],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaceFeed({
    String? cursor,
    required String identityToken,
    required String raceId,
  }) async =>
      const {'events': []};

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async =>
      const {'coins': 100, 'heldCoins': 0};
}

/// A race the viewer IS in — the control case (no spectate chrome).
class _ParticipantMatchupApi extends _SpectateMatchupApi {
  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async {
    final base = await super.fetchRaceDetails(
      identityToken: identityToken,
      raceId: raceId,
    );
    return {
      ...base,
      'myStatus': 'ACCEPTED',
      'participants': const [
        {'userId': 'user-1', 'displayName': 'Trail Walker', 'status': 'ACCEPTED'},
        {'userId': 'shefalig', 'displayName': 'ShefaliG', 'status': 'ACCEPTED'},
      ],
    };
  }
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_coins': 100,
    'auth_held_coins': 0,
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Future<void> _pump(WidgetTester tester, BackendApiService api) async {
  final auth = await _auth();
  await tester.pumpWidget(
    MaterialApp(
      home: RaceDetailScreen(
        authService: auth,
        raceId: 'matchup-race',
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('non-participant sees the SPECTATING banner and no write UI',
      (tester) async {
    await _pump(tester, _SpectateMatchupApi());

    // The read-only indicator.
    expect(find.text('SPECTATING · READ-ONLY'), findsOneWidget);
    // The powerups section (a write surface) is hidden while spectating.
    expect(find.text('POWERUPS'), findsNothing);
    // The live matchup is still visible (leaderboard planks render the racers).
    expect(find.textContaining('emersonz'), findsWidgets);
    expect(find.textContaining('ShefaliG'), findsWidgets);
  });

  testWidgets('a participant does NOT get the spectate chrome', (tester) async {
    await _pump(tester, _ParticipantMatchupApi());

    expect(find.text('SPECTATING · READ-ONLY'), findsNothing);
    // Powerups section renders for a real racer (powerups enabled).
    expect(find.text('POWERUPS'), findsOneWidget);
  });
}
