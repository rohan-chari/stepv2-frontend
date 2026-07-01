import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/profile_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _DeleteFailApi extends BackendApiService {
  @override
  Future<void> deleteAccount({required String identityToken}) async {
    throw const ApiException('network down');
  }

  @override
  Future<List<Map<String, dynamic>>> fetchFriendsSteps({
    required String identityToken,
    required String date,
  }) async => const [];

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async =>
      const {
        'displayName': 'Trail Walker',
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
}

Future<AuthService> _createAuthService(BackendApiService api) async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
  });
  final authService = AuthService(backendApiService: api);
  await authService.restoreSession();
  return authService;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('delete-account failure shows an error toast, not a SnackBar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _DeleteFailApi();
    final authService = await _createAuthService(api);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileTab(
            authService: authService,
            displayName: 'Trail Walker',
            email: 'walker@example.com',
            onSettingsChanged: () {},
            backendApiService: api,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // Open the settings sheet.
    await tester.tap(find.text('SETTINGS'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Tap DELETE ACCOUNT -> confirm dialog.
    await tester.ensureVisible(find.text('DELETE ACCOUNT'));
    await tester.tap(find.text('DELETE ACCOUNT'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Confirm deletion; the backend call throws and surfaces a toast.
    await tester.tap(find.text('DELETE'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.byType(SnackBar), findsNothing);
    expect(find.byKey(const Key('error-toast-shell')), findsOneWidget);
    expect(find.textContaining('Failed to delete account'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 300));
  });
}
