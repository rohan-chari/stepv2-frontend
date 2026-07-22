import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

/// B7 — the race chat keyboard must dismiss on drag and on tap-outside, and the
/// send button must still work.
///
/// There is no separate tournament chat: matchups push the regular
/// [RaceDetailScreen]. This pumps that screen, opens the CHAT tab, focuses the
/// composer, and verifies:
///  - dragging the message list drops the composer focus (onDrag dismissal),
///  - tapping outside the field drops focus (onTapOutside unfocus),
///  - tapping SEND with text still sends.
class _ChatBackendApiService extends BackendApiService {
  _ChatBackendApiService();

  int sendCalls = 0;
  String? lastSentBody;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async {
    return {
      'id': raceId,
      'name': 'Powerup Race',
      'status': 'ACTIVE',
      'targetSteps': 100000,
      'maxDurationDays': 7,
      'buyInAmount': 0,
      'payoutPreset': 'WINNER_TAKES_ALL',
      'potCoins': 0,
      'heldPotCoins': 0,
      'projectedPotCoins': 0,
      'payouts': {'first': 0, 'second': 0, 'third': 0},
      'myStatus': 'ACCEPTED',
      'isCreator': false,
      'powerupsEnabled': true,
      'endsAt': '2026-12-10T12:00:00.000Z',
      'participants': const [
        {'userId': 'user-1', 'displayName': 'Trail Walker', 'status': 'ACCEPTED'},
        {'userId': 'user-2', 'displayName': 'Hill Climber', 'status': 'ACCEPTED'},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async {
    return {
      'status': 'ACTIVE',
      'participants': const [
        {
          'userId': 'user-1',
          'displayName': 'Trail Walker',
          'totalSteps': 42000,
          'finishedAt': null,
        },
        {
          'userId': 'user-2',
          'displayName': 'Hill Climber',
          'totalSteps': 38000,
          'finishedAt': null,
        },
      ],
      'powerupData': {
        'enabled': true,
        'inventory': const [],
        'powerupSlots': 3,
        'queuedBoxCount': 0,
        'activeEffects': const [],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaceFeed({
    String? cursor,
    required String identityToken,
    required String raceId,
  }) async {
    return const {'events': []};
  }

  @override
  Future<Map<String, dynamic>> fetchRaceMessages({
    required String identityToken,
    required String raceId,
    String? cursor,
    int? limit,
    String? kind,
  }) async {
    if (kind == 'USER') {
      return {
        'messages': [
          for (var i = 0; i < 12; i++)
            {
              'id': 'm$i',
              'kind': 'USER',
              'body': 'Message number $i',
              'senderId': 'user-2',
              'senderName': 'Hill Climber',
              'createdAt': '2026-12-01T12:00:0${i % 10}.000Z',
            },
        ],
        'nextCursor': null,
      };
    }
    return const {'messages': [], 'nextCursor': null};
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    return const {'coins': 500, 'heldCoins': 0};
  }

  @override
  Future<Map<String, dynamic>> sendRaceMessage({
    required String identityToken,
    required String raceId,
    required String body,
  }) async {
    sendCalls += 1;
    lastSentBody = body;
    return {
      'message': {
        'id': 'server-1',
        'kind': 'USER',
        'body': body,
        'senderId': 'user-1',
        'senderName': 'Trail Walker',
        'createdAt': '2026-12-01T13:00:00.000Z',
      },
    };
  }
}

Future<AuthService> _createAuthService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_coins': 500,
    'auth_held_coins': 0,
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
}

bool _composerHasFocus(WidgetTester tester) {
  final editable = tester.widget<EditableText>(find.byType(EditableText).first);
  return editable.focusNode.hasFocus;
}

Future<void> _openChatTab(WidgetTester tester) async {
  // The activity/chat section lives far down the page's SingleChildScrollView,
  // so scroll it into view before tapping.
  await tester.ensureVisible(find.text('CHAT'));
  await _pumpFrames(tester);
  await tester.tap(find.text('CHAT'));
  await _pumpFrames(tester);
  // Bring the composer (and the message list above it) on-screen.
  await tester.ensureVisible(find.byType(TextField));
  await _pumpFrames(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('dragging the message list dismisses the keyboard',
      (WidgetTester tester) async {
    final authService = await _createAuthService();
    final api = _ChatBackendApiService();

    await tester.pumpWidget(
      MaterialApp(
        home: RaceDetailScreen(
          authService: authService,
          raceId: 'race-chat',
          backendApiService: api,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await _pumpFrames(tester);

    await _openChatTab(tester);

    // Focus the composer.
    await tester.tap(find.byType(TextField));
    await _pumpFrames(tester);
    expect(_composerHasFocus(tester), isTrue);

    // Drag the message list -> onDrag dismissal unfocuses the composer.
    await tester.drag(find.byType(ListView), const Offset(0, 120));
    await _pumpFrames(tester);
    expect(_composerHasFocus(tester), isFalse);

    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('tapping outside the field dismisses the keyboard',
      (WidgetTester tester) async {
    final authService = await _createAuthService();
    final api = _ChatBackendApiService();

    await tester.pumpWidget(
      MaterialApp(
        home: RaceDetailScreen(
          authService: authService,
          raceId: 'race-chat',
          backendApiService: api,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await _pumpFrames(tester);

    await _openChatTab(tester);

    await tester.tap(find.byType(TextField));
    await _pumpFrames(tester);
    expect(_composerHasFocus(tester), isTrue);

    // Tap a message in the list (outside the composer field) -> unfocus.
    await tester.tap(find.text('Message number 0'));
    await _pumpFrames(tester);
    expect(_composerHasFocus(tester), isFalse);

    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('the send button still sends after the dismissal wiring',
      (WidgetTester tester) async {
    final authService = await _createAuthService();
    final api = _ChatBackendApiService();

    await tester.pumpWidget(
      MaterialApp(
        home: RaceDetailScreen(
          authService: authService,
          raceId: 'race-chat',
          backendApiService: api,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await _pumpFrames(tester);

    await _openChatTab(tester);

    await tester.enterText(find.byType(TextField), 'hello world');
    await _pumpFrames(tester);

    await tester.ensureVisible(find.byIcon(Icons.send));
    await _pumpFrames(tester);
    await tester.tap(find.byIcon(Icons.send));
    await _pumpFrames(tester);

    expect(api.sendCalls, 1);
    expect(api.lastSentBody, 'hello world');

    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 300));
  });
}
