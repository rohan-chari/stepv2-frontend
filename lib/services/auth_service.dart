import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'backend_api_service.dart';

/// The Firebase project's **Web** OAuth client id, passed to GoogleSignIn as
/// `serverClientId` so the returned ID token's `aud` matches what the backend
/// verifies (`GOOGLE_AUTH_CLIENT_ID`). Not a secret. Same value for the prod
/// and `.staging` apps. See ANDROID.md §D.
const String kGoogleServerClientId =
    '784756906133-8b5umuhi93u40lg0pf11rf1grksj44cg.apps.googleusercontent.com';

bool isAuthenticationFailure(Object error) {
  return error is ApiException && error.statusCode == 401;
}

class AuthService extends ChangeNotifier {
  AuthService({BackendApiService? backendApiService})
    : _backendApiService = backendApiService ?? BackendApiService();

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
  static const _keyPendingShareToken = 'auth_pending_share_token';
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
  String? _pendingShareToken;
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

  /// A race share token captured from a deep link that has not yet been
  /// consumed (joined). Persisted so it survives the sign-in/onboarding gap on
  /// a fresh install: the link is tapped, the app installs, the user onboards,
  /// and the token is drained once they land in the app. See DeepLinkService
  /// and MainShell's drain logic.
  String? get pendingShareToken => _pendingShareToken;

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
    _pendingShareToken = prefs.getString(_keyPendingShareToken);
    _pendingReferralCode = prefs.getString(_keyPendingReferralCode);
    _pendingReferralCapturedAtMs = prefs.getInt(_keyPendingReferralCapturedAt);
    _welcomeReferralCode = prefs.getString(_keyWelcomeReferralCode);
    notifyListeners();
    return isSignedIn && hasSessionToken;
  }

  Future<bool> signInWithApple() async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

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
        name: _buildDisplayName(credential),
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
    } catch (e) {
      _identityToken = null;
      _userIdentifier = null;
      _backendUserId = null;
      _lastErrorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Google Sign-In (Android). Mirrors [signInWithApple]'s session-state
  /// effects and reuses every SharedPreferences key, so `restoreSession` and
  /// request auth work identically afterward. The Apple path is untouched.
  Future<bool> signInWithGoogle() async {
    try {
      final googleSignIn = GoogleSignIn(
        serverClientId: kGoogleServerClientId,
        scopes: const ['email'],
      );

      final account = await googleSignIn.signIn();
      if (account == null) {
        // User dismissed the picker — not an error worth surfacing loudly.
        _lastErrorMessage = 'Google sign-in was cancelled.';
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
    } catch (e) {
      _identityToken = null;
      _userIdentifier = null;
      _backendUserId = null;
      _lastErrorMessage = e.toString();
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
    // Clear the Google session on Android so the next sign-in re-prompts the
    // account picker. No-op / harmless on iOS (Apple has no client-side session).
    if (Platform.isAndroid) {
      try {
        await GoogleSignIn().signOut();
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
    _pendingShareToken = null;

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
    await prefs.remove(_keyPendingShareToken);
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
  }

  String? _buildDisplayName(AuthorizationCredentialAppleID credential) {
    final given = credential.givenName ?? '';
    final family = credential.familyName ?? '';
    final full = '$given $family'.trim();

    return full.isEmpty ? null : full;
  }
}
