import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'ad_service.dart';
import 'backend_api_service.dart';
import 'health_service.dart';

/// The Firebase project's **Web** OAuth client id, passed to GoogleSignIn as
/// `serverClientId` so the returned ID token's `aud` matches what the backend
/// verifies (`GOOGLE_AUTH_CLIENT_ID`). Not a secret. Same value for the prod
/// and `.staging` apps. See ANDROID.md §D.
const String kGoogleServerClientId =
    '784756906133-8b5umuhi93u40lg0pf11rf1grksj44cg.apps.googleusercontent.com';

/// The **iOS** OAuth client id for Google Sign-In, injected per build via
/// `--dart-define=GOOGLE_IOS_CLIENT_ID=…` (prod and staging bundle ids have
/// separate iOS clients — see DEPLOYMENT.md). Unlike Android, the iOS Google
/// SDK issues ID tokens with `aud` = this iOS client id, so the backend's
/// GOOGLE_AUTH_CLIENT_ID allowlist must include it. When the define is absent
/// (older build recipes, local dev) the Google button is hidden on iOS and
/// sign-in stays Apple-only, so forgetting the define can't ship a broken
/// button. Not a secret.
const String kGoogleIosClientId = String.fromEnvironment(
  'GOOGLE_IOS_CLIENT_ID',
);

/// Whether Google Sign-In can work in this build: always on Android; on iOS
/// only when the iOS OAuth client id was baked in at build time.
bool get isGoogleSignInAvailable =>
    Platform.isAndroid || (Platform.isIOS && kGoogleIosClientId.isNotEmpty);

GoogleSignIn _buildGoogleSignIn() {
  return GoogleSignIn(
    // iOS requires its own client id; Android resolves it from
    // google-services.json and must not receive one here.
    clientId: Platform.isIOS ? kGoogleIosClientId : null,
    serverClientId: kGoogleServerClientId,
    scopes: const ['email'],
  );
}

bool isAuthenticationFailure(Object error) {
  return error is ApiException && error.statusCode == 401;
}

typedef AppleCredentialProvider =
    Future<AuthorizationCredentialAppleID> Function();
typedef GoogleAccountProvider = Future<GoogleSignInAccount?> Function();

class AuthService extends ChangeNotifier {
  AuthService({
    BackendApiService? backendApiService,
    AppleCredentialProvider? appleCredentialProvider,
    GoogleAccountProvider? googleAccountProvider,
  }) : _backendApiService = backendApiService ?? BackendApiService(),
       _appleCredentialProvider =
           appleCredentialProvider ??
           (() => SignInWithApple.getAppleIDCredential(
             scopes: [AppleIDAuthorizationScopes.email],
           )),
       _googleAccountProvider =
           googleAccountProvider ?? (() => _buildGoogleSignIn().signIn());

  static const _keyIdentityToken = 'auth_identity_token';
  static const _keyUserIdentifier = 'auth_user_identifier';
  static const _keyBackendUserId = 'auth_backend_user_id';
  static const _keyDisplayName = 'auth_display_name';
  static const _keyProfilePhotoUrl = 'auth_profile_photo_url';
  static const _keyProfilePhotoPromptDismissedAt =
      'auth_profile_photo_prompt_dismissed_at';
  static const _keySessionToken = 'auth_session_token';
  static const _keyIsAdmin = 'auth_is_admin';
  static const _keyCoins = 'auth_coins';
  static const _keyHeldCoins = 'auth_held_coins';
  static const _keyFirstRaceOnboardingSeen = 'auth_first_race_onboarding_seen';
  static const _keyTutorialOnboardingSeen = 'auth_tutorial_onboarding_seen';
  static const _keyHiddenFromLeaderboard = 'auth_hidden_from_leaderboard';
  static const _keyAutoJoinFeaturedRaces = 'auth_auto_join_featured_races';
  static const _keyBannerAdsEnabled = 'auth_banner_ads_enabled';
  static const _keyDualBoxBannersEnabled = 'auth_dual_box_banners_enabled';
  static const _keyTeamRacesEnabled = 'auth_team_races_enabled';
  static const _keyOnboardingV2Enabled = 'auth_onboarding_v2_enabled';
  static const _keyStepSampleBucketMinutes = 'auth_step_sample_bucket_minutes';
  static const _keyPendingShareToken = 'auth_pending_share_token';
  static const _keyPendingTournamentShareToken =
      'auth_pending_tournament_share_token';
  static const _keyPendingInviterRace = 'auth_pending_inviter_race';
  static const _keyPendingReferralCode = 'auth_pending_referral_code';
  static const _keyPendingReferralCapturedAt =
      'auth_pending_referral_captured_at';
  // One-shot: the code a just-signed-in user was referred with, stashed so the
  // onboarding welcome can greet them by inviter. Set at sign-in (the pending
  // code is cleared there to prevent re-apply), read once by the welcome step,
  // then cleared. Distinct from _keyPendingReferralCode for exactly that reason.
  static const _keyWelcomeReferralCode = 'auth_welcome_referral_code';

  /// How long a captured referral code stays usable client-side. After this it
  /// is ignored (the server also enforces a signup→first-race window).
  static const Duration _pendingReferralMaxAge = Duration(days: 30);

  final BackendApiService _backendApiService;
  final AppleCredentialProvider _appleCredentialProvider;
  final GoogleAccountProvider _googleAccountProvider;
  String? _identityToken;
  String? _userIdentifier;
  String? _backendUserId;
  String? _lastErrorMessage;
  String? _displayName;
  String? _profilePhotoUrl;
  String? _profilePhotoPromptDismissedAt;
  String? _sessionToken;
  bool _isAdmin = false;
  int _coins = 0;
  int _heldCoins = 0;
  bool _firstRaceOnboardingSeen = false;
  bool _tutorialOnboardingSeen = false;
  bool _hiddenFromLeaderboard = false;
  bool _autoJoinFeaturedRaces = false;
  bool _bannerAdsEnabled = false;
  bool _dualBoxBannersEnabled = false;
  bool _teamRacesEnabled = true;
  bool _onboardingV2Enabled = false;
  int _stepSampleBucketMinutes = 60;
  String? _pendingShareToken;
  String? _pendingTournamentShareToken;
  Map<String, String>? _pendingInviterRace;
  String? _pendingReferralCode;
  int? _pendingReferralCapturedAtMs;
  String? _welcomeReferralCode;

  String? get identityToken => _identityToken;
  String? get sessionToken => _sessionToken;
  String? get authToken => _sessionToken ?? _identityToken;
  String? get userId => _backendUserId;
  String? get lastErrorMessage => _lastErrorMessage;
  String? get displayName => _displayName;
  String? get profilePhotoUrl => _profilePhotoUrl;
  String? get profilePhotoPromptDismissedAt => _profilePhotoPromptDismissedAt;
  bool get isAdmin => _isAdmin;
  int get coins => _coins;
  int get heldCoins => _heldCoins;
  bool get firstRaceOnboardingSeen => _firstRaceOnboardingSeen;
  bool get tutorialOnboardingSeen => _tutorialOnboardingSeen;
  bool get hiddenFromLeaderboard => _hiddenFromLeaderboard;
  bool get autoJoinFeaturedRaces => _autoJoinFeaturedRaces;

  /// Remote kill switch for banner ads (backend `featureFlags.bannerAdsEnabled`
  /// on /auth/me, toggleable from Admin → Settings). Mirrored into
  /// [AdService.remoteBannersEnabled] wherever it changes.
  bool get bannerAdsEnabled => _bannerAdsEnabled;
  bool get dualBoxBannersEnabled => _dualBoxBannersEnabled;

  /// Remote kill switch for team-race CREATION (TR-107, backend
  /// `featureFlags.teamRacesEnabled`). Defaults ON; only an explicit `false`
  /// from the backend hides the create-flow team toggle. Existing team races
  /// are unaffected by the switch (they render, run, and pay out normally).
  bool get teamRacesEnabled => _teamRacesEnabled;

  /// Server-controlled activation flow. This deliberately defaults to false:
  /// frozen/older backend payloads must continue through the v1 onboarding.
  bool get onboardingV2Enabled => _onboardingV2Enabled;

  /// Remotely-configurable step-sample bucket size in minutes (backend
  /// `featureFlags.stepSampleBucketMinutes`). One of {5, 10, 15, 30, 60};
  /// anything else — absent, null, out-of-set, or non-integer — resolves to 60
  /// (hourly), so a new build against an older backend behaves exactly like
  /// today. Persisted so a cold-start sync (which can run before the me-fetch
  /// completes) uses the last-known granularity instead of reverting to hourly.
  int get stepSampleBucketMinutes => _stepSampleBucketMinutes;

  static const Set<int> _allowedStepSampleBucketMinutes = {5, 10, 15, 30, 60};

  /// Resolves a raw `featureFlags.stepSampleBucketMinutes` value to an allowed
  /// bucket size, defaulting to 60 for any non-integer / out-of-set input.
  static int _resolveStepSampleBucketMinutes(dynamic raw) {
    int? value;
    if (raw is int) {
      value = raw;
    } else if (raw is num && raw == raw.toInt()) {
      value = raw.toInt();
    }
    if (value != null && _allowedStepSampleBucketMinutes.contains(value)) {
      return value;
    }
    return 60;
  }

  /// A race share token captured from a deep link that has not yet been
  /// consumed (joined). Persisted so it survives the sign-in/onboarding gap on
  /// a fresh install: the link is tapped, the app installs, the user onboards,
  /// and the token is drained once they land in the app. See DeepLinkService
  /// and MainShell's drain logic.
  String? get pendingShareToken => _pendingShareToken;

  /// A tournament share token captured from a `/t/<token>` deep link that has
  /// not yet been consumed (joined). Parallels [pendingShareToken] but rides a
  /// separate slot so a race link and a tournament link never clobber each
  /// other. Drained by MainShell once signed-in and onboarded.
  String? get pendingTournamentShareToken => _pendingTournamentShareToken;

  /// A referral code captured from a deep link / install referrer / clipboard
  /// that hasn't been attributed yet. Returns null once older than
  /// [_pendingReferralMaxAge]. Persisted immediately so it survives the fresh-
  /// install sign-in/onboarding gap, mirroring [pendingShareToken].
  String? get pendingReferralCode {
    final code = _pendingReferralCode;
    if (code == null || code.isEmpty) return null;
    final at = _pendingReferralCapturedAtMs;
    if (at != null) {
      final ageMs = DateTime.now().millisecondsSinceEpoch - at;
      if (ageMs > _pendingReferralMaxAge.inMilliseconds) return null;
    }
    return code;
  }

  /// One-shot referral code for the post-sign-in welcome (inviter greeting).
  /// Null once the welcome has been dismissed. See [_keyWelcomeReferralCode].
  String? get welcomeReferralCode => _welcomeReferralCode;

  bool get isSignedIn => _identityToken != null && _userIdentifier != null;
  bool get hasSessionToken =>
      _sessionToken != null && _sessionToken!.isNotEmpty;

  /// Loads persisted auth state. Returns true if a session exists.
  Future<bool> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    _identityToken = prefs.getString(_keyIdentityToken);
    _userIdentifier = prefs.getString(_keyUserIdentifier);
    _backendUserId = prefs.getString(_keyBackendUserId);
    _displayName = prefs.getString(_keyDisplayName);
    _profilePhotoUrl = prefs.getString(_keyProfilePhotoUrl);
    _profilePhotoPromptDismissedAt = prefs.getString(
      _keyProfilePhotoPromptDismissedAt,
    );
    _sessionToken = prefs.getString(_keySessionToken);
    _isAdmin = prefs.getBool(_keyIsAdmin) ?? false;
    _coins = prefs.getInt(_keyCoins) ?? 0;
    _heldCoins = prefs.getInt(_keyHeldCoins) ?? 0;
    _firstRaceOnboardingSeen =
        prefs.getBool(_keyFirstRaceOnboardingSeen) ?? false;
    _tutorialOnboardingSeen =
        prefs.getBool(_keyTutorialOnboardingSeen) ?? false;
    _hiddenFromLeaderboard = prefs.getBool(_keyHiddenFromLeaderboard) ?? false;
    _autoJoinFeaturedRaces = prefs.getBool(_keyAutoJoinFeaturedRaces) ?? false;
    _bannerAdsEnabled = prefs.getBool(_keyBannerAdsEnabled) ?? false;
    AdService.remoteBannersEnabled = _bannerAdsEnabled;
    _dualBoxBannersEnabled = prefs.getBool(_keyDualBoxBannersEnabled) ?? false;
    AdService.remoteDualBoxBannersEnabled = _dualBoxBannersEnabled;
    _teamRacesEnabled = prefs.getBool(_keyTeamRacesEnabled) ?? true;
    _onboardingV2Enabled = prefs.getBool(_keyOnboardingV2Enabled) ?? false;
    _stepSampleBucketMinutes = prefs.getInt(_keyStepSampleBucketMinutes) ?? 60;
    _pendingShareToken = prefs.getString(_keyPendingShareToken);
    _pendingTournamentShareToken = prefs.getString(
      _keyPendingTournamentShareToken,
    );
    final rawInviterRace = prefs.getString(_keyPendingInviterRace);
    if (rawInviterRace != null) {
      try {
        _pendingInviterRace = (jsonDecode(rawInviterRace) as Map).map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        );
      } catch (_) {
        _pendingInviterRace = null;
      }
    }
    _pendingReferralCode = prefs.getString(_keyPendingReferralCode);
    _pendingReferralCapturedAtMs = prefs.getInt(_keyPendingReferralCapturedAt);
    _welcomeReferralCode = prefs.getString(_keyWelcomeReferralCode);
    notifyListeners();
    return isSignedIn && hasSessionToken;
  }

  Future<bool> signInWithApple() async {
    // Clear a previous attempt's message so dismissing Apple's sheet never
    // resurfaces stale error copy.
    _lastErrorMessage = null;
    try {
      // Only the email scope: the backend assigns a generated display name and
      // never uses the Apple real name, so we don't request (or send) it.
      final credential = await _appleCredentialProvider();

      final identityToken = credential.identityToken;

      if (identityToken == null || identityToken.isEmpty) {
        throw const HttpException(
          'Apple sign-in did not provide an identity token.',
        );
      }

      final userIdentifier = credential.userIdentifier;

      if (userIdentifier == null || userIdentifier.isEmpty) {
        throw const HttpException(
          'Apple sign-in did not provide a user identifier.',
        );
      }

      final referralCode = pendingReferralCode;
      final response = await _backendApiService.provisionAppleUser(
        identityToken: identityToken,
        userIdentifier: userIdentifier,
        email: credential.email,
        referralCode: referralCode,
      );

      final backendUser = response['user'] as Map<String, dynamic>;
      // Attribution is recorded server-side in the new-user create branch (when
      // a code was present); clear the pending code so a later re-login can't
      // re-apply it, but stash a one-shot copy for the onboarding welcome.
      if (referralCode != null) {
        await setPendingReferralCode(null);
        await _setWelcomeReferralCode(referralCode);
      }

      _identityToken = identityToken;
      _userIdentifier = userIdentifier;
      _backendUserId = backendUser['id'] as String?;
      _sessionToken = response['sessionToken'] as String?;
      applyBackendUser(backendUser);
      _lastErrorMessage = null;

      await _persist();
      notifyListeners();
      return true;
    } on SignInWithAppleAuthorizationException catch (error) {
      _identityToken = null;
      _userIdentifier = null;
      _backendUserId = null;
      _lastErrorMessage = error.code == AuthorizationErrorCode.canceled
          ? null
          : 'Apple sign-in couldn’t be completed. Please try again.';
      notifyListeners();
      return false;
    } catch (_) {
      _identityToken = null;
      _userIdentifier = null;
      _backendUserId = null;
      _lastErrorMessage =
          'We couldn’t sign you in with Apple. Check your connection and try again.';
      notifyListeners();
      return false;
    }
  }

  /// Google Sign-In (Android, and iOS builds carrying GOOGLE_IOS_CLIENT_ID).
  /// Mirrors [signInWithApple]'s session-state effects and reuses every
  /// SharedPreferences key, so `restoreSession` and request auth work
  /// identically afterward. The Apple path is untouched.
  Future<bool> signInWithGoogle() async {
    _lastErrorMessage = null;
    try {
      final account = await _googleAccountProvider();
      if (account == null) {
        // User dismissed the picker — not an error worth surfacing loudly.
        _lastErrorMessage = null;
        notifyListeners();
        return false;
      }

      final auth = await account.authentication;
      final idToken = auth.idToken;

      if (idToken == null || idToken.isEmpty) {
        throw const HttpException(
          'Google sign-in did not provide an ID token.',
        );
      }

      final referralCode = pendingReferralCode;
      final response = await _backendApiService.provisionGoogleUser(
        idToken: idToken,
        email: account.email,
        name: account.displayName,
        referralCode: referralCode,
      );

      final backendUser = response['user'] as Map<String, dynamic>;
      if (referralCode != null) {
        await setPendingReferralCode(null);
      }

      _identityToken = idToken;
      // The Google stable id keeps isSignedIn (needs both tokens) true across
      // launches, matching the Apple userIdentifier contract.
      _userIdentifier = account.id;
      _backendUserId = backendUser['id'] as String?;
      _sessionToken = response['sessionToken'] as String?;
      applyBackendUser(backendUser);
      _lastErrorMessage = null;

      await _persist();
      notifyListeners();
      return true;
    } catch (_) {
      _identityToken = null;
      _userIdentifier = null;
      _backendUserId = null;
      _lastErrorMessage =
          'We couldn’t sign you in with Google. Check your connection and try again.';
      notifyListeners();
      return false;
    }
  }

  /// Reviewer bypass: signs in via the backend /auth/review endpoint using
  /// the email + password provided to Apple's review team. No Apple Sign-In
  /// involved. Mirrors the same session-state effects as signInWithApple.
  Future<bool> signInAsReviewer({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _backendApiService.signInAsReviewer(
        email: email,
        password: password,
      );

      final backendUser = response['user'] as Map<String, dynamic>;

      _identityToken = null;
      _userIdentifier = null;
      _backendUserId = backendUser['id'] as String?;
      _sessionToken = response['sessionToken'] as String?;
      applyBackendUser(backendUser);
      _lastErrorMessage = null;

      await _persist();
      notifyListeners();
      return true;
    } catch (e) {
      _lastErrorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> updateDisplayName(String? displayName) async {
    _displayName = displayName;
    final prefs = await SharedPreferences.getInstance();
    if (displayName != null) {
      await prefs.setString(_keyDisplayName, displayName);
    } else {
      await prefs.remove(_keyDisplayName);
    }
    notifyListeners();
  }

  Future<void> updateProfilePhotoUrl(String? profilePhotoUrl) async {
    _profilePhotoUrl = profilePhotoUrl;
    final prefs = await SharedPreferences.getInstance();
    if (profilePhotoUrl != null) {
      await prefs.setString(_keyProfilePhotoUrl, profilePhotoUrl);
    } else {
      await prefs.remove(_keyProfilePhotoUrl);
    }
    notifyListeners();
  }

  Future<void> updateProfilePhotoPromptDismissedAt(String? value) async {
    _profilePhotoPromptDismissedAt = value;
    final prefs = await SharedPreferences.getInstance();
    if (value != null) {
      await prefs.setString(_keyProfilePhotoPromptDismissedAt, value);
    } else {
      await prefs.remove(_keyProfilePhotoPromptDismissedAt);
    }
    notifyListeners();
  }

  /// Sets whether the user is hidden from the global leaderboard. Updates local
  /// state + persists + notifies optimistically so the toggle reflects the
  /// change immediately, then pushes to the backend. On failure (e.g. an older
  /// backend that 404s the endpoint) the local value is reverted so the UI
  /// doesn't drift from the server.
  Future<void> updateLeaderboardVisibility(bool hidden) async {
    final token = authToken;
    if (token == null || token.isEmpty) return;

    final previous = _hiddenFromLeaderboard;
    _hiddenFromLeaderboard = hidden;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHiddenFromLeaderboard, hidden);
    notifyListeners();

    try {
      final user = await _backendApiService.updateLeaderboardVisibility(
        identityToken: token,
        hidden: hidden,
      );
      applyBackendUser(user);
      await prefs.setBool(_keyHiddenFromLeaderboard, _hiddenFromLeaderboard);
      notifyListeners();
    } catch (_) {
      _hiddenFromLeaderboard = previous;
      await prefs.setBool(_keyHiddenFromLeaderboard, previous);
      notifyListeners();
    }
  }

  /// Sets whether the user auto-joins the daily/weekly featured challenges.
  /// Same optimistic-update-then-revert pattern as
  /// [updateLeaderboardVisibility]: local state flips immediately, the backend
  /// write follows, and a failure (e.g. an older backend that 404s the
  /// endpoint) reverts the local value.
  Future<void> updateFeaturedAutoJoin(bool enabled) async {
    final token = authToken;
    if (token == null || token.isEmpty) return;

    final previous = _autoJoinFeaturedRaces;
    _autoJoinFeaturedRaces = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoJoinFeaturedRaces, enabled);
    notifyListeners();

    try {
      final user = await _backendApiService.updateFeaturedAutoJoin(
        identityToken: token,
        enabled: enabled,
      );
      applyBackendUser(user);
      await prefs.setBool(_keyAutoJoinFeaturedRaces, _autoJoinFeaturedRaces);
      notifyListeners();
    } catch (_) {
      _autoJoinFeaturedRaces = previous;
      await prefs.setBool(_keyAutoJoinFeaturedRaces, previous);
      notifyListeners();
    }
  }

  void applyBackendUser(Map<String, dynamic> backendUser) {
    if (backendUser.containsKey('id')) {
      _backendUserId = backendUser['id'] as String?;
    }
    if (backendUser.containsKey('displayName')) {
      _displayName = backendUser['displayName'] as String?;
    }
    if (backendUser.containsKey('profilePhotoUrl')) {
      _profilePhotoUrl = backendUser['profilePhotoUrl'] as String?;
    }
    if (backendUser.containsKey('profilePhotoPromptDismissedAt')) {
      _profilePhotoPromptDismissedAt =
          backendUser['profilePhotoPromptDismissedAt'] as String?;
    }
    if (backendUser.containsKey('isAdmin')) {
      _isAdmin = backendUser['isAdmin'] as bool? ?? false;
    }
    if (backendUser.containsKey('coins')) {
      _coins = backendUser['coins'] as int? ?? 0;
    }
    if (backendUser.containsKey('heldCoins')) {
      _heldCoins = backendUser['heldCoins'] as int? ?? 0;
    }
    // Defensive: older backend payloads may not include this field. Only
    // override the local value when the key is present; default false.
    if (backendUser.containsKey('firstRaceOnboardingSeen')) {
      _firstRaceOnboardingSeen =
          backendUser['firstRaceOnboardingSeen'] as bool? ?? false;
    }
    // Defensive: older backends omit this; only override when present.
    if (backendUser.containsKey('tutorialOnboardingSeen')) {
      _tutorialOnboardingSeen =
          backendUser['tutorialOnboardingSeen'] as bool? ?? false;
    }
    // Defensive: older backends predate the leaderboard-visibility field. Only
    // override when the key is present; default false (visible) otherwise.
    if (backendUser.containsKey('hiddenFromLeaderboard')) {
      _hiddenFromLeaderboard =
          backendUser['hiddenFromLeaderboard'] as bool? ?? false;
    }
    // Defensive: older backends predate the featured auto-join field. Only
    // override when the key is present; default false (off) otherwise.
    if (backendUser.containsKey('autoJoinFeaturedRaces')) {
      _autoJoinFeaturedRaces =
          backendUser['autoJoinFeaturedRaces'] as bool? ?? false;
    }
    // Remote feature flags (additive `featureFlags` map on /auth/me). Only
    // override when present so an older backend never flips a cached value;
    // any absent/null flag reads as false (banners stay hidden).
    if (backendUser.containsKey('featureFlags')) {
      final flags = backendUser['featureFlags'];
      _bannerAdsEnabled = flags is Map && flags['bannerAdsEnabled'] == true;
      AdService.remoteBannersEnabled = _bannerAdsEnabled;
      _dualBoxBannersEnabled =
          flags is Map && flags['dualBoxBannersEnabled'] == true;
      AdService.remoteDualBoxBannersEnabled = _dualBoxBannersEnabled;
      // TR-107 team-race creation kill switch. Opposite default from banners:
      // the feature ships ON, so only an explicit false disables it — an older
      // backend that omits the key must not hide the toggle.
      _teamRacesEnabled = !(flags is Map && flags['teamRacesEnabled'] == false);
      // Step-sample granularity. Absent/null/out-of-set/non-integer -> 60
      // (hourly), so an older backend that omits the key reads as hourly.
      _stepSampleBucketMinutes = _resolveStepSampleBucketMinutes(
        flags is Map ? flags['stepSampleBucketMinutes'] : null,
      );
    }
    // Unlike team races, v2 is opt-in: within a payload that carries the
    // envelope, anything except the literal boolean true is the compatible v1
    // path. But the write is guarded on the envelope being PRESENT, like every
    // field above — an unconditional assignment let any payload lacking
    // `featureFlags` silently flip v2 off mid-session, mid-onboarding.
    if (backendUser.containsKey('featureFlags')) {
      final activationFlags = backendUser['featureFlags'];
      _onboardingV2Enabled =
          activationFlags is Map &&
          activationFlags['onboardingV2Enabled'] == true;
    }
    // Contract §12 names the envelope `appSettings`; accept it too so either
    // backend shape flips the switch. Only an explicit false disables.
    final appSettings = backendUser['appSettings'];
    if (appSettings is Map && appSettings.containsKey('teamRacesEnabled')) {
      _teamRacesEnabled = appSettings['teamRacesEnabled'] != false;
    }
  }

  Future<void> syncFromBackendUser(Map<String, dynamic> backendUser) async {
    applyBackendUser(backendUser);
    await _persist();
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    final token = authToken;
    if (token == null || token.isEmpty) {
      throw const ApiException('Not signed in.');
    }
    await _backendApiService.deleteAccount(identityToken: token);
    await signOut();
  }

  Future<void> signOut() async {
    // Clear the Google session so the next sign-in re-prompts the account
    // picker. Runs wherever Google Sign-In is available (Android always; iOS
    // when the client id was baked in) — harmless if the user signed in with
    // Apple, which keeps no client-side session.
    if (isGoogleSignInAvailable) {
      try {
        await _buildGoogleSignIn().signOut();
      } catch (_) {}
    }

    _identityToken = null;
    _userIdentifier = null;
    _backendUserId = null;
    _lastErrorMessage = null;
    _displayName = null;
    _profilePhotoUrl = null;
    _profilePhotoPromptDismissedAt = null;
    _sessionToken = null;
    _coins = 0;
    _heldCoins = 0;
    _isAdmin = false;
    _firstRaceOnboardingSeen = false;
    _tutorialOnboardingSeen = false;
    _hiddenFromLeaderboard = false;
    _autoJoinFeaturedRaces = false;
    _bannerAdsEnabled = false;
    AdService.remoteBannersEnabled = false;
    _dualBoxBannersEnabled = false;
    AdService.remoteDualBoxBannersEnabled = false;
    _onboardingV2Enabled = false;
    _stepSampleBucketMinutes = 60;
    _pendingShareToken = null;
    _pendingTournamentShareToken = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyIdentityToken);
    await prefs.remove(_keyUserIdentifier);
    await prefs.remove(_keyBackendUserId);
    await prefs.remove(_keyDisplayName);
    await prefs.remove(_keyProfilePhotoUrl);
    await prefs.remove(_keyProfilePhotoPromptDismissedAt);
    await prefs.remove(_keySessionToken);
    await prefs.remove(_keyIsAdmin);
    await prefs.remove(_keyHeldCoins);
    await prefs.remove(_keyFirstRaceOnboardingSeen);
    await prefs.remove(_keyTutorialOnboardingSeen);
    await prefs.remove(_keyHiddenFromLeaderboard);
    await prefs.remove(_keyAutoJoinFeaturedRaces);
    await prefs.remove(_keyBannerAdsEnabled);
    await prefs.remove(_keyDualBoxBannersEnabled);
    await prefs.remove(_keyOnboardingV2Enabled);
    await prefs.remove(_keyStepSampleBucketMinutes);
    await prefs.remove(_keyPendingShareToken);
    await prefs.remove(_keyPendingTournamentShareToken);
    _pendingInviterRace = null;
    await prefs.remove(_keyPendingInviterRace);
    // Health authorization is device-scoped, not auth-scoped, and lives under
    // its own key outside this `auth_*` set — so it survived sign-out and
    // account deletion, leaving a re-signup on the same device already
    // "authorized" and skipping the onboarding health gate entirely.
    await HealthService.clearPersistedAuthState();
    notifyListeners();
  }

  /// Records (or clears, when [token] is null) a race share token captured from
  /// a deep link, to be joined once the user is signed in and onboarded.
  /// Persisted immediately — like [updateSessionToken] — so it survives a fresh
  /// install's sign-in/onboarding gap. Independent of [_persist] (which only
  /// runs on sign-in), so a token captured on the sign-in screen isn't lost.
  Future<void> setPendingShareToken(String? token) async {
    _pendingShareToken = token;
    final prefs = await SharedPreferences.getInstance();
    if (token != null && token.isNotEmpty) {
      await prefs.setString(_keyPendingShareToken, token);
    } else {
      _pendingShareToken = null;
      await prefs.remove(_keyPendingShareToken);
    }
    notifyListeners();
  }

  /// Records (or clears) a tournament share token from a `/t/<token>` deep link,
  /// to be joined once signed-in and onboarded. Parallels [setPendingShareToken].
  Future<void> setPendingTournamentShareToken(String? token) async {
    _pendingTournamentShareToken = token;
    final prefs = await SharedPreferences.getInstance();
    if (token != null && token.isNotEmpty) {
      await prefs.setString(_keyPendingTournamentShareToken, token);
    } else {
      _pendingTournamentShareToken = null;
      await prefs.remove(_keyPendingTournamentShareToken);
    }
    notifyListeners();
  }

  /// The inviter's joinable race for a referred install (fetched from the
  /// referral preview by MainShell), pending the one-tap "race your friend"
  /// offer once onboarding completes. Keys: raceId, raceName, inviterName.
  /// Persisted so it survives an app restart mid-onboarding; cleared after the
  /// offer is shown (any outcome) and on sign-out.
  Map<String, String>? get pendingInviterRace => _pendingInviterRace;

  Future<void> setPendingInviterRace(Map<String, String>? race) async {
    _pendingInviterRace = (race == null || race['raceId'] == null)
        ? null
        : race;
    final prefs = await SharedPreferences.getInstance();
    if (_pendingInviterRace != null) {
      await prefs.setString(
        _keyPendingInviterRace,
        jsonEncode(_pendingInviterRace),
      );
    } else {
      await prefs.remove(_keyPendingInviterRace);
    }
    notifyListeners();
  }

  /// Records (or clears, when [code] is null) a referral code captured before
  /// sign-in, to be attributed once the user signs in. Persisted immediately
  /// (independent of [_persist], which only runs on sign-in) so it survives a
  /// fresh install's sign-in/onboarding gap, mirroring [setPendingShareToken].
  ///
  /// First-capture-wins: an already-persisted, non-expired code is NOT
  /// overwritten by a later capture (the first invite tapped wins), matching the
  /// backend's first-capture-wins attribution. Deliberately NOT cleared by
  /// [signOut] — a code may be captured before the referred account signs in.
  Future<void> setPendingReferralCode(String? code) async {
    final prefs = await SharedPreferences.getInstance();
    if (code == null || code.isEmpty) {
      _pendingReferralCode = null;
      _pendingReferralCapturedAtMs = null;
      await prefs.remove(_keyPendingReferralCode);
      await prefs.remove(_keyPendingReferralCapturedAt);
      notifyListeners();
      return;
    }
    // First-capture-wins: keep an existing, non-expired code.
    if (pendingReferralCode != null) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _pendingReferralCode = code;
    _pendingReferralCapturedAtMs = nowMs;
    await prefs.setString(_keyPendingReferralCode, code);
    await prefs.setInt(_keyPendingReferralCapturedAt, nowMs);
    notifyListeners();
  }

  /// Stash (or clear) the one-shot welcome code. Set at sign-in when the user
  /// was referred; cleared by the welcome step once shown.
  Future<void> _setWelcomeReferralCode(String? code) async {
    // Update the field + notify SYNCHRONOUSLY so a listener (MainShell) rebuilds
    // and advances the onboarding flow immediately; persistence follows.
    _welcomeReferralCode = (code != null && code.isNotEmpty) ? code : null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (_welcomeReferralCode != null) {
      await prefs.setString(_keyWelcomeReferralCode, _welcomeReferralCode!);
    } else {
      await prefs.remove(_keyWelcomeReferralCode);
    }
  }

  /// Clears the one-shot welcome code after the welcome has been shown.
  Future<void> clearWelcomeReferralCode() => _setWelcomeReferralCode(null);

  Future<void> updateSessionToken(String? token) async {
    _sessionToken = token;
    final prefs = await SharedPreferences.getInstance();
    if (token != null) {
      await prefs.setString(_keySessionToken, token);
    } else {
      await prefs.remove(_keySessionToken);
    }
    notifyListeners();
  }

  /// Marks the first-race onboarding step as seen locally (after the user
  /// joins a race or skips). The backend is the source of truth; this keeps
  /// the in-memory + persisted value in sync so the step won't re-show this
  /// session.
  Future<void> markFirstRaceOnboardingSeenLocally() async {
    _firstRaceOnboardingSeen = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyFirstRaceOnboardingSeen, true);
    notifyListeners();
  }

  /// Marks the tutorial onboarding step as seen, both locally (so the step
  /// won't re-show this session) and on the backend (source of truth). Used by
  /// the skip path and after starting the tutorial. Backend write is
  /// best-effort: the local flag still advances onboarding if the network call
  /// fails, and the backend remains authoritative on the next sync.
  Future<void> markTutorialOnboardingSeen() async {
    _tutorialOnboardingSeen = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyTutorialOnboardingSeen, true);
    notifyListeners();
    final token = authToken;
    if (token != null && token.isNotEmpty) {
      try {
        await _backendApiService.markTutorialOnboardingSeen(
          identityToken: token,
        );
      } catch (_) {
        // Best-effort; local flag already advanced onboarding.
      }
    }
  }

  /// Claims the one-time 100-coin tutorial-completion reward. The backend is
  /// authoritative and idempotent — it only grants once per account ever, so
  /// replays / reinstalls return granted:false. On a grant, updates the local
  /// coin balance. Also marks the onboarding step seen locally (completing
  /// implies seen). Returns whether coins were granted this call.
  Future<bool> claimTutorialReward() async {
    final token = authToken;
    if (token == null || token.isEmpty) return false;
    // Completing the tutorial dismisses the onboarding step regardless of
    // whether coins were granted this time.
    _tutorialOnboardingSeen = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyTutorialOnboardingSeen, true);
    try {
      final result = await _backendApiService.claimTutorialReward(
        identityToken: token,
      );
      final granted = result['granted'] as bool? ?? false;
      final coins = result['coins'] as int?;
      if (coins != null) {
        await updateCoins(coins);
      } else {
        notifyListeners();
      }
      return granted;
    } catch (_) {
      notifyListeners();
      return false;
    }
  }

  Future<void> updateCoins(int coins) async {
    _coins = coins;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyCoins, coins);
    notifyListeners();
  }

  Future<void> updateHeldCoins(int heldCoins) async {
    _heldCoins = heldCoins;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyHeldCoins, heldCoins);
    notifyListeners();
  }

  Future<void> updateAdminAccess(bool isAdmin) async {
    _isAdmin = isAdmin;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsAdmin, isAdmin);
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (_identityToken != null) {
      await prefs.setString(_keyIdentityToken, _identityToken!);
    }
    if (_userIdentifier != null) {
      await prefs.setString(_keyUserIdentifier, _userIdentifier!);
    }
    if (_backendUserId != null) {
      await prefs.setString(_keyBackendUserId, _backendUserId!);
    }
    if (_displayName != null) {
      await prefs.setString(_keyDisplayName, _displayName!);
    }
    if (_profilePhotoUrl != null) {
      await prefs.setString(_keyProfilePhotoUrl, _profilePhotoUrl!);
    }
    if (_profilePhotoPromptDismissedAt != null) {
      await prefs.setString(
        _keyProfilePhotoPromptDismissedAt,
        _profilePhotoPromptDismissedAt!,
      );
    }
    if (_sessionToken != null) {
      await prefs.setString(_keySessionToken, _sessionToken!);
    }
    await prefs.setBool(_keyIsAdmin, _isAdmin);
    await prefs.setInt(_keyCoins, _coins);
    await prefs.setInt(_keyHeldCoins, _heldCoins);
    await prefs.setBool(_keyFirstRaceOnboardingSeen, _firstRaceOnboardingSeen);
    await prefs.setBool(_keyTutorialOnboardingSeen, _tutorialOnboardingSeen);
    await prefs.setBool(_keyHiddenFromLeaderboard, _hiddenFromLeaderboard);
    await prefs.setBool(_keyBannerAdsEnabled, _bannerAdsEnabled);
    await prefs.setBool(_keyDualBoxBannersEnabled, _dualBoxBannersEnabled);
    await prefs.setBool(_keyTeamRacesEnabled, _teamRacesEnabled);
    await prefs.setBool(_keyOnboardingV2Enabled, _onboardingV2Enabled);
    await prefs.setInt(_keyStepSampleBucketMinutes, _stepSampleBucketMinutes);
  }
}
