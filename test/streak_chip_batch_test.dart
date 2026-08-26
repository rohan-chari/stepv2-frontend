import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/ad_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/pill_button.dart';
import 'package:step_tracker/widgets/streak_chip.dart';

String _todayLocalDate() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)}';
}

class _FakeDailyRewardApi extends BackendApiService {
  int statusCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchDailyRewardStatus({
    required String identityToken,
    required String localDate,
  }) async {
    statusCalls += 1;
    return {'claimedToday': false};
  }
}

class _DelayedDailyRewardApi extends BackendApiService {
  final Completer<Map<String, dynamic>> response = Completer();

  @override
  Future<Map<String, dynamic>> fetchDailyRewardStatus({
    required String identityToken,
    required String localDate,
  }) => response.future;
}

class _FakeAdController implements ExtraSpinAdController {
  int loadCalls = 0;

  @override
  bool get isSupported => true;

  @override
  bool get isReady => false;

  @override
  Future<void> load({required String userId, required String localDate}) async {
    loadCalls++;
  }

  @override
  Future<bool> showAndAwaitReward() async => false;

  @override
  void dispose() {}
}

Future<AuthService> _createAuthService() async {
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
  testWidgets(
    'StreakChip renders synchronously from batch initialData without fetching',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final api = _FakeDailyRewardApi();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StreakChip(
              authService: authService,
              backendApiService: api,
              initialData: {
                'claimedToday': false,
                'localDate': _todayLocalDate(),
              },
            ),
          ),
        ),
      );

      // No pump-and-settle needed: the batch payload renders in-frame.
      expect(find.text('CLAIM REWARD'), findsOneWidget);
      expect(api.statusCalls, 0);
    },
  );

  testWidgets('StreakChip keeps the Daily Reward destination when claimed', (
    WidgetTester tester,
  ) async {
    final authService = await _createAuthService();
    final api = _FakeDailyRewardApi();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreakChip(
            authService: authService,
            backendApiService: api,
            initialData: {'claimedToday': true, 'localDate': _todayLocalDate()},
          ),
        ),
      ),
    );

    expect(find.text('DAILY REWARD'), findsOneWidget);
    expect(api.statusCalls, 0);
  });

  testWidgets('compact claimed reward uses the vertical check action', (
    WidgetTester tester,
  ) async {
    final authService = await _createAuthService();
    final api = _FakeDailyRewardApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 58,
            width: 180,
            child: StreakChip(
              compact: true,
              authService: authService,
              backendApiService: api,
              initialData: {
                'claimedToday': true,
                'localDate': _todayLocalDate(),
              },
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.check_box_rounded), findsOneWidget);
    expect(find.bySemanticsLabel('Open daily reward'), findsOneWidget);
    expect(
      find.byKey(const Key('home-daily-reward-compact-layout')),
      findsOneWidget,
    );
    expect(api.statusCalls, 0);
  });

  testWidgets(
    'StreakChip falls back to the standalone fetch on an old backend',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final api = _FakeDailyRewardApi();

      // No initialData and no batch in flight: the old-backend path.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StreakChip(authService: authService, backendApiService: api),
          ),
        ),
      );

      // Blank placeholder while the fallback fetch is in flight.
      expect(find.byType(PillButton), findsNothing);
      await tester.pump();

      expect(api.statusCalls, 1);
      expect(find.text('CLAIM REWARD'), findsOneWidget);
    },
  );

  testWidgets('StreakChip consumes the batch when it lands after mount', (
    WidgetTester tester,
  ) async {
    final authService = await _createAuthService();
    final api = _FakeDailyRewardApi();

    Widget build({Map<String, dynamic>? initialData, required bool loading}) {
      return MaterialApp(
        home: Scaffold(
          body: StreakChip(
            authService: authService,
            backendApiService: api,
            initialData: initialData,
            awaitingBatch: loading,
          ),
        ),
      );
    }

    // Batch in flight: hold off the fallback fetch.
    await tester.pumpWidget(build(initialData: null, loading: true));
    await tester.pump();
    expect(api.statusCalls, 0);
    expect(find.byType(PillButton), findsNothing);

    // Batch lands with the field: consumed, still no standalone request.
    await tester.pumpWidget(
      build(
        initialData: {'claimedToday': true, 'localDate': _todayLocalDate()},
        loading: false,
      ),
    );
    await tester.pump();
    expect(api.statusCalls, 0);
    expect(find.text('DAILY REWARD'), findsOneWidget);
  });

  testWidgets('StreakChip refetches when the batch payload is stale', (
    WidgetTester tester,
  ) async {
    final authService = await _createAuthService();
    final api = _FakeDailyRewardApi();

    // A payload computed before midnight must not be trusted.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreakChip(
            authService: authService,
            backendApiService: api,
            initialData: const {
              'claimedToday': true,
              'localDate': '2000-01-01',
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(api.statusCalls, 1);
    expect(find.text('CLAIM REWARD'), findsOneWidget);
  });

  testWidgets(
    'StreakChip ignores a status response from the previous account',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final api = _DelayedDailyRewardApi();
      final ads = _FakeAdController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StreakChip(
              authService: authService,
              backendApiService: api,
              adController: ads,
            ),
          ),
        ),
      );
      await tester.pump();

      await authService.updateSessionToken('new-session');
      await authService.syncFromBackendUser(const {'id': 'user-2'});
      api.response.complete({
        'claimedToday': true,
        'adExtraSpin': {
          'available': true,
          'pendingGrant': false,
          'used': false,
        },
      });
      await tester.pump();

      expect(ads.loadCalls, 0);
      expect(find.text('EXTRA SPIN'), findsNothing);
    },
  );
}
