import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'restoreSession returns false when a session token is missing',
    () async {
      SharedPreferences.setMockInitialValues({
        'auth_identity_token': 'apple-token',
        'auth_user_identifier': 'apple-user-123',
      });

      final authService = AuthService();
      final restored = await authService.restoreSession();

      expect(restored, isFalse);
      expect(authService.sessionToken, isNull);
    },
  );

  test('restoreSession returns true when a session token is present', () async {
    SharedPreferences.setMockInitialValues({
      'auth_identity_token': 'apple-token',
      'auth_user_identifier': 'apple-user-123',
      'auth_session_token': 'session-token',
      'auth_is_admin': true,
    });

    final authService = AuthService();
    final restored = await authService.restoreSession();

    expect(restored, isTrue);
    expect(authService.authToken, 'session-token');
    expect(authService.isAdmin, isTrue);
  });

  test('updateAdminAccess persists the admin flag', () async {
    final authService = AuthService();

    await authService.updateAdminAccess(true);

    final restoredService = AuthService();
    final restored = await restoredService.restoreSession();

    expect(restored, isFalse);
    expect(restoredService.isAdmin, isTrue);
  });

  test('isAuthenticationFailure returns true for unauthorized api errors', () {
    expect(
      isAuthenticationFailure(
        const ApiException('Session token is invalid', statusCode: 401),
      ),
      isTrue,
    );
  });

  test('isAuthenticationFailure returns false for non-auth api errors', () {
    expect(
      isAuthenticationFailure(
        const ApiException('Something went wrong', statusCode: 500),
      ),
      isFalse,
    );
  });
}
