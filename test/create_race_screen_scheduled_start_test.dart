import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/create_race_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// 1.1.7 — optional scheduled-start picker on Create Race. When the user picks a
// future date/time, createRace must send scheduledStartAt; when they leave it
// off, the param must be omitted (preserving the instant/manual race behavior).
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
    int maxParticipants = 10,
    DateTime? scheduledStartAt,
  }) async {
    lastCreateRaceCall = {
      'name': name,
      'scheduledStartAt': scheduledStartAt,
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

  testWidgets('CreateRaceScreen omits scheduledStartAt when no time is picked', (
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

    await tester.enterText(find.byType(TextField).at(0), 'Instant Race');

    await tester.ensureVisible(find.text('CREATE RACE'));
    await tester.tap(find.text('CREATE RACE'));
    await tester.pumpAndSettle();

    expect(backendApiService.lastCreateRaceCall, isNotNull);
    expect(backendApiService.lastCreateRaceCall!['scheduledStartAt'], isNull);
  });

  testWidgets(
    'CreateRaceScreen sends scheduledStartAt when a future time is picked',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final backendApiService = _FakeBackendApiService();

      final screen = CreateRaceScreen(
        authService: authService,
        backendApiService: backendApiService,
      );

      await tester.pumpWidget(MaterialApp(home: screen));

      await tester.enterText(find.byType(TextField).at(0), 'Scheduled Race');

      // Drive the scheduled-start selection directly via the screen's test hook
      // so the test doesn't depend on the platform date/time picker dialog.
      final state = tester.state<CreateRaceScreenState>(
        find.byType(CreateRaceScreen),
      );
      final picked = DateTime.now().add(const Duration(days: 2));
      state.debugSetScheduledStart(picked);
      await tester.pump();

      await tester.ensureVisible(find.text('CREATE RACE'));
      await tester.tap(find.text('CREATE RACE'));
      await tester.pumpAndSettle();

      expect(backendApiService.lastCreateRaceCall, isNotNull);
      final sent =
          backendApiService.lastCreateRaceCall!['scheduledStartAt']
              as DateTime?;
      expect(sent, isNotNull);
      expect(sent!.isAfter(DateTime.now()), isTrue);
    },
  );
}
