import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/discovery_join_coordinator.dart';

const _canonicalFundedPool = <String, dynamic>{
  'coins': 0,
  'projected': true,
  'atMax': false,
  'playerCount': 1,
  'durationDays': 3,
  'durationPoints': 2,
  'coinUnit': 20,
  'maxCoins': 16000,
  'funded': true,
};

class _JoinApi extends BackendApiService {
  _JoinApi({this.failure});

  final ApiException? failure;
  int raceJoins = 0;
  int tournamentJoins = 0;

  @override
  Future<Map<String, dynamic>> joinPublicRace({
    required String identityToken,
    required String raceId,
    bool onboarding = false,
  }) async {
    raceJoins += 1;
    if (failure case final error?) throw error;
    return {
      'race': {'id': raceId, 'status': 'PENDING'},
    };
  }

  @override
  Future<Map<String, dynamic>> joinTournament({
    required String identityToken,
    required String tournamentId,
  }) async {
    tournamentJoins += 1;
    if (failure case final error?) throw error;
    return {
      'tournament': {'id': tournamentId, 'status': 'PENDING'},
    };
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async =>
      const {'coins': 200, 'heldCoins': 0};
}

Future<AuthService> _authWithCoins(int coins) async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'identity',
    'auth_user_identifier': 'platform-user',
    'auth_session_token': 'session',
    'auth_backend_user_id': 'user-1',
    'auth_coins': coins,
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Future<void> _pumpJoinButton(
  WidgetTester tester, {
  required AuthService auth,
  required BackendApiService api,
  required Map<String, dynamic> payload,
  required DiscoveryJoinTarget target,
  bool tournamentFeatured = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final coordinator = DiscoveryJoinCoordinator(
                authService: auth,
                backendApiService: api,
              );
              if (target == DiscoveryJoinTarget.race) {
                await coordinator.joinRace(context, payload);
              } else {
                await coordinator.joinTournament(
                  context,
                  payload,
                  featured: tournamentFeatured,
                );
              }
            },
            child: const Text('JOIN'),
          ),
        ),
      ),
    ),
  );
}

Map<String, dynamic> _payload(
  DiscoveryJoinTarget target,
  Map<String, dynamic>? prizePool,
) => {
  'id': target == DiscoveryJoinTarget.race ? 'race-1' : 'tournament-1',
  'status': 'PENDING',
  'buyInAmount': 100,
  'prizePool': prizePool,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final target in DiscoveryJoinTarget.values) {
    testWidgets('${target.name} shows the funded exposure limit as one toast', (
      tester,
    ) async {
      final auth = await _authWithCoins(0);
      final api = _JoinApi(
        failure: const ApiException(
          'Conflict',
          statusCode: 409,
          code: 'FUNDED_EXPOSURE_LIMIT',
        ),
      );
      await _pumpJoinButton(
        tester,
        auth: auth,
        api: api,
        payload: _payload(target, _canonicalFundedPool),
        target: target,
      );

      await tester.tap(find.text('JOIN'));
      await tester.pump();

      expect(
        find.text(
          'Finish or leave another funded race before joining this one.',
        ),
        findsOneWidget,
      );
      expect(find.text('Conflict'), findsNothing);
    });

    testWidgets(
      '${target.name} malformed or explicitly unfunded pools retain buy-in confirmation',
      (tester) async {
        for (final pool in <Map<String, dynamic>>[
          <String, dynamic>{},
          {..._canonicalFundedPool, 'funded': false},
          {..._canonicalFundedPool, 'coins': 'invalid'},
        ]) {
          final auth = await _authWithCoins(200);
          final api = _JoinApi();
          await _pumpJoinButton(
            tester,
            auth: auth,
            api: api,
            payload: _payload(target, pool),
            target: target,
          );

          await tester.tap(find.text('JOIN'));
          await tester.pump();

          expect(find.text('100 GOLD BUY-IN'), findsOneWidget);
          expect(api.raceJoins + api.tournamentJoins, 0);
          await tester.tap(find.text('NEVER MIND'));
          await tester.pump();
        }
      },
    );

    testWidgets(
      '${target.name} malformed pool retains insufficient-balance guard',
      (tester) async {
        final auth = await _authWithCoins(50);
        final api = _JoinApi();
        await _pumpJoinButton(
          tester,
          auth: auth,
          api: api,
          payload: _payload(target, const {}),
          target: target,
        );

        await tester.tap(find.text('JOIN'));
        await tester.pump();

        expect(find.text('Not enough gold for this buy-in'), findsOneWidget);
        expect(find.text('100 GOLD BUY-IN'), findsNothing);
        expect(api.raceJoins + api.tournamentJoins, 0);
      },
    );

    testWidgets(
      '${target.name} canonical zero-coin funded pool joins one-tap',
      (tester) async {
        final auth = await _authWithCoins(0);
        final api = _JoinApi();
        await _pumpJoinButton(
          tester,
          auth: auth,
          api: api,
          payload: _payload(target, _canonicalFundedPool),
          target: target,
        );

        await tester.tap(find.text('JOIN'));
        await tester.pump();

        expect(find.text('100 GOLD BUY-IN'), findsNothing);
        expect(find.text('Not enough gold for this buy-in'), findsNothing);
        expect(api.raceJoins + api.tournamentJoins, 1);
      },
    );
  }

  testWidgets(
    'featured tournament malformed or unfunded pools retain buy-in safeguards',
    (tester) async {
      for (final pool in <Map<String, dynamic>>[
        <String, dynamic>{},
        {..._canonicalFundedPool, 'funded': false},
        {..._canonicalFundedPool, 'coins': 'invalid'},
      ]) {
        final auth = await _authWithCoins(200);
        final api = _JoinApi();
        await _pumpJoinButton(
          tester,
          auth: auth,
          api: api,
          payload: _payload(DiscoveryJoinTarget.tournament, pool),
          target: DiscoveryJoinTarget.tournament,
          tournamentFeatured: true,
        );

        await tester.tap(find.text('JOIN'));
        await tester.pump();

        expect(find.text('100 GOLD BUY-IN'), findsOneWidget);
        expect(api.tournamentJoins, 0);
        await tester.tap(find.text('NEVER MIND'));
        await tester.pump();
      }

      final auth = await _authWithCoins(50);
      final api = _JoinApi();
      await _pumpJoinButton(
        tester,
        auth: auth,
        api: api,
        payload: _payload(DiscoveryJoinTarget.tournament, const {}),
        target: DiscoveryJoinTarget.tournament,
        tournamentFeatured: true,
      );
      await tester.tap(find.text('JOIN'));
      await tester.pump();
      expect(find.text('Not enough gold for this buy-in'), findsOneWidget);
      expect(api.tournamentJoins, 0);
    },
  );

  testWidgets(
    'featured tournament canonical funded zero pool remains one-tap',
    (tester) async {
      final auth = await _authWithCoins(0);
      final api = _JoinApi();
      await _pumpJoinButton(
        tester,
        auth: auth,
        api: api,
        payload: _payload(DiscoveryJoinTarget.tournament, _canonicalFundedPool),
        target: DiscoveryJoinTarget.tournament,
        tournamentFeatured: true,
      );

      await tester.tap(find.text('JOIN'));
      await tester.pump();

      expect(find.text('100 GOLD BUY-IN'), findsNothing);
      expect(find.text('Not enough gold for this buy-in'), findsNothing);
      expect(api.tournamentJoins, 1);
    },
  );
}
