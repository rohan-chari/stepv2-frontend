import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/referral_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _RedeemReferralApi extends BackendApiService {
  _RedeemReferralApi({required this.attributed, this.reason});
  final bool attributed;
  final String? reason;

  @override
  Future<Map<String, dynamic>> fetchReferralStatus({
    required String identityToken,
  }) async => {
    'code': 'BARA-7F3K',
    'url': 'https://steptracker-api.org/r/BARA-7F3K',
    'referredCount': 0,
    'completedCount': 0,
    'coinsEarned': 0,
    'friends': const [],
  };

  @override
  Future<Map<String, dynamic>> redeemReferralCode({
    required String identityToken,
    required String code,
  }) async => {'attributed': attributed, if (reason != null) 'reason': reason};
}

Future<AuthService> _createAuthService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

Future<void> _enterCodeAndApply(WidgetTester tester) async {
  await tester.tap(find.text('Have an invite code?'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400)); // open the sheet
  await tester.enterText(find.byType(TextField), 'BARA-XXXX');
  await tester.tap(find.text('APPLY'));
  // Close the sheet, resolve the redeem future, slide the toast in.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _flushToast(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('successful redeem shows an info toast, not a SnackBar', (
    tester,
  ) async {
    final auth = await _createAuthService();
    await tester.pumpWidget(
      MaterialApp(
        home: ReferralScreen(
          authService: auth,
          backendApiService: _RedeemReferralApi(attributed: true),
        ),
      ),
    );
    await tester.pump(); // resolve fetch

    await _enterCodeAndApply(tester);

    expect(find.byType(SnackBar), findsNothing);
    expect(find.byKey(const Key('info-toast-shell')), findsOneWidget);
    expect(
      find.text("You're in! Finish your first race to earn coins."),
      findsOneWidget,
    );

    await _flushToast(tester);
  });

  testWidgets('rejected redeem shows an error toast, not a SnackBar', (
    tester,
  ) async {
    final auth = await _createAuthService();
    await tester.pumpWidget(
      MaterialApp(
        home: ReferralScreen(
          authService: auth,
          backendApiService: _RedeemReferralApi(
            attributed: false,
            reason: 'self_referral',
          ),
        ),
      ),
    );
    await tester.pump(); // resolve fetch

    await _enterCodeAndApply(tester);

    expect(find.byType(SnackBar), findsNothing);
    expect(find.byKey(const Key('error-toast-shell')), findsOneWidget);
    expect(
      find.text("You can't use your own invite code."),
      findsOneWidget,
    );

    await _flushToast(tester);
  });
}
