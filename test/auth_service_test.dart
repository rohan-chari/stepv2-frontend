import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _RecordingLeaderboardApi extends BackendApiService {
  bool? lastHidden;
  int calls = 0;

  @override
  Future<Map<String, dynamic>> updateLeaderboardVisibility({
    required String identityToken,
    required bool hidden,
  }) async {
    calls += 1;
    lastHidden = hidden;
    return {'hiddenFromLeaderboard': hidden};
  }
}

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

  test('dismissing Apple sign-in is a silent cancellation', () async {
    final authService = AuthService(
      appleCredentialProvider: () async =>
          throw const SignInWithAppleAuthorizationException(
            code: AuthorizationErrorCode.canceled,
            message: 'The operation was cancelled.',
          ),
    );

    expect(await authService.signInWithApple(), isFalse);
    expect(authService.lastErrorMessage, isNull);
  });

  test('a genuine Apple sign-in failure gets friendly copy', () async {
    final authService = AuthService(
      appleCredentialProvider: () async =>
          throw const SignInWithAppleAuthorizationException(
            code: AuthorizationErrorCode.failed,
            message: 'Raw native SDK details',
          ),
    );

    expect(await authService.signInWithApple(), isFalse);
    expect(
      authService.lastErrorMessage,
      'Apple sign-in couldn’t be completed. Please try again.',
    );
    expect(authService.lastErrorMessage, isNot(contains('Raw native')));
  });

  test('dismissing Google sign-in is a silent cancellation', () async {
    final authService = AuthService(googleAccountProvider: () async => null);

    expect(await authService.signInWithGoogle(), isFalse);
    expect(authService.lastErrorMessage, isNull);
  });

  test('pendingShareToken defaults to null', () async {
    final authService = AuthService();
    await authService.restoreSession();
    expect(authService.pendingShareToken, isNull);
  });

  test(
    'setPendingShareToken persists across instances (survives install gap)',
    () async {
      final authService = AuthService();
      await authService.setPendingShareToken('tok-abc');
      expect(authService.pendingShareToken, 'tok-abc');

      // A fresh instance (e.g. relaunch after onboarding) restores the token, so
      // the share intent survives the sign-in/onboarding gap.
      final restored = AuthService();
      await restored.restoreSession();
      expect(restored.pendingShareToken, 'tok-abc');
    },
  );

  test('setPendingShareToken(null) clears the persisted token', () async {
    final authService = AuthService();
    await authService.setPendingShareToken('tok-abc');
    await authService.setPendingShareToken(null);
    expect(authService.pendingShareToken, isNull);

    final restored = AuthService();
    await restored.restoreSession();
    expect(restored.pendingShareToken, isNull);
  });

  test('signOut clears a pending share token', () async {
    SharedPreferences.setMockInitialValues({
      'auth_identity_token': 'apple-token',
      'auth_user_identifier': 'apple-user-123',
      'auth_session_token': 'session-token',
    });
    final authService = AuthService();
    await authService.restoreSession();
    await authService.setPendingShareToken('tok-abc');

    await authService.signOut();

    expect(authService.pendingShareToken, isNull);
    final restored = AuthService();
    await restored.restoreSession();
    expect(restored.pendingShareToken, isNull);
  });

  test('pendingReferralCode defaults to null', () async {
    final authService = AuthService();
    await authService.restoreSession();
    expect(authService.pendingReferralCode, isNull);
  });

  test(
    'setPendingReferralCode persists across instances (survives install gap)',
    () async {
      final authService = AuthService();
      await authService.setPendingReferralCode('BARA-7F3K');
      expect(authService.pendingReferralCode, 'BARA-7F3K');

      final restored = AuthService();
      await restored.restoreSession();
      expect(restored.pendingReferralCode, 'BARA-7F3K');
    },
  );

  test('setPendingReferralCode is first-capture-wins (no overwrite)', () async {
    final authService = AuthService();
    await authService.setPendingReferralCode('BARA-AAAA');
    // A later capture must NOT overwrite the first invite tapped.
    await authService.setPendingReferralCode('BARA-BBBB');
    expect(authService.pendingReferralCode, 'BARA-AAAA');
  });

  test('setPendingReferralCode(null) clears the persisted code', () async {
    final authService = AuthService();
    await authService.setPendingReferralCode('BARA-7F3K');
    await authService.setPendingReferralCode(null);
    expect(authService.pendingReferralCode, isNull);

    final restored = AuthService();
    await restored.restoreSession();
    expect(restored.pendingReferralCode, isNull);
  });

  test('pendingReferralCode expires after the max age', () async {
    // A code captured 40 days ago is past the 30-day window, so it's ignored.
    final fortyDaysAgoMs = DateTime.now()
        .subtract(const Duration(days: 40))
        .millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      'auth_pending_referral_code': 'BARA-7F3K',
      'auth_pending_referral_captured_at': fortyDaysAgoMs,
    });
    final authService = AuthService();
    await authService.restoreSession();
    expect(authService.pendingReferralCode, isNull);
  });

  test('hiddenFromLeaderboard defaults to false', () async {
    final authService = AuthService();
    await authService.restoreSession();
    expect(authService.hiddenFromLeaderboard, isFalse);
  });

  test(
    'applyBackendUser ignores hiddenFromLeaderboard when the key is absent',
    () async {
      final authService = AuthService();
      // Older backend payload without the field must not crash or flip state.
      authService.applyBackendUser({'displayName': 'Trail Walker'});
      expect(authService.hiddenFromLeaderboard, isFalse);
    },
  );

  test(
    'applyBackendUser merges hiddenFromLeaderboard only when the key is present',
    () async {
      final authService = AuthService();
      authService.applyBackendUser({'hiddenFromLeaderboard': true});
      expect(authService.hiddenFromLeaderboard, isTrue);
      authService.applyBackendUser({'hiddenFromLeaderboard': false});
      expect(authService.hiddenFromLeaderboard, isFalse);
    },
  );

  test(
    'updateLeaderboardVisibility calls the API, updates state, notifies',
    () async {
      SharedPreferences.setMockInitialValues({
        'auth_identity_token': 'apple-token',
        'auth_user_identifier': 'apple-user-123',
        'auth_session_token': 'session-token',
      });
      final api = _RecordingLeaderboardApi();
      final authService = AuthService(backendApiService: api);
      await authService.restoreSession();

      var notified = 0;
      authService.addListener(() => notified++);

      await authService.updateLeaderboardVisibility(true);

      expect(api.calls, 1);
      expect(api.lastHidden, isTrue);
      expect(authService.hiddenFromLeaderboard, isTrue);
      expect(notified, greaterThan(0));

      // Persisted: a fresh instance restores the toggle.
      final restored = AuthService();
      await restored.restoreSession();
      expect(restored.hiddenFromLeaderboard, isTrue);
    },
  );

  test('welcomeReferralCode restores and clears (one-shot)', () async {
    SharedPreferences.setMockInitialValues({
      'auth_welcome_referral_code': 'BARA-7F3K',
    });
    final authService = AuthService();
    await authService.restoreSession();
    expect(authService.welcomeReferralCode, 'BARA-7F3K');

    await authService.clearWelcomeReferralCode();
    expect(authService.welcomeReferralCode, isNull);

    // Cleared from storage too — the welcome never shows twice.
    final restored = AuthService();
    await restored.restoreSession();
    expect(restored.welcomeReferralCode, isNull);
  });
}
