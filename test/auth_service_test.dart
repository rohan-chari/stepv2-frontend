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

class _ProvisionRecordingApi extends BackendApiService {
  String? appleSourceRaceToken;

  @override
  Future<Map<String, dynamic>> provisionAppleUser({
    required String identityToken,
    required String userIdentifier,
    String? email,
    String? referralCode,
    String? referralSourceRaceToken,
  }) async {
    appleSourceRaceToken = referralSourceRaceToken;
    return {
      'user': {'id': 'user-1'},
      'sessionToken': 'session',
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'discoverable identity support is contains-key guarded and defensive',
    () {
      final auth = AuthService();

      expect(auth.supportsDiscoverableIdentity, isFalse);
      expect(auth.requiresDiscoverableIdentityOnboarding, isFalse);

      auth.applyBackendUser({
        'firstName': 'Nathan',
        'lastName': null,
        'nameSetupOnboardingRequired': true,
        'nameSetupCompletedAt': null,
        'featureFlags': {'racesInviteDecisionGateEnabled': true},
      });

      expect(auth.supportsDiscoverableIdentity, isTrue);
      expect(auth.firstName, 'Nathan');
      expect(auth.lastName, isNull);
      expect(auth.requiresDiscoverableIdentityOnboarding, isTrue);
      expect(auth.racesInviteDecisionGateEnabled, isTrue);

      auth.applyBackendUser({
        'firstName': 42,
        'lastName': <String>[],
        'nameSetupOnboardingRequired': 'yes',
        'nameSetupCompletedAt': 123,
        'featureFlags': {'racesInviteDecisionGateEnabled': 'yes'},
      });

      expect(auth.firstName, isNull);
      expect(auth.lastName, isNull);
      expect(auth.requiresDiscoverableIdentityOnboarding, isFalse);
      expect(auth.racesInviteDecisionGateEnabled, isFalse);
    },
  );

  test(
    'absent identity fields do not turn an old backend into incomplete setup',
    () {
      final auth = AuthService();
      auth.applyBackendUser({'displayName': 'TrailWalker'});

      expect(auth.supportsDiscoverableIdentity, isFalse);
      expect(auth.shouldShowDiscoverableIdentityRemediation, isFalse);
    },
  );

  test(
    'quick-race share capability is literal, persisted, and authoritative',
    () async {
      SharedPreferences.setMockInitialValues({
        'auth_identity_token': 'identity',
        'auth_user_identifier': 'platform-user',
        'auth_session_token': 'session',
        'auth_backend_user_id': 'user-1',
      });
      final auth = AuthService();
      await auth.restoreSession();

      await auth.syncFromBackendUser({
        'id': 'user-1',
        'featureFlags': {'quickRaceShareAutoFriendEnabled': true},
      }, authoritative: true);
      expect(auth.quickRaceShareAutoFriendEnabled, isTrue);

      final restored = AuthService();
      await restored.restoreSession();
      expect(restored.quickRaceShareAutoFriendEnabled, isTrue);

      // A partial mutation without featureFlags is not capability evidence.
      restored.applyBackendUser({'displayName': 'Renamed'});
      expect(restored.quickRaceShareAutoFriendEnabled, isTrue);

      await restored.syncFromBackendUser({'id': 'user-1'}, authoritative: true);
      expect(restored.quickRaceShareAutoFriendEnabled, isFalse);
      final restoredAfterOldBackend = AuthService();
      await restoredAfterOldBackend.restoreSession();
      expect(restoredAfterOldBackend.quickRaceShareAutoFriendEnabled, isFalse);

      for (final payload in <Map<String, dynamic>>[
        {'id': 'user-1', 'featureFlags': null},
        {'id': 'user-1', 'featureFlags': 'bad'},
        {
          'id': 'user-1',
          'featureFlags': {'quickRaceShareAutoFriendEnabled': null},
        },
        {
          'id': 'user-1',
          'featureFlags': {'quickRaceShareAutoFriendEnabled': 'yes'},
        },
        {
          'id': 'user-1',
          'featureFlags': {'quickRaceShareAutoFriendEnabled': false},
        },
      ]) {
        restored.applyBackendUser({
          'featureFlags': {'quickRaceShareAutoFriendEnabled': true},
        });
        restored.applyBackendUser(payload, authoritative: true);
        expect(restored.quickRaceShareAutoFriendEnabled, isFalse);
      }

      restored.applyBackendUser({
        'featureFlags': {'quickRaceShareAutoFriendEnabled': true},
      });
      await restored.signOut();
      expect(restored.quickRaceShareAutoFriendEnabled, isFalse);
    },
  );

  test(
    'authoritative old-backend user clears cached identity capability state',
    () async {
      SharedPreferences.setMockInitialValues({
        'auth_identity_token': 'identity',
        'auth_user_identifier': 'platform-user',
        'auth_session_token': 'session',
        'auth_backend_user_id': 'user-1',
        'auth_identity_state_user_id': 'user-1',
        'auth_identity_supported': true,
        'auth_first_name': 'Cached',
        'auth_last_name': 'Walker',
        'auth_name_setup_onboarding_required': true,
      });
      final auth = AuthService();
      await auth.restoreSession();

      expect(auth.requiresDiscoverableIdentityOnboarding, isTrue);
      expect(auth.shouldShowDiscoverableIdentityRemediation, isTrue);

      await auth.syncFromBackendUser({
        'id': 'user-1',
        'displayName': 'Old Backend User',
      }, authoritative: true);

      expect(auth.supportsDiscoverableIdentity, isFalse);
      expect(auth.nameSetupOnboardingRequired, isFalse);
      expect(auth.requiresDiscoverableIdentityOnboarding, isFalse);
      expect(auth.shouldShowDiscoverableIdentityRemediation, isFalse);

      // A partial mutation response is not capability evidence and may retain
      // the last authoritative state.
      auth.applyBackendUser({
        'nameSetupCompletedAt': null,
        'nameSetupOnboardingRequired': true,
      });
      await auth.syncFromBackendUser({'displayName': 'Renamed'});
      expect(auth.supportsDiscoverableIdentity, isTrue);
      expect(auth.requiresDiscoverableIdentityOnboarding, isTrue);
    },
  );

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

  test(
    'Apple provision receives pending race attribution without consuming it',
    () async {
      final api = _ProvisionRecordingApi();
      final authService = AuthService(
        backendApiService: api,
        appleCredentialProvider: () async =>
            const AuthorizationCredentialAppleID(
              userIdentifier: 'apple-user',
              givenName: 'Nathan',
              familyName: 'Chari',
              authorizationCode: 'code',
              email: null,
              identityToken: 'identity',
              state: null,
            ),
      );
      await authService.setPendingShareToken('raceToken123');

      expect(await authService.signInWithApple(), isTrue);
      expect(api.appleSourceRaceToken, 'raceToken123');
      expect(authService.pendingShareToken, 'raceToken123');
      expect(authService.providerFirstName, 'Nathan');
      expect(authService.providerLastName, 'Chari');

      final restored = AuthService();
      await restored.restoreSession();
      expect(restored.providerFirstName, 'Nathan');
      expect(restored.providerLastName, 'Chari');
    },
  );

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
