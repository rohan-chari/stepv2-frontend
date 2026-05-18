import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_chat_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _FakeRaceChatApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchRaceMessages({
    required String identityToken,
    required String raceId,
    String? cursor,
    int? limit,
  }) async {
    return {
      'messages': [
        {
          'id': 'msg-own',
          'kind': 'USER',
          'body': 'outgoing visible text',
          'senderId': 'user-1',
          'senderName': 'Sugaroro2',
          'createdAt': '2026-05-18T15:00:00',
        },
        {
          'id': 'msg-other',
          'kind': 'USER',
          'body': 'incoming dark text',
          'senderId': 'user-2',
          'senderName': 'Alex Summit',
          'createdAt': '2026-05-18T15:01:00',
        },
      ],
      'nextCursor': null,
    };
  }

  @override
  Future<Map<String, dynamic>> markRaceChatRead({
    required String identityToken,
    required String raceId,
  }) async {
    return const {'success': true};
  }
}

Future<AuthService> _authService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Sugaroro2',
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('outgoing race chat bubbles use light text on dark background', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RaceChatScreen(
          authService: await _authService(),
          raceId: 'race-1',
          raceName: 'Demo Powerup Sprint',
          raceStatus: 'ACTIVE',
          myStatus: 'ACCEPTED',
          myUserId: 'user-1',
          backendApiService: _FakeRaceChatApi(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final outgoing = tester.widget<Text>(find.text('outgoing visible text'));
    final incoming = tester.widget<Text>(find.text('incoming dark text'));

    expect(outgoing.style?.color, Colors.white);
    expect(incoming.style?.color, isNot(Colors.white));
  });
}
