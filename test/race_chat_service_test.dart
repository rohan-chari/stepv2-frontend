import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/race_chat_service.dart';

class _FakeRaceChatApi extends BackendApiService {
  Completer<Map<String, dynamic>>? fetchCompleter;
  Completer<Map<String, dynamic>>? sendCompleter;
  List<Map<String, dynamic>> nextFetchMessages = const [];

  @override
  Future<Map<String, dynamic>> fetchRaceMessages({
    required String identityToken,
    required String raceId,
    String? cursor,
    int? limit,
    String? kind,
  }) {
    final completer = fetchCompleter;
    if (completer != null) return completer.future;
    return Future.value({'messages': nextFetchMessages, 'nextCursor': null});
  }

  @override
  Future<Map<String, dynamic>> sendRaceMessage({
    required String identityToken,
    required String raceId,
    required String body,
  }) {
    final completer = sendCompleter;
    if (completer != null) return completer.future;
    return Future.value({'message': _message('server-1', body)});
  }
}

Map<String, dynamic> _message(String id, String body) {
  return {
    'id': id,
    'kind': 'USER',
    'body': body,
    'senderId': 'user-1',
    'senderName': 'Trail Walker',
    'createdAt': '2026-05-18T20:00:00.000Z',
  };
}

Future<AuthService> _authService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'send de-dupes server message inserted by refresh while pending',
    () async {
      final api = _FakeRaceChatApi();
      final service = RaceChatService(
        authService: await _authService(),
        raceId: 'race-1',
        api: api,
      );
      api.sendCompleter = Completer<Map<String, dynamic>>();

      final sendFuture = service.send('hello');
      await Future<void>.delayed(Duration.zero);

      expect(service.messages.single.pending, isTrue);

      api.nextFetchMessages = [_message('server-1', 'hello')];
      await service.refreshTop();
      expect(service.messages.map((m) => m.id), contains('server-1'));

      api.sendCompleter!.complete({'message': _message('server-1', 'hello')});
      await sendFuture;

      expect(service.messages.where((m) => m.id == 'server-1'), hasLength(1));
      expect(service.messages, hasLength(1));
    },
  );

  test(
    'loadInitial can complete after dispose without notifying listeners',
    () async {
      final api = _FakeRaceChatApi()
        ..fetchCompleter = Completer<Map<String, dynamic>>();
      final service = RaceChatService(
        authService: await _authService(),
        raceId: 'race-1',
        api: api,
      );

      final loadFuture = service.loadInitial();
      service.dispose();
      api.fetchCompleter!.complete({
        'messages': [_message('server-1', 'hello')],
        'nextCursor': null,
      });

      await expectLater(loadFuture, completes);
    },
  );
}
