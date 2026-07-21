import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('onboarding v2 defaults false when feature flags are missing', () async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthService();
    auth.applyBackendUser({'id': 'user-1'});
    expect(auth.onboardingV2Enabled, isFalse);
  });

  test('only literal true enables onboarding v2 and value persists', () async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthService();
    await auth.syncFromBackendUser({
      'id': 'user-1',
      'featureFlags': {'onboardingV2Enabled': true},
    });
    expect(auth.onboardingV2Enabled, isTrue);

    final restored = AuthService();
    await restored.restoreSession();
    expect(restored.onboardingV2Enabled, isTrue);

    await auth.syncFromBackendUser({
      'featureFlags': {'onboardingV2Enabled': null},
    });
    expect(auth.onboardingV2Enabled, isFalse);
  });
}
