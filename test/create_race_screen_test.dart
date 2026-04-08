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
  }) async {
    lastCreateRaceCall = {
      'identityToken': identityToken,
      'name': name,
      'targetSteps': targetSteps,
      'maxDurationDays': maxDurationDays,
      'powerupsEnabled': powerupsEnabled,
      'powerupStepInterval': powerupStepInterval,
      'buyInAmount': buyInAmount,
      'payoutPreset': payoutPreset,
    };

    return {
      'race': {
        'id': 'race-1',
        'name': name,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    return const {'coins': 320, 'heldCoins': 100};
  }
}

Future<AuthService> _createAuthService() async {
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

  testWidgets('CreateRaceScreen sends buy-in and payout preset selections', (
    WidgetTester tester,
  ) async {
    final authService = await _createAuthService();
    final backendApiService = _FakeBackendApiService();

    await tester.pumpWidget(
      MaterialApp(
        home: CreateRaceScreen(
          authService: authService,
          backendApiService: backendApiService,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).at(0), 'Gold Rush');
    await tester.enterText(find.byType(TextField).at(1), '100000');

    await tester.tap(find.text('BUY-IN'));
    await tester.pump();
    await tester.ensureVisible(find.text('100'));
    await tester.tap(find.text('100'));
    await tester.pump();
    await tester.ensureVisible(find.text('TOP 3 70/20/10'));
    await tester.tap(find.text('TOP 3 70/20/10'));
    await tester.pump();

    await tester.ensureVisible(find.text('CREATE RACE'));
    await tester.tap(find.text('CREATE RACE'));
    await tester.pumpAndSettle();

    expect(backendApiService.lastCreateRaceCall, isNotNull);
    expect(backendApiService.lastCreateRaceCall!['buyInAmount'], 100);
    expect(
      backendApiService.lastCreateRaceCall!['payoutPreset'],
      'TOP3_70_20_10',
    );
  });
}
