import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/loadable.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/screens/tabs/home_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/onboarding_state_service.dart';

/// The SETUP board: one container carrying the name, photo and first-friend
/// asks, and the friends row that only appears for a genuinely empty roster.
class _FakeBackendApiService extends BackendApiService {
  int dismissCalls = 0;

  Map<String, dynamic> get _user => const {
    'id': 'user-1',
    'displayName': 'SwiftCapybara07',
  };

  @override
  Future<Map<String, dynamic>> fetchDailyRewardStatus({
    required String identityToken,
    required String localDate,
  }) async {
    return const {'claimedToday': true};
  }

  @override
  Future<Map<String, dynamic>> recordRenameChipShown({
    required String identityToken,
  }) async => _user;

  @override
  Future<Map<String, dynamic>> dismissRenameChip({
    required String identityToken,
  }) async {
    dismissCalls += 1;
    return _user;
  }
}

Future<AuthService> _createAuthService(BackendApiService api) async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'SwiftCapybara07',
    'auth_profile_photo_url': 'https://example.test/photo.png',
    'auth_profile_photo_prompt_dismissed_at': '2026-07-01T00:00:00.000Z',
    'auth_onboarding_v3_enabled': true,
    'auth_rename_chip_shown_count': 0,
  });
  final authService = AuthService(backendApiService: api);
  await authService.restoreSession();
  return authService;
}

Widget _buildHome(
  AuthService authService,
  BackendApiService api, {
  required Loadable<List<Map<String, dynamic>>>? friendsState,
  List<Map<String, dynamic>> friends = const [],
  VoidCallback? onOpenFriendsTab,
}) {
  return MaterialApp(
    home: Scaffold(
      body: HomeTab(
        stepData: StepData(steps: 2400, date: DateTime(2026, 7, 27)),
        isLoading: false,
        error: null,
        healthAuthorized: true,
        notificationsState: true,
        displayName: 'SwiftCapybara07',
        authService: authService,
        backendApiService: api,
        onRefresh: () async {},
        onEnableHealth: () {},
        onEnableNotifications: () {},
        onDisplayNameChanged: () {},
        friendsSteps: friends,
        friendsStepsState: friendsState,
        onOpenFriendsTab: onOpenFriendsTab,
        raceCard: const {'state': 'EMPTY'},
      ),
    ),
  );
}

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
    OnboardingStateService.debugResetRenameChipSession();
  });

  testWidgets('a loaded, empty friends list offers the first-friend row', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var opened = 0;
    final api = _FakeBackendApiService();
    final authService = await _createAuthService(api);

    await tester.pumpWidget(
      _buildHome(
        authService,
        api,
        friendsState: const Loadable.success(<Map<String, dynamic>>[]),
        onOpenFriendsTab: () => opened += 1,
      ),
    );
    await _flush(tester);

    expect(find.text('Add your first friend'), findsOneWidget);

    await tester.tap(find.byKey(const Key('home-add-friend-cta')));
    await _flush(tester);
    expect(opened, 1, reason: 'the row hands off to the Friends tab');
  });

  testWidgets('a user with friends never sees the first-friend row', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final api = _FakeBackendApiService();
    final authService = await _createAuthService(api);

    await tester.pumpWidget(
      _buildHome(
        authService,
        api,
        friends: const [
          {'userId': 'friend-1', 'displayName': 'Sam', 'steps': 900},
        ],
        friendsState: const Loadable.success(<Map<String, dynamic>>[
          {'userId': 'friend-1', 'displayName': 'Sam', 'steps': 900},
        ]),
        onOpenFriendsTab: () {},
      ),
    );
    await _flush(tester);

    expect(find.text('Add your first friend'), findsNothing);
  });

  testWidgets('an in-flight friends fetch never accuses the user of having 0', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final api = _FakeBackendApiService();
    final authService = await _createAuthService(api);

    await tester.pumpWidget(
      _buildHome(
        authService,
        api,
        friendsState: const Loadable.loading(),
        onOpenFriendsTab: () {},
      ),
    );
    await _flush(tester);

    expect(find.text('Add your first friend'), findsNothing);

    // Same for an outright failure — an error is not evidence of no friends.
    await tester.pumpWidget(
      _buildHome(
        authService,
        api,
        friendsState: const Loadable.error('offline'),
        onOpenFriendsTab: () {},
      ),
    );
    await _flush(tester);

    expect(find.text('Add your first friend'), findsNothing);
  });

  testWidgets(
    'KEEP IT retires the name ask without opening the rename screen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final api = _FakeBackendApiService();
      final authService = await _createAuthService(api);

      await tester.pumpWidget(
        _buildHome(
          authService,
          api,
          friendsState: const Loadable.success(<Map<String, dynamic>>[]),
          onOpenFriendsTab: () {},
        ),
      );
      await _flush(tester);

      expect(find.byKey(const Key('home-keep-name')), findsOneWidget);

      await tester.tap(find.byKey(const Key('home-keep-name')));
      await _flush(tester);

      expect(api.dismissCalls, 1);
      expect(find.byKey(const Key('home-keep-name')), findsNothing);
      expect(
        find.text('Display Name'),
        findsNothing,
        reason: 'keeping the name must not push the rename screen',
      );
      // The board itself survives — the friends ask is still outstanding.
      expect(find.text('Add your first friend'), findsOneWidget);
    },
  );
}
