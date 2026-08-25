import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/inbox_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';

class _ReadAllInboxApi extends BackendApiService {
  _ReadAllInboxApi({this.readAllResult, this.readAllError});

  final InboxReadAllResult? readAllResult;
  final Object? readAllError;
  int readAllCalls = 0;
  int perAlertReadCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchInboxAlerts({
    required String identityToken,
    String? cursor,
    int limit = 25,
  }) async => {
    'alerts': [
      {
        'id': 'alert-1',
        'type': 'RACE_STARTED',
        'title': 'Race ready',
        'body': 'Your race is ready to open.',
        'readAt': null,
        'destination': {'route': 'home'},
      },
    ],
    'nextCursor': null,
    'unreadCount': 1,
    'totalUnreadCount': 2,
  };

  @override
  Future<Map<String, dynamic>> fetchFeedbackThreads({
    required String identityToken,
    String? cursor,
    int limit = 25,
  }) async => {
    'threads': [
      {
        'id': 'thread-1',
        'preview': 'We replied to your note.',
        'unread': true,
        'unreadByUser': true,
      },
    ],
    'nextCursor': null,
  };

  @override
  Future<Map<String, dynamic>> markInboxAlertRead({
    required String identityToken,
    required String alertId,
  }) async {
    perAlertReadCalls++;
    return const {'read': true, 'unreadCount': 0};
  }

  @override
  Future<InboxReadAllResult> markInboxReadAll({
    required String identityToken,
  }) async {
    readAllCalls++;
    final error = readAllError;
    if (error != null) throw error;
    return readAllResult!;
  }
}

Future<AuthService> _readAllAuth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

const _readAllSuccess = InboxReadAllResult(
  readAlertCount: 1,
  readThreadCount: 1,
  unreadCount: 0,
  totalUnreadCount: 0,
);

void main() {
  testWidgets(
    'standalone Inbox uses one read-all call and updates local rows/badge',
    (tester) async {
      final auth = await _readAllAuth();
      final api = _ReadAllInboxApi(readAllResult: _readAllSuccess);
      final badgeUpdates = <int>[];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemeData.light(),
          home: InboxScreen(
            authService: auth,
            backendApiService: api,
            clearOnOpen: true,
            onUnreadCountChanged: badgeUpdates.add,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(api.readAllCalls, 1);
      expect(api.perAlertReadCalls, 0);
      expect(badgeUpdates, [2, 0]);
      expect(find.text('Race ready'), findsOneWidget);
      expect(find.text('We replied to your note.'), findsOneWidget);
      expect(find.text('NEW'), findsNothing);
    },
  );

  testWidgets('read-all failure preserves the prior badge and unread rows', (
    tester,
  ) async {
    final auth = await _readAllAuth();
    final api = _ReadAllInboxApi(readAllError: const ApiException('offline'));
    final badgeUpdates = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeData.light(),
        home: InboxScreen(
          authService: auth,
          backendApiService: api,
          clearOnOpen: true,
          onUnreadCountChanged: badgeUpdates.add,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(api.readAllCalls, 1);
    expect(api.perAlertReadCalls, 0);
    expect(badgeUpdates, [2]);
    expect(find.byKey(const ValueKey('inbox-unread-alert-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-unread-thread-1')), findsOneWidget);
  });

  testWidgets('embedded Inbox does not clear on open', (tester) async {
    final auth = await _readAllAuth();
    final api = _ReadAllInboxApi(readAllResult: _readAllSuccess);
    final badgeUpdates = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeData.light(),
        home: InboxScreen(
          hostMode: InboxHostMode.embedded,
          authService: auth,
          backendApiService: api,
          clearOnOpen: false,
          onUnreadCountChanged: badgeUpdates.add,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(api.readAllCalls, 0);
    expect(find.byKey(const ValueKey('inbox-unread-alert-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-unread-thread-1')), findsOneWidget);
    expect(badgeUpdates, [2]);
  });
}
