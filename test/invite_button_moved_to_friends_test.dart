import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/referral_screen.dart';
import 'package:step_tracker/screens/tabs/friends_tab.dart';
import 'package:step_tracker/screens/tabs/profile_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// Item 1: the INVITE FRIENDS & EARN COINS button moved from Profile to Friends.
// It renders on the Friends tab (and tapping it opens the ReferralScreen), and
// is gone from Profile.

const _inviteLabel = 'INVITE FRIENDS & EARN COINS';

class _FriendsBackend extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchFriends({
    required String identityToken,
  }) async => const {
    'friends': [],
    'pending': {'incoming': [], 'outgoing': []},
  };

  @override
  Future<Map<String, dynamic>> fetchReferralStatus({
    required String identityToken,
  }) async => const {
    'code': 'BARA-TEST',
    'url': 'https://steptracker-api.org/r/BARA-TEST',
    'referredCount': 0,
    'completedCount': 0,
    'coinsEarned': 0,
    'friends': [],
  };
}

class _ProfileBackend extends BackendApiService {
  @override
  Future<List<Map<String, dynamic>>> fetchFriendsSteps({
    required String identityToken,
    required String date,
  }) async => const [];

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async =>
      const {
        'stepGoal': 8000,
        'incomingFriendRequests': 0,
        'displayName': 'Trail Walker',
        'email': 'walker@example.com',
        'isAdmin': false,
        'coins': 70,
        'heldCoins': 0,
      };

  @override
  Future<Map<String, dynamic>> fetchRaces({
    required String identityToken,
  }) async => const {'races': []};

  @override
  Future<Map<String, dynamic>> fetchStats({
    required String identityToken,
  }) async => const {
    'thisWeek': 12000,
    'thisMonth': 45000,
    'thisYear': 150000,
    'allTime': 300000,
    'streak': 4,
  };

  @override
  Future<Map<String, dynamic>> fetchStepCalendar({
    required String identityToken,
    required String month,
  }) async => const {'days': []};

  @override
  Future<Map<String, dynamic>> fetchDailyRewardStatus({
    required String identityToken,
    required String localDate,
  }) async => const {'claimedToday': true};
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_coins': 70,
    'auth_held_coins': 0,
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('FriendsTab renders the invite button and it opens ReferralScreen',
      (tester) async {
    final auth = await _auth();
    await tester.pumpWidget(
      MaterialApp(
        home: FriendsTab(
          authService: auth,
          onFriendsChanged: () {},
          backendApiService: _FriendsBackend(),
          displayName: 'Trail Walker',
        ),
      ),
    );
    await tester.pump();

    expect(find.text(_inviteLabel), findsOneWidget);

    await tester.tap(find.text(_inviteLabel));
    // PulseGlow animates forever, so pumpAndSettle would time out; pump a few
    // frames to let the navigation push complete instead.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ReferralScreen), findsOneWidget);
  });

  testWidgets('ProfileTab no longer renders the invite button', (tester) async {
    final auth = await _auth();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileTab(
            authService: auth,
            displayName: 'Trail Walker',
            email: 'walker@example.com',
            onSettingsChanged: () {},
            backendApiService: _ProfileBackend(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text(_inviteLabel), findsNothing);
    expect(find.text('INVITE FRIENDS'), findsNothing);
    // Neighboring sections remain.
    expect(find.text('STEP CALENDAR'), findsOneWidget);
    expect(find.text('STATS'), findsOneWidget);
  });
}
