import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/services/auth_service.dart';

// TR-107: remote kill switch for team-race CREATION. When off, clients hide
// the team-race toggle. Default is ON — and defensively, an older backend that
// doesn't send the flag at all must leave the feature available (only an
// explicit false hides it). Existing races are unaffected either way.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('teamRacesEnabled defaults to true', () async {
    final authService = AuthService();
    await authService.restoreSession();
    expect(authService.teamRacesEnabled, isTrue);
  });

  test('applyBackendUser leaves the flag on when featureFlags is absent',
      () async {
    final authService = AuthService();
    await authService.restoreSession();
    authService.applyBackendUser({'displayName': 'Trail Walker'});
    expect(authService.teamRacesEnabled, isTrue);
  });

  test('applyBackendUser leaves the flag on when the key is missing from '
      'featureFlags (older backend)', () async {
    final authService = AuthService();
    await authService.restoreSession();
    authService.applyBackendUser({
      'featureFlags': {'bannerAdsEnabled': true},
    });
    expect(authService.teamRacesEnabled, isTrue);
  });

  test('applyBackendUser turns the flag off only on an explicit false',
      () async {
    final authService = AuthService();
    await authService.restoreSession();
    authService.applyBackendUser({
      'featureFlags': {'teamRacesEnabled': false},
    });
    expect(authService.teamRacesEnabled, isFalse);

    authService.applyBackendUser({
      'featureFlags': {'teamRacesEnabled': true},
    });
    expect(authService.teamRacesEnabled, isTrue);
  });

  test('applyBackendUser also honors the appSettings envelope (contract §12)',
      () async {
    final authService = AuthService();
    await authService.restoreSession();
    authService.applyBackendUser({
      'appSettings': {'teamRacesEnabled': false},
    });
    expect(authService.teamRacesEnabled, isFalse);

    authService.applyBackendUser({
      'appSettings': {'teamRacesEnabled': true},
    });
    expect(authService.teamRacesEnabled, isTrue);
  });

  test('kill switch state persists across instances', () async {
    final authService = AuthService();
    await authService.restoreSession();
    await authService.syncFromBackendUser({
      'featureFlags': {'teamRacesEnabled': false},
    });

    final restored = AuthService();
    await restored.restoreSession();
    expect(restored.teamRacesEnabled, isFalse);
  });
}
