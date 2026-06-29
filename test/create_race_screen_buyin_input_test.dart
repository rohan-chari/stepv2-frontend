import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    int maxDurationDays = 7,
    bool powerupsEnabled = false,
    int? powerupStepInterval,
    int buyInAmount = 0,
    String payoutPreset = 'WINNER_TAKES_ALL',
    bool isPublic = false,
    int? maxParticipants = 10,
    DateTime? scheduledStartAt,
  }) async {
    lastCreateRaceCall = {
      'identityToken': identityToken,
      'name': name,

      'maxDurationDays': maxDurationDays,
      'powerupsEnabled': powerupsEnabled,
      'powerupStepInterval': powerupStepInterval,
      'buyInAmount': buyInAmount,
      'payoutPreset': payoutPreset,
      'isPublic': isPublic,
      'maxParticipants': maxParticipants,
    };
    return {
      'race': {'id': 'race-1', 'name': name},
    };
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    return const {'coins': 320, 'heldCoins': 100};
  }
}

Future<AuthService> _createAuthService({int coins = 420}) async {
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

Finder _buyInTextFieldFinder() {
  // Buy-in field is the third TextField on screen (name, steps, buy-in).
  return find.byType(TextField).at(2);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Buy-in input is hidden when disabled and shown when enabled',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      await tester.pumpWidget(
        MaterialApp(
          home: CreateRaceScreen(
            authService: authService,
            backendApiService: _FakeBackendApiService(),
          ),
        ),
      );

      // Only 2 TextFields when buy-in disabled (name + steps).
      expect(find.byType(TextField), findsNWidgets(2));

      await tester.tap(find.text('BUY-IN'));
      await tester.pump();

      // Now buy-in TextField is rendered as third field.
      expect(find.byType(TextField), findsNWidgets(3));
    },
  );

  testWidgets(
    'Buy-in field accepts arbitrary numeric input (150) and is sent on submit',
    (WidgetTester tester) async {
      final authService = await _createAuthService(coins: 5000);
      final backend = _FakeBackendApiService();

      await tester.pumpWidget(
        MaterialApp(
          home: CreateRaceScreen(
            authService: authService,
            backendApiService: backend,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField).at(0), 'Gold Rush');
      await tester.enterText(find.byType(TextField).at(1), '100000');

      await tester.tap(find.text('BUY-IN'));
      await tester.pump();

      final buyIn = _buyInTextFieldFinder();
      await tester.ensureVisible(buyIn);
      await tester.enterText(buyIn, '150');
      await tester.pump();

      await tester.ensureVisible(find.text('CREATE RACE'));
      await tester.tap(find.text('CREATE RACE'));
      await tester.pumpAndSettle();

      expect(backend.lastCreateRaceCall, isNotNull);
      expect(backend.lastCreateRaceCall!['buyInAmount'], 150);
    },
  );

  testWidgets(
    'Buy-in field filters non-numeric input via digitsOnly formatter',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      await tester.pumpWidget(
        MaterialApp(
          home: CreateRaceScreen(
            authService: authService,
            backendApiService: _FakeBackendApiService(),
          ),
        ),
      );

      await tester.tap(find.text('BUY-IN'));
      await tester.pump();

      final buyInFinder = _buyInTextFieldFinder();
      final buyInWidget = tester.widget<TextField>(buyInFinder);

      expect(buyInWidget.keyboardType, TextInputType.number);
      expect(
        buyInWidget.inputFormatters!.any(
          (f) => f is FilteringTextInputFormatter,
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'Submission blocked when buy-in exceeds user coin balance',
    (WidgetTester tester) async {
      final authService = await _createAuthService(coins: 100);
      final backend = _FakeBackendApiService();

      await tester.pumpWidget(
        MaterialApp(
          home: CreateRaceScreen(
            authService: authService,
            backendApiService: backend,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField).at(0), 'Gold Rush');
      await tester.enterText(find.byType(TextField).at(1), '100000');

      await tester.tap(find.text('BUY-IN'));
      await tester.pump();

      final buyIn = _buyInTextFieldFinder();
      await tester.ensureVisible(buyIn);
      await tester.enterText(buyIn, '9999');
      await tester.pump();

      await tester.ensureVisible(find.text('CREATE RACE'));
      await tester.tap(find.text('CREATE RACE'));
      await tester.pump();

      expect(backend.lastCreateRaceCall, isNull);
    },
  );
}
