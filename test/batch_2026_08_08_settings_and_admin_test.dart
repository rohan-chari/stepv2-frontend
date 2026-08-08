// Feature batch 2026-08-08 — Settings + Admin additions.
//
//  * Item 3 (client half) — milestone reminder toggle, hidden when the backend
//    preferences payload lacks the field.
//  * Item 7 — SEND FEEDBACK sheet (offline keeps the text + retry).
//  * Item 10 — COMMUNITY section.
//  * Item 9 (client half) — admin VERSIONS + RACES sections, hidden when the
//    fields are absent.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/admin_screen.dart';
import 'package:step_tracker/screens/settings_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/notification_service.dart';

class _PrefsApi extends BackendApiService {
  _PrefsApi({required this.prefsPayload, this.throwOnSubmit = false});

  final Map<String, dynamic> prefsPayload;
  final bool throwOnSubmit;

  int submitCalls = 0;
  String? lastSubmittedText;

  @override
  Future<Map<String, dynamic>> fetchNotificationPreferences({
    required String identityToken,
  }) async => prefsPayload;

  @override
  Future<bool> fetchDailyRewardRemindersEnabled({
    required String identityToken,
  }) async => true;

  @override
  Future<void> submitSuggestion({
    required String identityToken,
    required String text,
  }) async {
    submitCalls++;
    lastSubmittedText = text;
    if (throwOnSubmit) {
      throw const ApiException('offline');
    }
  }
}

class _GrantedNotificationService extends NotificationService {
  @override
  Future<bool?> getPermissionState() async => true;

  @override
  Future<bool?> getSystemPermissionState() async => true;
}

class _StatsApi extends BackendApiService {
  _StatsApi(this.stats);

  final Map<String, dynamic> stats;

  @override
  Future<Map<String, dynamic>> fetchAdminStats({
    required String identityToken,
  }) async => stats;
}

Future<AuthService> _authService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Runner',
    'auth_coins': 0,
    'auth_held_coins': 0,
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

Future<void> _pumpSettings(WidgetTester tester, _PrefsApi api) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final auth = await _authService();
  await tester.pumpWidget(
    MaterialApp(
      home: SettingsScreen(
        authService: auth,
        notificationService: _GrantedNotificationService(),
        backendApiService: api,
        onSettingsChanged: () {},
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.bara.steps',
      version: '2.2.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('Item 3 — milestone reminder toggle', () {
    testWidgets('renders when the backend carries the field', (tester) async {
      await _pumpSettings(
        tester,
        _PrefsApi(
          prefsPayload: const {
            'dailyRewardRemindersEnabled': true,
            'stepMilestoneRemindersEnabled': true,
          },
        ),
      );

      expect(
        find.byKey(const Key('settings-milestone-reminder-toggle')),
        findsOneWidget,
      );
      expect(
        find.text('Remind me to collect step milestone coins'),
        findsOneWidget,
      );
    });

    testWidgets('hides against a backend without the field', (tester) async {
      await _pumpSettings(
        tester,
        _PrefsApi(prefsPayload: const {'dailyRewardRemindersEnabled': true}),
      );

      expect(
        find.byKey(const Key('settings-milestone-reminder-toggle')),
        findsNothing,
      );
      // The section itself is intact — the daily-reward toggle still renders.
      expect(
        find.byKey(const Key('settings-section-notifications')),
        findsOneWidget,
      );
      expect(find.text('Remind me to open my daily box'), findsOneWidget);
    });

    testWidgets('an entirely absent preferences endpoint also hides it', (
      tester,
    ) async {
      await _pumpSettings(tester, _PrefsApi(prefsPayload: const {}));
      expect(
        find.byKey(const Key('settings-milestone-reminder-toggle')),
        findsNothing,
      );
    });
  });

  group('Item 10 — COMMUNITY section', () {
    testWidgets('renders Instagram and X rows (TikTok deferred)', (
      tester,
    ) async {
      await _pumpSettings(tester, _PrefsApi(prefsPayload: const {}));

      expect(
        find.byKey(const Key('settings-section-community')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('settings-social-instagram')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('settings-social-x')), findsOneWidget);
      expect(find.text('@bara.steps'), findsOneWidget);
      expect(find.text('@barastepz'), findsOneWidget);
      expect(find.text('TikTok'), findsNothing);
    });

    testWidgets('renders in dark mode too (ink flip trap)', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final auth = await _authService();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: MediaQuery(
            data: const MediaQueryData(platformBrightness: Brightness.dark),
            child: SettingsScreen(
              authService: auth,
              notificationService: _GrantedNotificationService(),
              backendApiService: _PrefsApi(prefsPayload: const {}),
              onSettingsChanged: () {},
            ),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(
        find.byKey(const Key('settings-social-instagram')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Item 7 — SEND FEEDBACK', () {
    testWidgets('sits in HELP & LEGAL and opens the sheet', (tester) async {
      await _pumpSettings(tester, _PrefsApi(prefsPayload: const {}));

      final button = find.byKey(const Key('settings-send-feedback'));
      expect(button, findsOneWidget);

      await tester.ensureVisible(button);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(button);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byKey(const Key('feedback-sheet')), findsOneWidget);
      expect(find.byKey(const Key('feedback-input')), findsOneWidget);
    });

    testWidgets('submits the typed text', (tester) async {
      final api = _PrefsApi(prefsPayload: const {});
      await _pumpSettings(tester, api);

      final button = find.byKey(const Key('settings-send-feedback'));
      await tester.ensureVisible(button);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(button);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      await tester.enterText(
        find.byKey(const Key('feedback-input')),
        '  more capybara hats  ',
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('feedback-submit')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(api.submitCalls, 1);
      expect(api.lastSubmittedText, 'more capybara hats');
      // Sheet closed on success.
      expect(find.byKey(const Key('feedback-sheet')), findsNothing);
    });

    testWidgets('offline keeps the text and offers a retry', (tester) async {
      final api = _PrefsApi(prefsPayload: const {}, throwOnSubmit: true);
      await _pumpSettings(tester, api);

      final button = find.byKey(const Key('settings-send-feedback'));
      await tester.ensureVisible(button);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(button);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      await tester.enterText(
        find.byKey(const Key('feedback-input')),
        'please fix the thing',
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('feedback-submit')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Sheet stays open, text preserved, error shown, button offers RETRY.
      expect(find.byKey(const Key('feedback-sheet')), findsOneWidget);
      expect(find.byKey(const Key('feedback-error')), findsOneWidget);
      expect(find.text('please fix the thing'), findsOneWidget);
      expect(find.text('RETRY'), findsOneWidget);
    });
  });

  group('Item 9 — admin VERSIONS + RACES', () {
    Future<void> pumpAdmin(WidgetTester tester, Map<String, dynamic> stats) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final auth = await _authService();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminStatsCard(
                width: 380,
                authService: auth,
                backendApiService: _StatsApi(stats),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('renders both sections when the backend sends them', (
      tester,
    ) async {
      await pumpAdmin(tester, const {
        'users': {'total': 10},
        'versionsSince': '2026-07-09',
        'versions': [
          {'version': '2.2.0', 'platform': 'ios', 'users': 7},
          {'version': 'unknown', 'users': 3},
        ],
        'races': {
          'privateTotal': 40,
          'privateActive': 5,
          'publicTotal': 12,
          'publicActive': 2,
        },
      });

      expect(find.text('VERSIONS'), findsOneWidget);
      expect(find.text('2.2.0 (ios)'), findsOneWidget);
      expect(find.text('unknown'), findsOneWidget);
      expect(find.text('2026-07-09'), findsOneWidget);
      expect(find.text('RACES'), findsOneWidget);
      expect(find.text('40 / 5'), findsOneWidget);
      expect(find.text('12 / 2'), findsOneWidget);
    });

    testWidgets('hides both sections against an older backend', (tester) async {
      await pumpAdmin(tester, const {
        'users': {'total': 10},
      });

      expect(find.text('VERSIONS'), findsNothing);
      expect(find.text('RACES'), findsNothing);
      // The rest of the card still renders.
      expect(find.text('USERS'), findsOneWidget);
    });

    testWidgets('an empty versions list hides the section', (tester) async {
      await pumpAdmin(tester, const {
        'users': {'total': 10},
        'versions': <Map<String, dynamic>>[],
      });
      expect(find.text('VERSIONS'), findsNothing);
    });
  });
}
