import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/screens/tabs/home_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/onboarding_state_service.dart';
import 'package:step_tracker/widgets/arcade_fx.dart';

/// Counts the two additive rename-chip POSTs so the tests can assert
/// "fires exactly once per app session" and "a failing POST never un-dismisses".
class _FakeBackendApiService extends BackendApiService {
  _FakeBackendApiService({this.throwOnDismiss = false});

  final bool throwOnDismiss;
  int shownCalls = 0;
  int dismissCalls = 0;
  int serverShownCount = 0;
  String? serverDismissedAt;

  Map<String, dynamic> get _user => {
    'id': 'user-1',
    'displayName': 'SwiftCapybara07',
    'renameChipShownCount': serverShownCount,
    'renameChipDismissedAt': serverDismissedAt,
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
  }) async {
    shownCalls += 1;
    serverShownCount += 1;
    return _user;
  }

  @override
  Future<Map<String, dynamic>> dismissRenameChip({
    required String identityToken,
  }) async {
    dismissCalls += 1;
    if (throwOnDismiss) {
      throw const ApiException('Not found', statusCode: 404);
    }
    serverDismissedAt ??= '2026-07-27T18:03:11.442Z';
    return _user;
  }
}

/// Builds a signed-in AuthService. [serverRenameChipState] mirrors what the
/// backend last sent: null means the backend never sent either key (an older
/// backend), which must select the legacy device-local path.
Future<AuthService> _createAuthService({
  BackendApiService? backendApiService,
  Map<String, Object>? serverRenameChipState,
  Map<String, Object>? localPrefs,
}) async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'SwiftCapybara07',
    'auth_profile_photo_url': 'https://example.test/photo.png',
    'auth_profile_photo_prompt_dismissed_at': '2026-07-01T00:00:00.000Z',
    'auth_onboarding_v3_enabled': true,
    ...?serverRenameChipState,
    ...?localPrefs,
  });

  final authService = AuthService(backendApiService: backendApiService);
  await authService.restoreSession();
  return authService;
}

Widget _buildHome(
  AuthService authService,
  BackendApiService api, {
  Map<String, dynamic>? raceCard,
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
        friendsSteps: const [],
        raceCard: raceCard ?? const {'state': 'EMPTY'},
      ),
    ),
  );
}

/// Flushes the async prefs/network reads inside `_resolveRenameChip` plus the
/// StaggerIn intro animations, without `pumpAndSettle` (home hosts repeating
/// tickers that never settle).
Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Finder _staggerAt(int index) => find.byWidgetPredicate(
  (widget) => widget is StaggerIn && widget.index == index,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // PackageInfo.fromPlatform() never resolves inside testWidgets' fake-async
    // zone; without this the activation-event writes hang silently.
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
    OnboardingStateService.debugResetRenameChipSession();
  });

  group('§6.1 placement', () {
    // 1. SETUP renders above the race section.
    testWidgets('SETUP sits above the RACES section', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final api = _FakeBackendApiService();
      final authService = await _createAuthService(
        backendApiService: api,
        serverRenameChipState: {'auth_rename_chip_shown_count': 0},
      );

      await tester.pumpWidget(_buildHome(authService, api));
      await _flush(tester);

      expect(find.text('SETUP'), findsOneWidget);
      expect(find.text('RACES'), findsWidgets);
      expect(find.byKey(const Key('home-rename-chip')), findsOneWidget);

      final setupDy = tester.getTopLeft(find.text('SETUP')).dy;
      // "RACES" appears both as the section header and inside the empty-state
      // card, so assert against every one of them.
      for (final race in find.text('RACES').evaluate()) {
        expect(
          setupDy,
          lessThan(tester.getTopLeft(find.byWidget(race.widget)).dy),
          reason: 'setup work is a prerequisite for the races below it',
        );
      }
    });

    // 1b. The stagger indices still run top-to-bottom.
    testWidgets('the SETUP stagger index precedes the race stagger index', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final api = _FakeBackendApiService();
      final authService = await _createAuthService(
        backendApiService: api,
        serverRenameChipState: {'auth_rename_chip_shown_count': 0},
      );

      await tester.pumpWidget(_buildHome(authService, api));
      await _flush(tester);

      // Today's Coins moved from index 3 to 4 when batch 2026-08-10b item 3
      // inserted the pending-invite block at 3.
      expect(
        tester.getTopLeft(_staggerAt(2)).dy,
        lessThan(tester.getTopLeft(_staggerAt(4)).dy),
      );
    });

    // 2. A fully set-up user gets no header and no gap.
    testWidgets('a fully set-up user sees no SETUP header and no gap', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final api = _FakeBackendApiService();
      final authService = await _createAuthService(
        backendApiService: api,
        serverRenameChipState: {
          'auth_rename_chip_dismissed_at': '2026-07-20T10:00:00.000Z',
        },
      );

      await tester.pumpWidget(_buildHome(authService, api));
      await _flush(tester);

      expect(find.text('SETUP'), findsNothing);
      expect(find.byKey(const Key('home-rename-chip')), findsNothing);
      expect(
        tester.getSize(_staggerAt(2)).height,
        0.0,
        reason: 'an empty SETUP section must not add padding above the races',
      );
    });
  });

  group('§6.3 rename chip — server state', () {
    // 3. Server dismissal wins over empty local prefs. (Regression: the chip
    // came back after every sign-out because the local ledger was wiped.)
    testWidgets('a server dismissal hides the chip even with empty local prefs', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final api = _FakeBackendApiService();
      final authService = await _createAuthService(
        backendApiService: api,
        serverRenameChipState: {
          'auth_rename_chip_shown_count': 1,
          'auth_rename_chip_dismissed_at': '2026-07-20T10:00:00.000Z',
        },
      );

      await tester.pumpWidget(_buildHome(authService, api));
      await _flush(tester);

      expect(find.byKey(const Key('home-rename-chip')), findsNothing);
      expect(api.shownCalls, 0);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.get(OnboardingStateService.keyRenameChipShownCount), isNull);
    });

    // 4. Server count wins.
    testWidgets('a server count at the cap hides the chip', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final api = _FakeBackendApiService();
      final authService = await _createAuthService(
        backendApiService: api,
        serverRenameChipState: {
          'auth_rename_chip_shown_count':
              OnboardingStateService.maxRenameChipShows,
        },
      );

      await tester.pumpWidget(_buildHome(authService, api));
      await _flush(tester);

      expect(find.byKey(const Key('home-rename-chip')), findsNothing);
      expect(api.shownCalls, 0);
    });

    // 5. Old backend: neither key ever arrived -> legacy local ledger.
    testWidgets('an older backend falls back to the local prefs ledger', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final api = _FakeBackendApiService();
      final authService = await _createAuthService(backendApiService: api);
      expect(authService.hasServerRenameChipState, isFalse);

      await tester.pumpWidget(_buildHome(authService, api));
      await _flush(tester);

      expect(find.byKey(const Key('home-rename-chip')), findsOneWidget);
      expect(api.shownCalls, 0, reason: 'never POST to a backend without it');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(OnboardingStateService.keyRenameChipShownCount), 1);
    });

    // 5b. The legacy ledger still retires the chip.
    testWidgets('an older backend honours a local dismissal', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final api = _FakeBackendApiService();
      final authService = await _createAuthService(
        backendApiService: api,
        localPrefs: {OnboardingStateService.keyRenameChipDismissed: true},
      );

      await tester.pumpWidget(_buildHome(authService, api));
      await _flush(tester);

      expect(find.byKey(const Key('home-rename-chip')), findsNothing);
    });

    // 5c. The PageView double-count is a defect in its own right (§2.2), so the
    // once-per-session guard must hold on the legacy path too — an older
    // backend keeps the bug otherwise.
    testWidgets('the local ledger counts once per session across a re-pump', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final api = _FakeBackendApiService();
      final authService = await _createAuthService(backendApiService: api);
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(_buildHome(authService, api));
      await _flush(tester);
      expect(find.byKey(const Key('home-rename-chip')), findsOneWidget);
      expect(prefs.getInt(OnboardingStateService.keyRenameChipShownCount), 1);

      // Swiping to another tab disposes home (the PageView has no keep-alive).
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await _flush(tester);

      await tester.pumpWidget(_buildHome(authService, api));
      await _flush(tester);

      expect(find.byKey(const Key('home-rename-chip')), findsOneWidget);
      expect(
        prefs.getInt(OnboardingStateService.keyRenameChipShownCount),
        1,
        reason: 'a tab swipe must not burn a chip impression',
      );
      expect(api.shownCalls, 0);
    });

    // 6. Once per app session, across the PageView's dispose/rebuild.
    testWidgets('the shown POST fires once per session across a re-pump', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final api = _FakeBackendApiService();
      final authService = await _createAuthService(
        backendApiService: api,
        serverRenameChipState: {'auth_rename_chip_shown_count': 0},
      );

      await tester.pumpWidget(_buildHome(authService, api));
      await _flush(tester);
      expect(find.byKey(const Key('home-rename-chip')), findsOneWidget);
      expect(api.shownCalls, 1);

      // Swiping to another tab disposes home (the PageView has no keep-alive).
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await _flush(tester);

      await tester.pumpWidget(_buildHome(authService, api));
      await _flush(tester);

      expect(find.byKey(const Key('home-rename-chip')), findsOneWidget);
      expect(
        api.shownCalls,
        1,
        reason: 'a tab swipe must not burn a chip impression',
      );
    });

    // 7. Dismissal is optimistic and never reverts on a failed POST.
    testWidgets('tapping the chip retires it even when the POST fails', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final api = _FakeBackendApiService(throwOnDismiss: true);
      final authService = await _createAuthService(
        backendApiService: api,
        serverRenameChipState: {'auth_rename_chip_shown_count': 0},
      );

      await tester.pumpWidget(_buildHome(authService, api));
      await _flush(tester);
      expect(find.byKey(const Key('home-rename-chip')), findsOneWidget);

      await tester.tap(find.byKey(const Key('home-rename-chip')));
      await _flush(tester);

      expect(api.dismissCalls, 1);
      expect(find.byKey(const Key('home-rename-chip')), findsNothing);
      expect(authService.renameChipDismissedAt, isNotNull);

      // Back on home (route popped / tab re-entered): still gone.
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await _flush(tester);
      await tester.pumpWidget(_buildHome(authService, api));
      await _flush(tester);

      expect(find.byKey(const Key('home-rename-chip')), findsNothing);
    });
  });

  group('§6.2 AuthService persistence', () {
    test('applyBackendUser reads both additive fields and signOut clears them', () async {
      SharedPreferences.setMockInitialValues({
        'auth_identity_token': 'apple-token',
        'auth_user_identifier': 'apple-user-123',
        'auth_session_token': 'session-token',
      });
      final auth = AuthService(backendApiService: _FakeBackendApiService());
      await auth.restoreSession();
      expect(auth.hasServerRenameChipState, isFalse);

      await auth.syncFromBackendUser({
        'id': 'user-1',
        'renameChipShownCount': 2,
        'renameChipDismissedAt': null,
      });
      expect(auth.hasServerRenameChipState, isTrue);
      expect(auth.renameChipShownCount, 2);
      expect(auth.renameChipDismissedAt, isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('auth_rename_chip_shown_count'), 2);

      await auth.signOut();
      expect(auth.hasServerRenameChipState, isFalse);
      expect(auth.renameChipShownCount, isNull);
      expect(prefs.get('auth_rename_chip_shown_count'), isNull);
      expect(prefs.get('auth_rename_chip_dismissed_at'), isNull);
    });

    test('an absent key leaves the cached value untouched', () async {
      SharedPreferences.setMockInitialValues({
        'auth_identity_token': 'apple-token',
        'auth_user_identifier': 'apple-user-123',
        'auth_rename_chip_shown_count': 2,
      });
      final auth = AuthService(backendApiService: _FakeBackendApiService());
      await auth.restoreSession();
      expect(auth.hasServerRenameChipState, isTrue);

      auth.applyBackendUser({'id': 'user-1'});
      expect(auth.renameChipShownCount, 2);
    });
  });
}
