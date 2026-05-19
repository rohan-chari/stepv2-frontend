import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/create_race_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _FakeBackendApiService extends BackendApiService {
  Map<String, dynamic>? lastCreateRaceCall;

  @override
  Future<Map<String, dynamic>> createRace({
    required String identityToken,
    required String name,
    required int targetSteps,
    int maxDurationDays = 7,
    bool powerupsEnabled = false,
    int? powerupStepInterval,
    int buyInAmount = 0,
    String payoutPreset = 'WINNER_TAKES_ALL',
    bool isPublic = false,
    int maxParticipants = 10,
  }) async {
    lastCreateRaceCall = {'buyInAmount': buyInAmount};
    return {
      'race': {'id': 'race-1', 'name': name},
    };
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    return const {'coins': 5000, 'heldCoins': 0};
  }
}

Future<AuthService> _createAuthService({int coins = 5000}) async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_coins': coins,
    'auth_held_coins': 0,
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Submission blocked when buy-in exceeds 200 coins (max)',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final backend = _FakeBackendApiService();

      await tester.pumpWidget(
        MaterialApp(
          home: CreateRaceScreen(
            authService: authService,
            backendApiService: backend,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField).at(0), 'Big Race');
      await tester.enterText(find.byType(TextField).at(1), '5000');

      await tester.tap(find.text('BUY-IN'));
      await tester.pump();

      final buyIn = find.byType(TextField).at(2);
      await tester.ensureVisible(buyIn);
      await tester.enterText(buyIn, '201');
      await tester.pump();

      await tester.ensureVisible(find.text('CREATE RACE'));
      await tester.tap(find.text('CREATE RACE'));
      await tester.pump();

      expect(backend.lastCreateRaceCall, isNull);
    },
  );

  testWidgets(
    'Submission allowed when buy-in is exactly 200 coins (boundary)',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final backend = _FakeBackendApiService();

      await tester.pumpWidget(
        MaterialApp(
          home: CreateRaceScreen(
            authService: authService,
            backendApiService: backend,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField).at(0), 'Big Race');
      await tester.enterText(find.byType(TextField).at(1), '5000');

      await tester.tap(find.text('BUY-IN'));
      await tester.pump();

      final buyIn = find.byType(TextField).at(2);
      await tester.ensureVisible(buyIn);
      await tester.enterText(buyIn, '200');
      await tester.pump();

      await tester.ensureVisible(find.text('CREATE RACE'));
      await tester.tap(find.text('CREATE RACE'));
      await tester.pumpAndSettle();

      expect(backend.lastCreateRaceCall, isNotNull);
      expect(backend.lastCreateRaceCall!['buyInAmount'], 200);
    },
  );
}
