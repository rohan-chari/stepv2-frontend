import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/daily_reward_screen.dart';
import 'package:step_tracker/screens/admin_screen.dart';
import 'package:step_tracker/screens/inbox_screen.dart';
import 'package:step_tracker/screens/tabs/home_tab.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/services/ad_service.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/streak_chip.dart';

class _DailyApi extends BackendApiService {
  _DailyApi(this.status);

  final Map<String, dynamic> status;

  @override
  Future<Map<String, dynamic>> fetchDailyRewardStatus({
    required String identityToken,
    required String localDate,
  }) async => status;
}

class _UnavailableAd implements ExtraSpinAdController {
  int loads = 0;

  @override
  bool get isReady => false;

  @override
  bool get isSupported => true;

  @override
  void dispose() {}

  @override
  Future<void> load({required String userId, required String localDate}) async {
    loads++;
  }

  @override
  Future<bool> showAndAwaitReward() async => false;
}

class _InboxApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchInboxAlerts({
    required String identityToken,
    String? cursor,
    int limit = 25,
  }) async => {
    'alerts': [
      {
        'id': 'alert-1',
        'type': 'RACE_COMPLETED',
        'title': 'Race complete',
        'body': 'Open results',
        'readAt': null,
        'destination': {'route': 'home'},
      },
    ],
    'nextCursor': null,
  };

  @override
  Future<Map<String, dynamic>> fetchFeedbackThreads({
    required String identityToken,
    String? cursor,
    int limit = 25,
  }) async => {
    'threads': [
      {'id': 'thread-1', 'preview': 'Can you help?', 'unread': true},
    ],
    'nextCursor': null,
  };

  @override
  Future<Map<String, dynamic>> fetchFeedbackThread({
    required String identityToken,
    required String threadId,
    String? before,
    int limit = 25,
  }) async => {
    'thread': {'id': threadId},
    'messages': [
      {
        'id': 'm1',
        'senderKind': 'STAFF',
        'text': 'BARA SUPPORT is here.',
        'createdAt': '2026-08-17T00:00:00Z',
      },
    ],
    'nextBefore': null,
  };
}

class _AdminBannerApi extends _InboxApi {
  bool? enabled;
  String? message;

  @override
  Future<Map<String, dynamic>> fetchAdminSettings({
    required String identityToken,
  }) async => {
    'homeServiceBannerEnabled': false,
    'homeServiceBannerMessage': '',
  };

  @override
  Future<Map<String, dynamic>> updateAdminHomeServiceBanner({
    required String identityToken,
    required bool enabled,
    required String message,
    String? contestSlug,
  }) async {
    this.enabled = enabled;
    this.message = message;
    return {
      'homeServiceBannerEnabled': enabled,
      'homeServiceBannerMessage': message,
    };
  }
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'identity',
    'auth_session_token': 'session',
    'auth_backend_user_id': 'user-1',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

String _today() {
  final now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)}';
}

void main() {
  group('Inbox destination allowlist', () {
    test(
      'parses every backend-supported destination and rejects malformed routes',
      () {
        final home = InboxDestination.tryParse({'route': 'home'});
        final daily = InboxDestination.tryParse({'route': 'dailyReward'});
        final friends = InboxDestination.tryParse({'route': 'friends'});
        final race = InboxDestination.tryParse({
          'route': 'raceDetail',
          'raceId': 'race-1',
        });
        final tournament = InboxDestination.tryParse({
          'route': 'tournamentDetail',
          'tournamentId': 'tournament-1',
        });
        final support = InboxDestination.tryParse({
          'route': 'supportThread',
          'threadId': 'thread-1',
        });

        expect(home?.route, InboxDestinationRoute.home);
        expect(daily?.route, InboxDestinationRoute.dailyReward);
        expect(friends?.route, InboxDestinationRoute.friends);
        expect(race?.route, InboxDestinationRoute.raceDetail);
        expect(race?.raceId, 'race-1');
        expect(tournament?.route, InboxDestinationRoute.tournamentDetail);
        expect(tournament?.tournamentId, 'tournament-1');
        expect(support?.route, InboxDestinationRoute.supportThread);
        expect(support?.threadId, 'thread-1');
        expect(InboxDestination.tryParse({'route': 'supportThread'}), isNull);
        expect(InboxDestination.tryParse({'route': 'untrusted'}), isNull);
        expect(InboxDestination.tryParse({'route': 'raceDetail'}), isNull);
        expect(InboxDestination.tryParse(null), isNull);
      },
    );
  });

  testWidgets('Home always calls its reward entry DAILY REWARD', (
    tester,
  ) async {
    final auth = await _auth();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreakChip(
            authService: auth,
            backendApiService: _DailyApi(const {}),
            initialData: {'claimedToday': false, 'localDate': _today()},
          ),
        ),
      ),
    );

    expect(find.text('DAILY REWARD'), findsOneWidget);
    expect(find.text('CLAIM'), findsNothing);
  });

  testWidgets('an unavailable extra ad remains actionable as retry', (
    tester,
  ) async {
    final auth = await _auth();
    final ad = _UnavailableAd();
    await tester.pumpWidget(
      MaterialApp(
        home: DailyRewardScreen(
          authService: auth,
          backendApiService: _DailyApi({
            'claimedToday': true,
            'box': const <String, dynamic>{},
            'adExtraSpin': {
              'available': true,
              'pendingGrant': false,
              'used': false,
            },
          }),
          adController: ad,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('SPIN AGAIN'), findsOneWidget);
    expect(find.text('LOADING AD...'), findsNothing);
    await tester.tap(find.text('SPIN AGAIN'));
    await tester.pump();
    expect(ad.loads, greaterThanOrEqualTo(2));
  });

  testWidgets('Inbox has alerts and a replyable staff-only support thread', (
    tester,
  ) async {
    final auth = await _auth();
    await tester.pumpWidget(
      MaterialApp(
        home: InboxScreen(authService: auth, backendApiService: _InboxApi()),
      ),
    );
    await tester.pump();
    expect(find.text('Race complete'), findsOneWidget);
    expect(find.text('Can you help?'), findsOneWidget);
    await tester.tap(find.text('Can you help?'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('BARA SUPPORT is here.'), findsOneWidget);
    expect(find.text('Write a message'), findsOneWidget);
  });

  testWidgets('Home shows valid service banner data without Inbox chrome', (
    tester,
  ) async {
    final auth = await _auth();
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeTab(
            stepData: StepData(steps: 24, date: DateTime.now()),
            isLoading: false,
            error: null,
            healthAuthorized: true,
            notificationsState: true,
            displayName: 'Walker',
            authService: auth,
            backendApiService: _InboxApi(),
            onRefresh: () async {},
            onEnableHealth: () {},
            onEnableNotifications: () {},
            onDisplayNameChanged: () {},
            friendsSteps: const [],
            raceCard: const {
              'state': 'EMPTY',
              'inboxUnreadCount': 2,
              'homeServiceBanner': {
                'enabled': true,
                'message': 'Step syncs may be delayed.',
              },
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('home-service-banner')), findsOneWidget);
    expect(find.byKey(const Key('home-inbox-button')), findsNothing);
  });

  testWidgets('Admin validates and saves the atomic Home service banner pair', (
    tester,
  ) async {
    final auth = await _auth();
    final api = _AdminBannerApi();
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminFlagsPanel(
            authService: auth,
            backendApiService: api,
            showErrorToast: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(Switch).last);
    await tester.enterText(
      find.byKey(const Key('admin-home-service-banner-message')),
      'Step syncs may be delayed.',
    );
    await tester.tap(find.text('SAVE SERVICE BANNER'));
    await tester.pump();
    expect(api.enabled, isTrue);
    expect(api.message, 'Step syncs may be delayed.');
  });
}
