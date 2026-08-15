import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// Spec §5 / test 13 — a bracket-mate can now READ another matchup's chat and
// activity, so the race screen has to be read-only for them: the feed renders,
// the composer does not. Spectator-ness is derived from the participants list
// already in the details payload (am-I-in-it), never from a new backend field,
// so this holds against any backend version.

class _SpectateApi extends BackendApiService {
  _SpectateApi({this.myStatus});

  /// What the backend claims about the viewer. A spectator normally gets null,
  /// but the screen must not trust it — the participants list is the source.
  final String? myStatus;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async => {
    'id': raceId,
    'name': 'Daily Dash — Semifinals',
    'status': 'ACTIVE',
    'isTeamRace': false,
    'maxDurationDays': 1,
    'buyInAmount': 0,
    'potCoins': 0,
    'myStatus': myStatus,
    'isCreator': false,
    'powerupsEnabled': true,
    'endsAt': '2099-08-10T12:00:00.000Z',
    'tournamentId': 'tour-1',
    'tournamentRoundLabel': 'SEMIFINALS',
    'tournamentName': 'Daily Dash',
    // user-1 (the viewer) is NOT here → spectating.
    'participants': const [
      {'userId': 'emersonz', 'displayName': 'emersonz', 'status': 'ACCEPTED'},
      {'userId': 'shefalig', 'displayName': 'ShefaliG', 'status': 'ACCEPTED'},
    ],
  };

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async => {
    'status': 'ACTIVE',
    'participants': const [
      {
        'userId': 'emersonz',
        'displayName': 'emersonz',
        'totalSteps': 8200,
        'finishedAt': null,
      },
      {
        'userId': 'shefalig',
        'displayName': 'ShefaliG',
        'totalSteps': 7100,
        'finishedAt': null,
      },
    ],
    'powerupData': const {
      'enabled': true,
      'inventory': [],
      'powerupSlots': 3,
      'queuedBoxCount': 0,
      'activeEffects': [],
    },
  };

  @override
  Future<Map<String, dynamic>> fetchRaceMessages({
    required String identityToken,
    required String raceId,
    String? cursor,
    int? limit,
    String? kind,
  }) async => kind == 'SYSTEM'
      ? const {
          'messages': [
            {
              'id': 'e1',
              'eventType': 'RACE_STARTED',
              'body': 'The race is on!',
              'createdAt': '2026-07-25T10:00:00.000Z',
            },
          ],
        }
      : const {'messages': []};

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async =>
      const {'coins': 100, 'heldCoins': 0};
}

/// The control: the viewer IS one of the racers.
class _ParticipantApi extends _SpectateApi {
  _ParticipantApi() : super(myStatus: 'ACCEPTED');

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async {
    final base = await super.fetchRaceDetails(
      identityToken: identityToken,
      raceId: raceId,
    );
    return {
      ...base,
      'participants': const [
        {
          'userId': 'user-1',
          'displayName': 'Trail Walker',
          'status': 'ACCEPTED',
        },
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
  // Tall viewport: the race page is a long scroll and the ACTIVITY/CHAT tab
  // selector otherwise sits below the fold, where it can't be tapped.
  tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final auth = await _auth();
  await tester.pumpWidget(
    MaterialApp(
      home: RaceDetailScreen(
        key: UniqueKey(),
        authService: auth,
        raceId: 'matchup-race',
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _openChatTab(WidgetTester tester) async {
  await tester.tap(find.text('CHAT'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a spectator gets the activity feed and NO composer',
      (tester) async {
    await _pump(tester, _SpectateApi());

    // The activity feed a bracket-mate came here to read.
    expect(find.text('The race is on!'), findsOneWidget);

    await _openChatTab(tester);
    expect(find.byType(TextField), findsNothing);
    expect(find.text("You're spectating. Chat is read-only."), findsOneWidget);
  });

  testWidgets('a participant keeps the composer', (tester) async {
    await _pump(tester, _ParticipantApi());
    await _openChatTab(tester);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text("You're spectating. Chat is read-only."), findsNothing);
  });

  testWidgets(
      'a spectator stays read-only even if the backend claims ACCEPTED',
      (tester) async {
    // Spectator-ness comes from the participants list, not from `myStatus` —
    // a differently-versioned backend must not be able to hand a spectator a
    // composer whose posts would 403.
    await _pump(tester, _SpectateApi(myStatus: 'ACCEPTED'));
    await _openChatTab(tester);
    expect(find.byType(TextField), findsNothing);
    expect(find.text("You're spectating. Chat is read-only."), findsOneWidget);
  });

  testWidgets('a spectator sees no powerup or action affordances',
      (tester) async {
    await _pump(tester, _SpectateApi());
    expect(find.text('SPECTATING · READ-ONLY'), findsOneWidget);
    expect(find.text('POWERUPS'), findsNothing);
    expect(find.byIcon(Icons.more_horiz), findsNothing);
    expect(find.byIcon(Icons.notifications_active_rounded), findsNothing);
  });
}
