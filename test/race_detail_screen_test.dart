import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _FakeBackendApiService extends BackendApiService {
  int respondCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async {
    return {
      'id': raceId,
      'name': 'Paid Race',
      'status': 'PENDING',
      'targetSteps': 100000,
      'maxDurationDays': 7,
      'buyInAmount': 100,
      'payoutPreset': 'WINNER_TAKES_ALL',
      'potCoins': 0,
      'heldPotCoins': 100,
      'projectedPotCoins': 100,
      'payouts': {'first': 100, 'second': 0, 'third': 0},
      'myStatus': 'INVITED',
      'isCreator': false,
      'participants': const [
        {
          'userId': 'creator-1',
          'displayName': 'RaceMaker',
          'status': 'ACCEPTED',
        },
        {
          'userId': 'user-1',
          'displayName': 'Trail Walker',
          'status': 'INVITED',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> respondToRaceInvite({
    required String identityToken,
    required String raceId,
    required bool accept,
  }) async {
    respondCalls += 1;
    return {
      'participant': {
        'id': 'rp-1',
        'status': accept ? 'ACCEPTED' : 'DECLINED',
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

  testWidgets('RaceDetailScreen confirms paid invite acceptance before joining', (
    WidgetTester tester,
  ) async {
    final authService = await _createAuthService();
    final backendApiService = _FakeBackendApiService();

    await tester.pumpWidget(
      MaterialApp(
        home: RaceDetailScreen(
          authService: authService,
          raceId: 'race-1',
          backendApiService: backendApiService,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('ACCEPT'), findsOneWidget);

    await tester.tap(find.text('ACCEPT'));
    await tester.pump();

    expect(find.text('100 GOLD BUY-IN'), findsOneWidget);
    expect(
      find.text('Your 100 gold will be held until the race starts.'),
      findsOneWidget,
    );
    expect(backendApiService.respondCalls, 0);

    await tester.tap(find.text('LOCK IT IN'));
    await tester.pumpAndSettle();

    expect(backendApiService.respondCalls, 1);
  });
}
