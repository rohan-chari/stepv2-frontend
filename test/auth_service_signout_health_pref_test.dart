import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('signOut clears device-scoped health authorization', () {
    test('health_authorized does not survive sign-out', () async {
      SharedPreferences.setMockInitialValues({
        'auth_identity_token': 'apple-token',
        'auth_user_identifier': 'apple-user-123',
        'auth_session_token': 'session-token',
        'auth_backend_user_id': 'user-1',
        'auth_display_name': 'Trail Walker',
        // Granted under the PREVIOUS account, on this device.
        'health_authorized': true,
      });

      final authService = AuthService();
      await authService.restoreSession();
      await authService.signOut();

      final prefs = await SharedPreferences.getInstance();
      // Left behind, this makes a re-signup on the same device look already
      // authorized, so the onboarding health gate never renders.
      expect(prefs.getBool('health_authorized'), isNull);
    });

    test('sign-out is safe when health was never authorized', () async {
      SharedPreferences.setMockInitialValues({
        'auth_identity_token': 'apple-token',
        'auth_user_identifier': 'apple-user-123',
        'auth_session_token': 'session-token',
      });

      final authService = AuthService();
      await authService.restoreSession();
      await authService.signOut();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('health_authorized'), isNull);
    });
  });

  group('featureFlags envelope is only applied when present', () {
    test('a payload without featureFlags does not flip v2 off', () async {
      SharedPreferences.setMockInitialValues({});
      final authService = AuthService();

      authService.applyBackendUser({
        'id': 'user-1',
        'featureFlags': {'onboardingV2Enabled': true},
      });
      expect(authService.onboardingV2Enabled, isTrue);

      // A later response that omits the envelope entirely (an older backend,
      // or an endpoint that doesn't wrap) must not silently downgrade the
      // session to v1 mid-onboarding.
      authService.applyBackendUser({'id': 'user-1', 'coins': 40});
      expect(authService.onboardingV2Enabled, isTrue);
    });

    test('an explicit false in the envelope still disables v2', () async {
      SharedPreferences.setMockInitialValues({});
      final authService = AuthService();

      authService.applyBackendUser({
        'id': 'user-1',
        'featureFlags': {'onboardingV2Enabled': true},
      });
      expect(authService.onboardingV2Enabled, isTrue);

      authService.applyBackendUser({
        'id': 'user-1',
        'featureFlags': {'onboardingV2Enabled': false},
      });
      expect(authService.onboardingV2Enabled, isFalse);
    });

    test('v2 stays off when the envelope is present but omits the flag', () {
      SharedPreferences.setMockInitialValues({});
      final authService = AuthService();

      authService.applyBackendUser({
        'id': 'user-1',
        'featureFlags': {'bannerAdsEnabled': true},
      });
      expect(authService.onboardingV2Enabled, isFalse);
    });
  });
}
