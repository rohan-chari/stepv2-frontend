import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/pill_button.dart';

// 1.1.7 — a PENDING race the creator scheduled for the future must show a
// "Starts at <local time>" line and must NOT offer an enabled manual Start
// button (the backend rejects an early start; the UI surfaces that). Read
// scheduledStartAt defensively — older payloads omit it entirely.

class _ScheduledFutureRaceApi extends BackendApiService {
  _ScheduledFutureRaceApi({required this.scheduledStartAt});

  final String? scheduledStartAt;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async {
    return {
      'id': raceId,
      'name': 'Future Race',
      'status': 'PENDING',
      'targetSteps': 50000,
      'maxDurationDays': 7,
      'buyInAmount': 0,
      'payoutPreset': 'WINNER_TAKES_ALL',
      'potCoins': 0,
      'myStatus': 'ACCEPTED',
      'isCreator': true,
      if (scheduledStartAt != null) 'scheduledStartAt': scheduledStartAt,
      'participants': const [
        {'userId': 'user-1', 'displayName': 'Trail Walker', 'status': 'ACCEPTED'},
        {'userId': 'user-2', 'displayName': 'Hill Climber', 'status': 'ACCEPTED'},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    return const {'coins': 320, 'heldCoins': 0};
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
    'shows "Starts at" and disables manual Start for a future-scheduled PENDING race',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final future = DateTime.now().toUtc().add(const Duration(days: 2));
      final api = _ScheduledFutureRaceApi(
        scheduledStartAt: future.toIso8601String(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-sched',
            backendApiService: api,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // "Starts at ..." copy is shown.
      expect(find.textContaining('Starts at'), findsOneWidget);

      // The manual Start button is either absent or disabled (onPressed == null).
      final startFinder = find.widgetWithText(PillButton, 'START RACE');
      if (startFinder.evaluate().isNotEmpty) {
        final button = tester.widget<PillButton>(startFinder);
        expect(
          button.onPressed,
          isNull,
          reason: 'manual Start must be disabled until the scheduled time',
        );
      }
    },
  );

  testWidgets(
    'enables manual Start for a PENDING race with no scheduledStartAt (existing behavior)',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final api = _ScheduledFutureRaceApi(scheduledStartAt: null);

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-instant',
            backendApiService: api,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Starts at'), findsNothing);

      final startFinder = find.widgetWithText(PillButton, 'START RACE');
      expect(startFinder, findsOneWidget);
      final button = tester.widget<PillButton>(startFinder);
      expect(
        button.onPressed,
        isNotNull,
        reason: 'an unscheduled PENDING race must keep its enabled Start button',
      );
    },
  );
}
