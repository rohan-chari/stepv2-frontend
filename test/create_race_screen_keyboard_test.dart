import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/create_race_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _FakeBackendApiService extends BackendApiService {
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
    return {
      'race': {'id': 'race-1', 'name': name},
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

  testWidgets(
    'SingleChildScrollView dismisses keyboard on drag',
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

      final scrollView = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(
        scrollView.keyboardDismissBehavior,
        ScrollViewKeyboardDismissBehavior.onDrag,
      );
    },
  );

  testWidgets(
    'Tapping outside focused TextField dismisses keyboard',
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

      // Focus the race name field
      await tester.tap(find.byType(TextField).at(0));
      await tester.pump();
      expect(tester.binding.focusManager.primaryFocus, isNotNull);
      expect(
        tester.binding.focusManager.primaryFocus!.hasPrimaryFocus,
        isTrue,
      );

      // Tap on the NEW RACE header text area (outside of any TextField)
      await tester.tap(find.text('NEW RACE'));
      await tester.pump();

      final focus = tester.binding.focusManager.primaryFocus;
      // Either no primary focus or focus is no longer on an editable.
      final stillEditing =
          focus != null && focus.context?.widget is EditableText;
      expect(stillEditing, isFalse);
    },
  );
}
