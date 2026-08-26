import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/inbox_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';

class _ReadAllInboxApi extends BackendApiService {
  _ReadAllInboxApi({
    this.readAllResult,
    this.readAllError,
    this.withApproval = false,
  });

  final InboxReadAllResult? readAllResult;
  final Object? readAllError;
  final bool withApproval;
  int readAllCalls = 0;
  int fetchAlertCalls = 0;
  bool alertsWereRead = false;
  int perAlertReadCalls = 0;
  String? responseAction;

  @override
  Future<Map<String, dynamic>> fetchInboxAlerts({
    required String identityToken,
    String? cursor,
    int limit = 25,
  }) async {
    fetchAlertCalls++;
    return {
      'alerts': [
        {
          'id': 'alert-1',
          'type': 'RACE_STARTED',
          'title': 'Race ready',
          'body': 'Your race is ready to open.',
          'readAt': null,
          'destination': {'route': 'home'},
        },
        if (withApproval)
          {
            'id': 'approval-alert',
            'type': 'PRIVATE_RACE_JOIN_APPROVAL',
            'title': 'Join request',
            'body': 'Nathan invited Rohan to wyd STEP bro',
            'readAt': null,
            'destination': {
              'route': 'raceJoinRequest',
              'raceId': 'race-private',
              'requestId': 'request-private',
            },
          },
      ],
      'nextCursor': null,
      'unreadCount': alertsWereRead ? 0 : 1,
      'totalUnreadCount': alertsWereRead ? 1 : 2,
    };
  }

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
        'hasUnreadStaffReply': true,
        'lastStaffReplyAt': '2026-08-25T15:04:05.000Z',
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

  @override
  Future<void> markInboxAlertsRead({required String identityToken}) async {
    readAllCalls++;
    final error = readAllError;
    if (error != null) throw error;
    alertsWereRead = true;
  }

  @override
  Future<Map<String, dynamic>> respondToPrivateRaceJoinRequest({
    required String identityToken,
    required String raceId,
    required String requestId,
    required String action,
  }) async {
    responseAction = action;
    return {
      'joinRequest': {'id': requestId, 'status': '${action}ED'},
    };
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
      expect(api.fetchAlertCalls, greaterThanOrEqualTo(2));
      expect(api.perAlertReadCalls, 0);
      expect(badgeUpdates, [2, 1]);
      expect(find.text('Race ready'), findsOneWidget);
      expect(find.text('We replied to your note.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('inbox-unread-thread-1')),
        findsOneWidget,
      );
      expect(find.text('REPLIES FROM BARA'), findsOneWidget);
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

  testWidgets('creator join approval card keeps ACCEPT and DECLINE together', (
    tester,
  ) async {
    final auth = await _readAllAuth();
    final api = _ReadAllInboxApi(
      readAllResult: _readAllSuccess,
      withApproval: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeData.light(),
        home: InboxScreen(authService: auth, backendApiService: api),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('Nathan invited Rohan to wyd STEP bro'), findsOneWidget);
    expect(
      find.byKey(const Key('join-request-accept-request-private')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('join-request-decline-request-private')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('join-request-accept-request-private')),
    );
    await tester.pump();

    expect(api.responseAction, 'ACCEPT');
    expect(find.text('ACCEPTED'), findsOneWidget);
    expect(find.text('DECLINE'), findsNothing);
  });

  testWidgets(
    'read-all racing load-more marks only stale alerts, never staff replies',
    (tester) async {
      final auth = await _readAllAuth();
      final api = _StaleLoadMoreInboxApi();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemeData.light(),
          home: InboxScreen(
            authService: auth,
            backendApiService: api,
            clearOnOpen: true,
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('inbox-load-more')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('inbox-load-more')));
      await tester.pump();
      api.readAllCompleter.complete();
      await tester.pump();
      api.pageCompleter.complete();
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('inbox-unread-alert-2')), findsNothing);
      expect(
        find.byKey(const ValueKey('inbox-unread-thread-2')),
        findsOneWidget,
      );
    },
  );
}

class _StaleLoadMoreInboxApi extends BackendApiService {
  final Completer<void> readAllCompleter = Completer<void>();
  final Completer<void> pageCompleter = Completer<void>();
  bool alertsWereRead = false;

  @override
  Future<Map<String, dynamic>> fetchInboxAlerts({
    required String identityToken,
    String? cursor,
    int limit = 25,
  }) async {
    if (cursor != null) await pageCompleter.future;
    return {
      'alerts': [
        {
          'id': cursor == null ? 'alert-1' : 'alert-2',
          'type': 'RACE_STARTED',
          'title': cursor == null ? 'First race' : 'Second race',
          'body': 'Race alert',
          'readAt': null,
          'destination': {'route': 'home'},
        },
      ],
      'nextCursor': cursor == null && limit != 1 ? 'alerts-2' : null,
      'unreadCount': alertsWereRead ? 0 : 2,
      'totalUnreadCount': alertsWereRead ? 2 : 4,
    };
  }

  @override
  Future<Map<String, dynamic>> fetchFeedbackThreads({
    required String identityToken,
    String? cursor,
    int limit = 25,
  }) async {
    if (cursor != null) await pageCompleter.future;
    return {
      'threads': [
        {
          'id': cursor == null ? 'thread-1' : 'thread-2',
          'preview': cursor == null ? 'First reply' : 'Second reply',
          'unread': true,
          'unreadByUser': true,
          'hasUnreadStaffReply': true,
          'lastStaffReplyAt': '2026-08-25T15:04:05.000Z',
        },
      ],
      'nextCursor': cursor == null ? 'threads-2' : null,
    };
  }

  @override
  Future<void> markInboxAlertsRead({required String identityToken}) async {
    await readAllCompleter.future;
    alertsWereRead = true;
  }
}
