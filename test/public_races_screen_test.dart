import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/public_races_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _FakePublicRacesApi extends BackendApiService {
  bool joined = false;
  bool failFetchMe = false;

  @override
  Future<List<Map<String, dynamic>>> fetchPublicRaces({
    required String identityToken,
  }) async {
    return [
      {
        'id': 'race-1',
        'name': 'Gold Sprint',
        'targetSteps': 50000,
        'participantCount': 1,
        'maxParticipants': 10,
        'buyInAmount': 100,
        'creator': {'displayName': 'RaceMaker'},
        'powerupsEnabled': true,
      },
    ];
  }

  @override
  Future<Map<String, dynamic>> joinPublicRace({
    required String identityToken,
    required String raceId,
    bool onboarding = false,
  }) async {
    joined = true;
    return {
      'participant': {'id': 'rp-1', 'raceId': raceId},
    };
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    if (failFetchMe) throw const ApiException('wallet refresh failed');
    return const {'coins': 320, 'heldCoins': 100};
  }
}

Future<AuthService> _authService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_coins': 420,
    'auth_held_coins': 0,
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('joining a paid public race refreshes wallet state', (
    WidgetTester tester,
  ) async {
    final authService = await _authService();
    final api = _FakePublicRacesApi();

    await tester.pumpWidget(
      MaterialApp(
        home: PublicRacesScreen(
          authService: authService,
          backendApiService: api,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Gold Sprint'.toUpperCase()), findsOneWidget);
    await tester.tap(find.text('JOIN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('LOCK IT IN'));
    await tester.pumpAndSettle();

    expect(api.joined, isTrue);
    expect(authService.coins, 320);
    expect(authService.heldCoins, 100);
  });

  testWidgets(
    'successful public join is not undone by wallet refresh failure',
    (WidgetTester tester) async {
      final authService = await _authService();
      final api = _FakePublicRacesApi()..failFetchMe = true;

      await tester.pumpWidget(
        MaterialApp(
          home: PublicRacesScreen(
            authService: authService,
            backendApiService: api,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('JOIN'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('LOCK IT IN'));
      await tester.pumpAndSettle();

      expect(api.joined, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
