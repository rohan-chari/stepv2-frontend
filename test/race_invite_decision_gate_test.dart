import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/race_invite_decision_gate.dart';

class _GateApi extends BackendApiService {
  _GateApi(this.data);
  Map<String, dynamic> data;
  bool failFetch = false;
  bool failResponse = false;
  ApiException? responseError;
  int fetchCalls = 0;
  final responses = <String>[];

  @override
  Future<Map<String, dynamic>> fetchRaces({
    required String identityToken,
  }) async {
    fetchCalls += 1;
    if (failFetch) throw const ApiException('offline');
    return data;
  }

  @override
  Future<Map<String, dynamic>> respondToTournamentInvite({
    required String identityToken,
    required String tournamentId,
    required bool accept,
  }) async {
    if (failResponse) throw const ApiException('answer failed');
    if (responseError case final error?) throw error;
    responses.add('tournament:$tournamentId:$accept');
    data = {...data, 'tournaments': const <Map<String, dynamic>>[]};
    return const {};
  }

  @override
  Future<Map<String, dynamic>> respondToRaceInvite({
    required String identityToken,
    required String raceId,
    required bool accept,
  }) async {
    if (failResponse) throw const ApiException('answer failed');
    if (responseError case final error?) throw error;
    responses.add('race:$raceId:$accept');
    data = {
      ...data,
      'pending': const <Map<String, dynamic>>[],
      'active': const <Map<String, dynamic>>[],
    };
    return const {};
  }
}

Map<String, dynamic> _data({bool invites = true}) => {
  'active': const <Map<String, dynamic>>[],
  'completed': const <Map<String, dynamic>>[],
  'pending': invites
      ? [
          {
            'id': 'race-1',
            'name': 'Morning Dash',
            'myStatus': 'INVITED',
            'maxDurationDays': 3,
            'buyInAmount': 100,
            'myInviteExpiresAt': '2026-08-12T20:00:00.000Z',
            'creator': {'displayName': 'RaceHost'},
          },
        ]
      : const <Map<String, dynamic>>[],
  'tournaments': invites
      ? [
          {
            'id': 'tournament-1',
            'name': 'Bracket First',
            'myStatus': 'INVITED',
            'createdAt': '2026-08-11T19:00:00.000Z',
            'creator': {'displayName': 'BracketHost'},
          },
        ]
      : const <Map<String, dynamic>>[],
};

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'token',
    'auth_session_token': 'session',
    'auth_backend_user_id': 'me',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Widget _gate({
  required AuthService auth,
  required _GateApi api,
  required bool enabled,
  required bool active,
  int epoch = 1,
  VoidCallback? onHome,
}) => MaterialApp(
  home: RaceInviteDecisionGate(
    enabled: enabled,
    active: active,
    entryEpoch: epoch,
    authService: auth,
    backendApiService: api,
    onVerifiedData: (_) {},
    onExitHome: onHome ?? () {},
    onBlockingChanged: (_) {},
    child: const Scaffold(body: Text('STALE RACE LIST')),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.bara.app',
      version: '3.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets(
    'opaque gate orders tournament before race and reveals after both',
    (tester) async {
      final auth = await _auth();
      final api = _GateApi(_data());
      await tester.pumpWidget(
        _gate(auth: auth, api: api, enabled: true, active: false),
      );
      expect(find.text('STALE RACE LIST'), findsNothing);

      await tester.pumpWidget(
        _gate(auth: auth, api: api, enabled: true, active: true),
      );
      await tester.pump();
      expect(find.text('Bracket First'), findsOneWidget);
      expect(find.text('Morning Dash'), findsNothing);

      await tester.tap(find.byKey(const Key('races-gate-accept')));
      await tester.pump();
      expect(api.responses, ['tournament:tournament-1:true']);
      expect(find.text('Morning Dash'), findsOneWidget);

      await tester.tap(find.byKey(const Key('races-gate-decline')));
      await tester.pump();
      expect(api.responses.last, 'race:race-1:false');
      expect(find.text('STALE RACE LIST'), findsOneWidget);
    },
  );

  testWidgets(
    'paid tournament preflight shows its actual buy-in and accepts normally',
    (tester) async {
      final auth = await _auth();
      final api = _GateApi({
        'active': const <Map<String, dynamic>>[],
        'pending': const <Map<String, dynamic>>[],
        'completed': const <Map<String, dynamic>>[],
        'tournaments': [
          {
            'id': 'paid-tournament-invite',
            'name': 'Paid Bracket',
            'myStatus': 'INVITED',
            'buyInAmount': 75,
            'createdAt': '2026-08-12T12:00:00.000Z',
            'creator': {'displayName': 'BracketHost'},
          },
        ],
      });

      await tester.pumpWidget(
        _gate(auth: auth, api: api, enabled: true, active: true),
      );
      await tester.pump();

      expect(find.text('75 GOLD'), findsOneWidget);
      expect(find.text('ACCEPT · 75'), findsOneWidget);
      expect(find.text('ACCEPT · 0'), findsNothing);

      await tester.tap(find.byKey(const Key('races-gate-accept')));
      await tester.pump();

      expect(api.responses, ['tournament:paid-tournament-invite:true']);
      expect(find.text('STALE RACE LIST'), findsOneWidget);
    },
  );

  testWidgets('initial error never reveals stale list and can exit Home', (
    tester,
  ) async {
    final auth = await _auth();
    final api = _GateApi(_data())..failFetch = true;
    var exited = false;
    await tester.pumpWidget(
      _gate(auth: auth, api: api, enabled: true, active: false),
    );
    await tester.pumpWidget(
      _gate(
        auth: auth,
        api: api,
        enabled: true,
        active: true,
        onHome: () => exited = true,
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('races-gate-retry')), findsOneWidget);
    expect(find.text('STALE RACE LIST'), findsNothing);
    await tester.tap(find.byKey(const Key('races-gate-home')));
    expect(exited, isTrue);
  });

  testWidgets('answer error retains the current invite and blocks Races', (
    tester,
  ) async {
    final auth = await _auth();
    final api = _GateApi(_data())..failResponse = true;
    await tester.pumpWidget(
      _gate(auth: auth, api: api, enabled: true, active: false),
    );
    await tester.pumpWidget(
      _gate(auth: auth, api: api, enabled: true, active: true),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('races-gate-accept')));
    await tester.pump();

    expect(find.text('Bracket First'), findsOneWidget);
    expect(find.text('answer failed'), findsOneWidget);
    expect(find.byKey(const Key('races-gate-answer-retry')), findsOneWidget);
    expect(find.byKey(const Key('races-gate-answer-home')), findsOneWidget);
    expect(find.byKey(const Key('races-gate-accept')), findsOneWidget);
    expect(find.text('STALE RACE LIST'), findsNothing);
  });

  testWidgets(
    'race invitations are scanned and deduped across pending and active',
    (tester) async {
      final auth = await _auth();
      final invited = {
        'id': 'race-active-invite',
        'name': 'Already Underway',
        'myStatus': 'INVITED',
        'status': 'ACTIVE',
        'createdAt': '2026-08-11T20:00:00.000Z',
        'creator': {'displayName': 'RaceHost'},
      };
      final api = _GateApi({
        'pending': [invited],
        'active': [invited],
        'completed': const [],
        'tournaments': const [],
      });

      await tester.pumpWidget(
        _gate(auth: auth, api: api, enabled: true, active: true),
      );
      await tester.pump();

      expect(find.text('Already Underway'), findsOneWidget);
      expect(find.text('UNDERWAY'), findsOneWidget);
      await tester.tap(find.byKey(const Key('races-gate-decline')));
      await tester.pump();
      expect(api.responses, ['race:race-active-invite:false']);
      expect(find.text('STALE RACE LIST'), findsOneWidget);
    },
  );

  testWidgets(
    'only ALREADY_RESPONDED refreshes instead of displaying the error',
    (tester) async {
      final auth = await _auth();
      final api = _GateApi(_data())
        ..responseError = const ApiException(
          'You already responded',
          statusCode: 409,
          code: 'ALREADY_RESPONDED',
        );
      await tester.pumpWidget(
        _gate(auth: auth, api: api, enabled: true, active: true),
      );
      await tester.pump();
      api.data = _data(invites: false);
      await tester.tap(find.byKey(const Key('races-gate-accept')));
      await tester.pump();

      expect(api.fetchCalls, 2);
      expect(find.text('STALE RACE LIST'), findsOneWidget);
    },
  );

  testWidgets('other 400 and 409 action errors retain and explain the invite', (
    tester,
  ) async {
    for (final error in const [
      ApiException('That team is full', statusCode: 409, code: 'TEAM_FULL'),
      ApiException(
        'This race cannot accept responses',
        statusCode: 400,
        code: 'RACE_NOT_ACCEPTING',
      ),
    ]) {
      final auth = await _auth();
      final api = _GateApi(_data())..responseError = error;
      await tester.pumpWidget(
        _gate(auth: auth, api: api, enabled: true, active: true),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('races-gate-accept')));
      await tester.pump();

      expect(find.text('Bracket First'), findsOneWidget);
      expect(find.text(error.message), findsOneWidget);
      expect(api.fetchCalls, 1);
      expect(find.byKey(const Key('races-gate-answer-home')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('tournament invite shows matchupDurationDays', (tester) async {
    final auth = await _auth();
    final api = _GateApi({
      'pending': const [],
      'active': const [],
      'completed': const [],
      'tournaments': [
        {
          'id': 'tournament-duration',
          'name': 'Five Day Bracket',
          'myStatus': 'INVITED',
          'createdAt': '2026-08-11T19:00:00.000Z',
          'matchupDurationDays': 5,
          'maxDurationDays': 99,
          'creator': {'displayName': 'BracketHost'},
        },
      ],
    });

    await tester.pumpWidget(
      _gate(auth: auth, api: api, enabled: true, active: true),
    );
    await tester.pump();

    expect(find.text('5 DAYS'), findsOneWidget);
    expect(find.text('99 DAYS'), findsNothing);
  });

  testWidgets('unsupported flag-off branch preserves inline child', (
    tester,
  ) async {
    final auth = await _auth();
    await tester.pumpWidget(
      _gate(auth: auth, api: _GateApi(_data()), enabled: false, active: true),
    );
    expect(find.text('STALE RACE LIST'), findsOneWidget);
    expect(find.byKey(const Key('races-invite-gate-status')), findsNothing);
  });

  testWidgets('active initial mount checks and ignores malformed invite rows', (
    tester,
  ) async {
    final auth = await _auth();
    final api = _GateApi({
      'active': const [],
      'pending': [
        'bad',
        {7: 'non-string key'},
      ],
      'tournaments': const [null, 'bad'],
    });

    await tester.pumpWidget(
      _gate(auth: auth, api: api, enabled: true, active: true),
    );
    await tester.pump();

    expect(find.text('STALE RACE LIST'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
