import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/screens/tabs/home_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

/// Item 18 — the hero pace line had no zero/not-started case, so 0 steps at
/// midnight rendered the positive "Clean pace so far" copy, and a null
/// `stepData` was coerced to 0 and got the same line.
class _FakeApi extends BackendApiService {}

const _notStarted = 'Fresh day. Get moving to hit your first milestone.';
const _clean = 'Clean pace so far. Keep walking to hit your first milestone.';
const _nice = 'Nice pace. Tap the milestones below to claim your coins.';
const _huge = 'Huge day. You cleared every milestone — go claim those coins.';

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues(<String, Object>{
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

Future<void> _pumpHome(WidgetTester tester, {required StepData? stepData}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final auth = await _auth();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: HomeTab(
          key: UniqueKey(),
          stepData: stepData,
          isLoading: false,
          error: null,
          healthAuthorized: true,
          notificationsState: true,
          displayName: 'Trail Walker',
          authService: auth,
          backendApiService: _FakeApi(),
          onRefresh: () async {},
          onEnableHealth: () {},
          onEnableNotifications: () {},
          onDisplayNameChanged: () {},
          friendsSteps: const [],
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('0 steps renders the not-started copy, never "Clean pace"', (
    tester,
  ) async {
    await _pumpHome(
      tester,
      stepData: StepData(steps: 0, date: DateTime(2026, 7, 26)),
    );
    expect(find.text(_notStarted), findsOneWidget);
    expect(find.text(_clean), findsNothing);
  });

  testWidgets('a null stepData is not-started, not zero-coerced positive', (
    tester,
  ) async {
    await _pumpHome(tester, stepData: null);
    expect(find.text(_notStarted), findsOneWidget);
    expect(find.text(_clean), findsNothing);
  });

  testWidgets('4,999 steps still gets the positive low-bucket copy', (
    tester,
  ) async {
    await _pumpHome(
      tester,
      stepData: StepData(steps: 4999, date: DateTime(2026, 7, 26)),
    );
    expect(find.text(_clean), findsOneWidget);
    expect(find.text(_notStarted), findsNothing);
  });

  testWidgets('the 5k and 20k buckets are unchanged', (tester) async {
    await _pumpHome(
      tester,
      stepData: StepData(steps: 5000, date: DateTime(2026, 7, 26)),
    );
    expect(find.text(_nice), findsOneWidget);

    await _pumpHome(
      tester,
      stepData: StepData(steps: 20000, date: DateTime(2026, 7, 26)),
    );
    expect(find.text(_huge), findsOneWidget);
  });
}
