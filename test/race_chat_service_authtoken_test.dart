import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/race_chat_service.dart';

/// Captures the identityToken argument the service passes to backend calls.
class _CapturingChatApi extends BackendApiService {
  String? lastSendToken;
  String? lastFetchToken;

  @override
  Future<Map<String, dynamic>> fetchRaceMessages({
    required String identityToken,
    required String raceId,
    String? cursor,
    int? limit,
  }) async {
    lastFetchToken = identityToken;
    return {'messages': const [], 'nextCursor': null};
  }

  @override
  Future<Map<String, dynamic>> sendRaceMessage({
    required String identityToken,
    required String raceId,
    required String body,
  }) async {
    lastSendToken = identityToken;
    return {
      'message': {
        'id': 'server-1',
        'kind': 'USER',
        'body': body,
        'senderId': 'user-1',
        'senderName': 'Tester',
        'createdAt': '2026-05-19T00:00:00.000Z',
      },
    };
  }
}

Future<AuthService> _authServiceWith({
  String? identityToken,
  String? sessionToken,
}) async {
  final values = <String, Object>{};
  if (identityToken != null) {
    values['auth_identity_token'] = identityToken;
    values['auth_user_identifier'] = 'apple-user-123';
  }
  if (sessionToken != null) {
    values['auth_session_token'] = sessionToken;
    values['auth_backend_user_id'] = 'user-1';
  }
  SharedPreferences.setMockInitialValues(values);
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'send() uses sessionToken (authToken) when both tokens are present',
    () async {
      final api = _CapturingChatApi();
      final auth = await _authServiceWith(
        identityToken: 'apple-identity-token',
        sessionToken: 'backend-session-token',
      );
      final service = RaceChatService(
        authService: auth,
        raceId: 'race-1',
        api: api,
      );

      await service.send('hello');

      expect(api.lastSendToken, equals('backend-session-token'));
      expect(api.lastSendToken, isNot(equals('apple-identity-token')));
    },
  );

  test(
    'loadInitial() uses sessionToken (authToken) when both tokens are present',
    () async {
      final api = _CapturingChatApi();
      final auth = await _authServiceWith(
        identityToken: 'apple-identity-token',
        sessionToken: 'backend-session-token',
      );
      final service = RaceChatService(
        authService: auth,
        raceId: 'race-1',
        api: api,
      );

      await service.loadInitial();

      expect(api.lastFetchToken, equals('backend-session-token'));
      expect(api.lastFetchToken, isNot(equals('apple-identity-token')));
    },
  );

  test(
    'send() falls back to identityToken when sessionToken is null',
    () async {
      final api = _CapturingChatApi();
      final auth = await _authServiceWith(
        identityToken: 'apple-identity-token',
        sessionToken: null,
      );
      final service = RaceChatService(
        authService: auth,
        raceId: 'race-1',
        api: api,
      );

      await service.send('hello');

      expect(api.lastSendToken, equals('apple-identity-token'));
    },
  );
}
