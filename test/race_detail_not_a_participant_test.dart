import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

/// Seeded-challenge inactivity pruning (spec §5 item 1).
///
/// A pruned participant's `RaceParticipant` row is hard-deleted server-side, so
/// `GET /races/:id/details` answers 403 "You are not a participant in this
/// race". Two moments matter:
///
///  * OPEN — a stale push/deep link lands on a race the user is no longer in.
///    The screen used to show a raw-message toast over "Failed to load race".
///  * MID-SESSION — the screen is already open and the 30s progress poll starts
///    403ing. That used to fire "Couldn’t refresh race progress." every 30s
///    forever, over a stale interactive board.
///
/// Both must land on ONE purpose-built state, and the mid-session case must
/// STOP the poll. Nothing here depends on a new backend field: the 403 and its
/// message already exist today.

class _NotAParticipantApi extends BackendApiService {
  _NotAParticipantApi({this.detailsFail = false, this.progressFail = false});

  /// 403 on the details load (the "opened a stale link" case).
  bool detailsFail;

  /// 403 on every progress fetch from now on (the mid-session case).
  bool progressFail;

  int progressCalls = 0;
  int detailsCalls = 0;

  static const forbidden = ApiException(
    'You are not a participant in this race',
    statusCode: 403,
  );

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async {
    detailsCalls += 1;
    if (detailsFail) throw forbidden;
    return {
      'id': raceId,
      'name': 'Daily Challenge',
      'seedKind': 'DAILY',
      'status': 'ACTIVE',
      'maxDurationDays': 1,
      'buyInAmount': 0,
      'payoutPreset': 'TOP_HALF',
      'potCoins': 0,
      'heldPotCoins': 0,
      'projectedPotCoins': 0,
      'myStatus': 'ACCEPTED',
      'isCreator': false,
      'powerupsEnabled': false,
      'endsAt': '2126-04-10T12:00:00.000Z',
      'participants': const [
        {'userId': 'me', 'displayName': 'Bara', 'status': 'ACCEPTED'},
        {'userId': 'u1', 'displayName': 'Runner 1', 'status': 'ACCEPTED'},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async {
    progressCalls += 1;
    if (progressFail) throw forbidden;
    return {
      'status': 'ACTIVE',
      'participants': const [
        {
          'userId': 'me',
          'displayName': 'Bara',
          'totalSteps': 5000.0,
          'placement': 2,
          'finishedAt': null,
        },
        {
          'userId': 'u1',
          'displayName': 'Runner 1',
          'totalSteps': 9000.0,
          'placement': 1,
          'finishedAt': null,
        },
      ],
      'powerupData': const {
        'enabled': false,
        'inventory': [],
        'powerupSlots': 3,
        'queuedBoxCount': 0,
        'activeEffects': [],
      },
    };
  }

  // The chat + activity feeds poll every 5s once an ACTIVE race loads; keep
  // them silent so virtual time can advance without hitting the network.
  @override
  Future<Map<String, dynamic>> fetchRaceMessages({
    required String identityToken,
    required String raceId,
    String? cursor,
    int? limit,
    String? kind,
  }) async => const {'messages': [], 'events': []};

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
    'auth_identity_token': 'token',
    'auth_user_identifier': 'user',
    'auth_session_token': 'session',
    'auth_backend_user_id': 'me',
    'auth_display_name': 'Bara',
    'auth_coins': 0,
    'auth_held_coins': 0,
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Future<void> _pump(WidgetTester tester, _NotAParticipantApi api) async {
  await tester.binding.setSurfaceSize(const Size(600, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: RaceDetailScreen(
        authService: await _auth(),
        raceId: 'race-daily',
        backendApiService: api,
      ),
    ),
  );
  // Bounded pumps: the hero's spinning coin animates forever.
  await tester.pump();
  await tester.pump();
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // PackageInfo.fromPlatform() never resolves inside testWidgets' fake-async
    // zone; without this any activation-analytics write hangs silently.
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.bara.app',
      version: '2.1.2',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('a 403 on the details load renders the not-in-this-race state', (
    tester,
  ) async {
    final api = _NotAParticipantApi(detailsFail: true, progressFail: true);
    await _pump(tester, api);

    final state = find.byKey(const Key('race-not-a-participant'));
    expect(state, findsOneWidget);
    expect(
      find.descendant(
        of: state,
        matching: find.text('You’re not in this race'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: state, matching: find.text('Find it on Races')),
      findsOneWidget,
    );

    // The old generic body and the raw server message are both gone.
    expect(find.text('Failed to load race'), findsNothing);
    expect(find.text('You are not a participant in this race'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);

    await _teardown(tester);
  });

  testWidgets('a non-403 details failure keeps the generic failed-to-load body', (
    tester,
  ) async {
    // Only 403 means "you are not in this race". A 500 or a dropped connection
    // must not tell the user they were removed.
    final api = _Failing500Api();
    await tester.binding.setSurfaceSize(const Size(600, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: RaceDetailScreen(
          authService: await _auth(),
          raceId: 'race-daily',
          backendApiService: api,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('race-not-a-participant')), findsNothing);
    expect(find.text('Failed to load race'), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets('a mid-session 403 swaps to the state AND stops the 30s poll', (
    tester,
  ) async {
    final api = _NotAParticipantApi();
    await _pump(tester, api);

    // The board loaded normally — the user is still in the race.
    expect(find.byKey(const Key('race-not-a-participant')), findsNothing);
    expect(api.progressCalls, 1);

    // The sweep removes them. The next poll 403s.
    api.progressFail = true;
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(api.progressCalls, 2);

    expect(find.byKey(const Key('race-not-a-participant')), findsOneWidget);
    expect(
      find.text('You’re not in this race'),
      findsOneWidget,
    );

    // …and the poll is dead: no repeating 403 every 30s behind the state.
    await tester.pump(const Duration(seconds: 120));
    expect(api.progressCalls, 2);
    expect(tester.takeException(), isNull);

    await _teardown(tester);
  });
}

class _Failing500Api extends _NotAParticipantApi {
  _Failing500Api() : super(detailsFail: true, progressFail: true);

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async {
    throw const ApiException('Something went wrong.', statusCode: 500);
  }

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async {
    throw const ApiException('Something went wrong.', statusCode: 500);
  }
}
