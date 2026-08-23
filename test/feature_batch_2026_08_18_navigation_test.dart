import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/home_race_suggestion.dart';
import 'package:step_tracker/models/loadable.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/screens/inbox_screen.dart';
import 'package:step_tracker/screens/leaderboard_screen.dart';
import 'package:step_tracker/screens/tabs/home_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/tutorial/tutorial_preview_data.dart';
import 'package:step_tracker/tutorial/tutorial_real_screens.dart';
import 'package:step_tracker/tutorial/tutorial_screen.dart';
import 'package:step_tracker/widgets/wooden_tab_bar.dart';

class _InboxApi extends BackendApiService {
  _InboxApi({
    this.unreadCount = 4,
    this.totalUnreadCount,
    this.markReadPayload = const {},
  });

  final Object? unreadCount;
  final Object? totalUnreadCount;
  final Map<String, dynamic> markReadPayload;

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
        'body': 'Go!',
        'readAt': null,
        'destination': {'route': 'home'},
      },
    ],
    'nextCursor': null,
    'unreadCount': unreadCount,
    if (totalUnreadCount != null) 'totalUnreadCount': totalUnreadCount,
  };

  @override
  Future<Map<String, dynamic>> markInboxAlertRead({
    required String identityToken,
    required String alertId,
  }) async => markReadPayload;

  @override
  Future<Map<String, dynamic>> fetchFeedbackThreads({
    required String identityToken,
    String? cursor,
    int limit = 25,
  }) async => const {'threads': <Map<String, dynamic>>[], 'nextCursor': null};
}

class _ControlledInboxApi extends BackendApiService {
  _ControlledInboxApi({required this.alerts});

  final List<Map<String, dynamic>> alerts;
  final Map<String, Completer<Map<String, dynamic>>> readCompleters = {};
  final List<String> readCalls = [];
  int alertFetches = 0;
  int? refreshedUnreadCount;
  bool failUnreadRefresh = false;
  bool includeSupportThread = false;

  @override
  Future<Map<String, dynamic>> fetchInboxAlerts({
    required String identityToken,
    String? cursor,
    int limit = 25,
  }) async {
    alertFetches++;
    if (alertFetches > 1 && failUnreadRefresh) {
      throw const ApiException('offline');
    }
    return {
      'alerts': alerts,
      'nextCursor': null,
      'unreadCount': alertFetches == 1 ? 5 : refreshedUnreadCount ?? 5,
    };
  }

  @override
  Future<Map<String, dynamic>> markInboxAlertRead({
    required String identityToken,
    required String alertId,
  }) {
    readCalls.add(alertId);
    return readCompleters
        .putIfAbsent(alertId, Completer<Map<String, dynamic>>.new)
        .future;
  }

  @override
  Future<Map<String, dynamic>> fetchFeedbackThreads({
    required String identityToken,
    String? cursor,
    int limit = 25,
  }) async => {
    'threads': includeSupportThread
        ? <Map<String, dynamic>>[
            {
              'id': 'thread-1',
              'preview': 'We replied to your note',
              'unreadByUser': true,
            },
          ]
        : <Map<String, dynamic>>[],
    'nextCursor': null,
  };

  @override
  Future<Map<String, dynamic>> fetchFeedbackThread({
    required String identityToken,
    required String threadId,
    String? before,
    int limit = 25,
  }) async => const {'messages': <Map<String, dynamic>>[], 'nextBefore': null};
}

class _MalformedLeaderboardApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchLeaderboard({
    required String identityToken,
    String type = 'steps',
    String period = 'today',
    String scope = 'global',
  }) async => {
    'top100': [
      {'rank': 'first', 'displayName': 12, 'totalSteps': 'many'},
      null,
    ],
    'currentUser': 'not-a-map',
  };
}

Future<AuthService> _auth() async {
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

Widget _home(
  AuthService auth,
  Loadable<List<HomeRaceSuggestion>> suggestions, {
  VoidCallback? onLeaderboard,
  bool tutorial = false,
}) => MaterialApp(
  theme: AppThemeData.light(),
  home: Scaffold(
    body: HomeTab(
      stepData: StepData(steps: 1200, date: DateTime(2026, 8, 18)),
      isLoading: false,
      error: null,
      healthAuthorized: true,
      notificationsState: true,
      displayName: 'Trail Walker',
      authService: auth,
      backendApiService: _InboxApi(),
      onRefresh: () async {},
      onEnableHealth: () {},
      onEnableNotifications: () {},
      onDisplayNameChanged: () {},
      friendsSteps: const [],
      raceCard: const {'state': 'EMPTY', 'inboxUnreadCount': 9},
      suggestedRacesState: suggestions,
      onOpenLeaderboardTab: onLeaderboard,
      isTutorialPreview: tutorial,
    ),
  ),
);

Future<void> _boundedPump(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.3.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets(
    'Home owns one Leaderboards ticket between suggestions and Feedback in every state',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final auth = await _auth();
      var taps = 0;
      final states = <Loadable<List<HomeRaceSuggestion>>>[
        const Loadable.loading(),
        const Loadable.success([]),
        const Loadable.error('offline'),
        Loadable.success(tutorialPreviewHomeSuggestions()),
      ];

      for (final state in states) {
        await tester.pumpWidget(
          _home(auth, state, onLeaderboard: () => taps++),
        );
        await _boundedPump(tester);

        final ticket = find.byKey(const Key('home-leaderboards-ticket'));
        expect(ticket, findsOneWidget);
        expect(find.text('LEADERBOARDS'), findsOneWidget);
        expect(find.text("See today's top walkers"), findsOneWidget);
        expect(find.byKey(const Key('home-inbox-button')), findsNothing);
        expect(
          tester.getTopLeft(ticket).dy,
          greaterThan(tester.getTopLeft(find.text('SUGGESTED RACES')).dy),
        );
        expect(
          tester.getTopLeft(ticket).dy,
          lessThan(tester.getTopLeft(find.text('FEEDBACK')).dy),
        );
      }

      await tester.tap(find.byKey(const Key('home-leaderboards-ticket')));
      expect(taps, 1);
    },
  );

  test('Inbox destination parser accepts only the shell allowlist', () {
    final cases = <Map<String, dynamic>, InboxDestinationRoute>{
      {'route': 'home'}: InboxDestinationRoute.home,
      {'route': 'races'}: InboxDestinationRoute.races,
      {'route': 'friends'}: InboxDestinationRoute.friends,
      {'route': 'inbox'}: InboxDestinationRoute.inbox,
      {'route': 'profile'}: InboxDestinationRoute.profile,
      {'route': 'dailyReward'}: InboxDestinationRoute.dailyReward,
      {'route': 'raceDetail', 'raceId': 'race-1'}:
          InboxDestinationRoute.raceDetail,
      {'route': 'tournamentDetail', 'tournamentId': 'tournament-1'}:
          InboxDestinationRoute.tournamentDetail,
      {'route': 'supportThread', 'threadId': 'thread-1'}:
          InboxDestinationRoute.supportThread,
    };
    for (final entry in cases.entries) {
      expect(InboxDestination.tryParse(entry.key)?.route, entry.value);
    }
    expect(InboxDestination.tryParse({'route': 'raceDetail'}), isNull);
    expect(
      InboxDestination.tryParse({
        'route': 'home',
        'futureMetadata': {'source': 'backend-v2'},
      })?.route,
      InboxDestinationRoute.home,
    );
    expect(
      InboxDestination.tryParse({
        'route': 'raceDetail',
        'raceId': 'race-1',
        'futureMetadata': true,
      })?.raceId,
      'race-1',
    );
    expect(
      InboxDestination.tryParse({'route': 'supportThread', 'threadId': ''}),
      isNull,
    );
    expect(InboxDestination.tryParse({'route': 'unknown'}), isNull);
    expect(InboxDestination.tryParse('home'), isNull);
  });

  testWidgets('embedded Inbox exposes selected semantics and unread updates', (
    tester,
  ) async {
    final auth = await _auth();
    final updates = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeData.light(),
        home: InboxScreen(
          hostMode: InboxHostMode.embedded,
          authService: auth,
          backendApiService: _InboxApi(
            unreadCount: 4,
            markReadPayload: const {'read': true, 'unreadCount': 3},
          ),
          onUnreadCountChanged: updates.add,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byTooltip('Back'), findsNothing);
    expect(find.byKey(const Key('inbox-segment-alerts')), findsNothing);
    expect(updates, [4]);

    await tester.tap(find.text('Race ready'));
    await tester.pump();
    expect(updates, [4, 3]);
  });

  testWidgets(
    'Inbox prefers combined totalUnreadCount and falls back to legacy unreadCount',
    (tester) async {
      final auth = await _auth();
      final updates = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: InboxScreen(
            authService: auth,
            backendApiService: _InboxApi(
              unreadCount: 2,
              totalUnreadCount: 7,
              markReadPayload: const {
                'read': true,
                'unreadCount': 1,
                'totalUnreadCount': 6,
              },
            ),
            onUnreadCountChanged: updates.add,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(updates, [7]);

      await tester.tap(find.text('Race ready'));
      await tester.pump();
      expect(updates, [7, 6]);

      await tester.pumpWidget(
        MaterialApp(
          home: InboxScreen(
            key: const ValueKey('malformed-total'),
            authService: auth,
            backendApiService: _InboxApi(
              unreadCount: 4,
              totalUnreadCount: 'bad',
            ),
            onUnreadCountChanged: updates.add,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(updates.last, 4);
    },
  );

  testWidgets(
    'a valid single authoritative read count can increase with new unread',
    (tester) async {
      final auth = await _auth();
      final updates = <int>[];
      var decrements = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: InboxScreen(
            authService: auth,
            backendApiService: _InboxApi(
              unreadCount: 5,
              markReadPayload: const {'read': true, 'unreadCount': 7},
            ),
            onUnreadCountChanged: updates.add,
            onUnreadCountDecremented: () => decrements++,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.text('Race ready'));
      await tester.pump();

      expect(updates, [5, 7]);
      expect(decrements, 0);
    },
  );

  testWidgets(
    'present malformed authoritative counts retain prior without legacy decrement',
    (tester) async {
      final auth = await _auth();
      for (final entry in <Object?>[null, -1, 1.5, 'seven'].indexed) {
        final updates = <int>[];
        var decrements = 0;
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(entry.$1),
            home: InboxScreen(
              authService: auth,
              backendApiService: _InboxApi(
                unreadCount: 5,
                markReadPayload: {'read': true, 'unreadCount': entry.$2},
              ),
              onUnreadCountChanged: updates.add,
              onUnreadCountDecremented: () => decrements++,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        await tester.tap(find.text('Race ready'));
        await tester.pump();

        expect(updates, [5], reason: 'value: ${entry.$2}');
        expect(decrements, 0, reason: 'value: ${entry.$2}');
      }
    },
  );

  testWidgets(
    'malformed unread data is ignored and an old read response decrements once',
    (tester) async {
      final auth = await _auth();
      final updates = <int>[];
      var decrements = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemeData.night(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: InboxScreen(
              hostMode: InboxHostMode.embedded,
              authService: auth,
              backendApiService: _InboxApi(
                unreadCount: 'four',
                markReadPayload: const {'read': true},
              ),
              onUnreadCountChanged: updates.add,
              onUnreadCountDecremented: () => decrements++,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(updates, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Race ready'));
      await tester.pump();
      expect(decrements, 1);
      await tester.tap(find.text('Race ready'));
      await tester.pump();
      expect(decrements, 1);
    },
  );

  testWidgets(
    'two rapid taps issue one legacy read and decrement the unread total once',
    (tester) async {
      final auth = await _auth();
      final api = _ControlledInboxApi(
        alerts: [
          {
            'id': 'alert-1',
            'type': 'RACE_STARTED',
            'title': 'One alert',
            'body': 'Open it',
            'readAt': null,
            'destination': {'route': 'home'},
          },
        ],
      );
      var decrements = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: InboxScreen(
            authService: auth,
            backendApiService: api,
            onUnreadCountDecremented: () => decrements++,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      await tester.tap(find.text('One alert'));
      await tester.pump();
      await tester.tap(find.text('One alert'));
      await tester.pump();
      expect(api.readCalls, ['alert-1']);

      api.readCompleters['alert-1']!.complete(const {'read': true});
      await tester.pump();
      expect(decrements, 1);
    },
  );

  testWidgets(
    'reversed distinct legacy reads each decrement the unread total once',
    (tester) async {
      final auth = await _auth();
      final api = _ControlledInboxApi(
        alerts: [
          for (final id in ['alert-1', 'alert-2'])
            {
              'id': id,
              'type': 'RACE_STARTED',
              'title': id == 'alert-1' ? 'First alert' : 'Second alert',
              'body': 'Open it',
              'readAt': null,
              'destination': {'route': 'home'},
            },
        ],
      );
      final updates = <int>[];
      var decrements = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: InboxScreen(
            authService: auth,
            backendApiService: api,
            onUnreadCountChanged: updates.add,
            onUnreadCountDecremented: () => decrements++,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      await tester.tap(find.text('First alert'));
      await tester.pump();
      await tester.tap(find.text('Second alert'));
      await tester.pump();
      api.readCompleters['alert-2']!.complete(const {'read': true});
      await tester.pump();
      api.readCompleters['alert-1']!.complete(const {'read': true});
      await tester.pump();

      expect(updates, [5]);
      expect(decrements, 2);
      expect(api.alertFetches, 1);
    },
  );

  testWidgets(
    'reversed authoritative reads reconcile once after all mutations settle',
    (tester) async {
      final auth = await _auth();
      final api = _ControlledInboxApi(
        alerts: [
          for (final id in ['alert-1', 'alert-2'])
            {
              'id': id,
              'type': 'RACE_STARTED',
              'title': id == 'alert-1' ? 'First alert' : 'Second alert',
              'body': 'Open it',
              'readAt': null,
              'destination': {'route': 'home'},
            },
        ],
      )..refreshedUnreadCount = 2;
      final updates = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: InboxScreen(
            authService: auth,
            backendApiService: api,
            onUnreadCountChanged: updates.add,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      await tester.tap(find.text('First alert'));
      await tester.pump();
      await tester.tap(find.text('Second alert'));
      await tester.pump();
      api.readCompleters['alert-2']!.complete(const {
        'read': true,
        'unreadCount': 4,
      });
      await tester.pump();
      api.readCompleters['alert-1']!.complete(const {
        'read': true,
        'unreadCount': 3,
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(updates, [5, 2]);
      expect(api.alertFetches, 2);
    },
  );

  testWidgets(
    'failed concurrent authoritative reconciliation retains the prior total',
    (tester) async {
      final auth = await _auth();
      final api = _ControlledInboxApi(
        alerts: [
          for (final id in ['alert-1', 'alert-2'])
            {
              'id': id,
              'type': 'RACE_STARTED',
              'title': id == 'alert-1' ? 'First alert' : 'Second alert',
              'body': 'Open it',
              'readAt': null,
              'destination': {'route': 'home'},
            },
        ],
      )..failUnreadRefresh = true;
      final updates = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: InboxScreen(
            authService: auth,
            backendApiService: api,
            onUnreadCountChanged: updates.add,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      await tester.tap(find.text('First alert'));
      await tester.pump();
      await tester.tap(find.text('Second alert'));
      await tester.pump();
      api.readCompleters['alert-2']!.complete(const {
        'read': true,
        'unreadCount': 4,
      });
      await tester.pump();
      api.readCompleters['alert-1']!.complete(const {
        'read': true,
        'unreadCount': 3,
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(updates, [5]);
      expect(api.alertFetches, 2);
    },
  );

  testWidgets(
    'successfully opening a support thread refreshes the combined unread total',
    (tester) async {
      final auth = await _auth();
      final api = _ControlledInboxApi(alerts: const [])
        ..includeSupportThread = true
        ..refreshedUnreadCount = 2;
      final updates = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: InboxScreen(
            hostMode: InboxHostMode.embedded,
            authService: auth,
            backendApiService: api,
            onUnreadCountChanged: updates.add,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.text('We replied to your note'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(find.byType(SupportThreadScreen), findsOneWidget);
      expect(updates, [5, 2]);
      expect(api.alertFetches, 2);
    },
  );

  testWidgets(
    'standalone Leaderboard has back chrome and tolerates malformed rows',
    (tester) async {
      final auth = await _auth();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemeData.light(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => StandaloneLeaderboardScreen(
                    authService: auth,
                    backendApiService: _MalformedLeaderboardApi(),
                  ),
                ),
              ),
              child: const Text('OPEN'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('OPEN'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(
        find.byKey(const Key('standalone-leaderboard-back')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('leaderboard-host-bottom-inset-0')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('standalone-leaderboard-back')));
      await tester.pumpAndSettle();
      expect(find.text('OPEN'), findsOneWidget);
    },
  );

  testWidgets(
    'tutorial copied navigation uses Inbox and ticket cannot escape',
    (tester) async {
      final auth = TutorialPreviewAuthService();
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemeData.light(),
          home: TutorialRealHost(
            page: TutorialMockPage.home,
            keys: const {},
            authService: auth,
            api: TutorialPreviewBackendApiService(),
          ),
        ),
      );
      await _boundedPump(tester);

      final bar = tester.widget<WoodenTabBar>(find.byType(WoodenTabBar));
      expect(bar.items.map((item) => item.label), [
        'Home',
        'Races',
        'Rank',
        'Friends',
        'Inbox',
      ]);
      expect(find.byKey(const Key('home-leaderboards-ticket')), findsOneWidget);
      tester
          .widget<InkWell>(find.byKey(const Key('home-leaderboards-ticket')))
          .onTap!();
      await tester.pump();
      expect(find.byType(StandaloneLeaderboardScreen), findsNothing);
    },
  );

  testWidgets('tutorial Friends preview selects the Friends tab', (tester) async {
    final auth = TutorialPreviewAuthService();
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeData.light(),
        home: TutorialRealHost(
          page: TutorialMockPage.friends,
          keys: const {},
          authService: auth,
          api: TutorialPreviewBackendApiService(),
        ),
      ),
    );
    await _boundedPump(tester);
    final bar = tester.widget<WoodenTabBar>(find.byType(WoodenTabBar));
    expect(bar.currentIndex, 3);
  });

  testWidgets('Inbox suppresses routine and malformed alert rows', (tester) async {
    final auth = await _auth();
    final api = _ControlledInboxApi(
      alerts: [
        const {
          'id': 'routine',
          'type': 'STEP_MILESTONE_REMINDER',
          'title': 'Routine',
          'body': 'Skip me',
          'destination': {'route': 'home'},
        },
        const {
          'id': 'bad-destination',
          'type': 'RACE_STARTED',
          'title': 'Bad route',
          'body': 'Skip me',
          'destination': {'route': 'not-allowed'},
        },
        const {
          'id': 'important',
          'type': 'RACE_STARTED',
          'title': 'Race ready',
          'body': 'Open me',
          'destination': {'route': 'home'},
        },
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeData.light(),
        home: InboxScreen(authService: auth, backendApiService: api),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('Race ready'), findsOneWidget);
    expect(find.text('Routine'), findsNothing);
    expect(find.text('Bad route'), findsNothing);
  });
}
