import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'backend_api_service.dart';

bool isAuthenticationFailure(Object error) {
  return error is ApiException && error.statusCode == 401;
}

class AuthService {
  AuthService({BackendApiService? backendApiService})
    : _backendApiService = backendApiService ?? BackendApiService();

  static const _keyIdentityToken = 'auth_identity_token';
  static const _keyUserIdentifier = 'auth_user_identifier';
  static const _keyBackendUserId = 'auth_backend_user_id';
  static const _keyStepGoal = 'auth_step_goal';
  static const _keyDisplayName = 'auth_display_name';
  static const _keySessionToken = 'auth_session_token';
  static const _keyIsAdmin = 'auth_is_admin';
  static const _keyCoins = 'auth_coins';

  final BackendApiService _backendApiService;
  String? _identityToken;
  String? _userIdentifier;
  String? _backendUserId;
  String? _lastErrorMessage;
  int? _stepGoal;
  String? _displayName;
  String? _sessionToken;
  bool _isAdmin = false;
  int _coins = 0;

  String? get identityToken => _identityToken;
  String? get sessionToken => _sessionToken;
  String? get authToken => _sessionToken ?? _identityToken;
  String? get userId => _backendUserId;
  String? get lastErrorMessage => _lastErrorMessage;
  int? get stepGoal => _stepGoal;
  String? get displayName => _displayName;
  bool get isAdmin => _isAdmin;
  int get coins => _coins;
  bool get isSignedIn => _identityToken != null && _userIdentifier != null;
  bool get hasSessionToken =>
      _sessionToken != null && _sessionToken!.isNotEmpty;

  /// Loads persisted auth state. Returns true if a session exists.
  Future<bool> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    _identityToken = prefs.getString(_keyIdentityToken);
    _userIdentifier = prefs.getString(_keyUserIdentifier);
    _backendUserId = prefs.getString(_keyBackendUserId);
    _stepGoal = prefs.getInt(_keyStepGoal);
    _displayName = prefs.getString(_keyDisplayName);
    _sessionToken = prefs.getString(_keySessionToken);
    _isAdmin = prefs.getBool(_keyIsAdmin) ?? false;
    _coins = prefs.getInt(_keyCoins) ?? 0;
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

      final response = await _backendApiService.provisionAppleUser(
        identityToken: identityToken,
        userIdentifier: userIdentifier,
        email: credential.email,
        name: _buildDisplayName(credential),
      );

      final backendUser = response['user'] as Map<String, dynamic>;

      _identityToken = identityToken;
      _userIdentifier = userIdentifier;
      _backendUserId = backendUser['id'] as String?;
      _displayName = backendUser['displayName'] as String?;
      _sessionToken = response['sessionToken'] as String?;
      _isAdmin = backendUser['isAdmin'] as bool? ?? false;
      _coins = backendUser['coins'] as int? ?? 0;
      _lastErrorMessage = null;

      await _persist();
      return true;
    } catch (e) {
      _identityToken = null;
      _userIdentifier = null;
      _backendUserId = null;
      _lastErrorMessage = e.toString();
      return false;
    }
  }

  Future<void> updateStepGoal(int? stepGoal) async {
    _stepGoal = stepGoal;
    final prefs = await SharedPreferences.getInstance();
    if (stepGoal != null) {
      await prefs.setInt(_keyStepGoal, stepGoal);
    } else {
      await prefs.remove(_keyStepGoal);
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
  }

  Future<void> signOut() async {
    _identityToken = null;
    _userIdentifier = null;
    _backendUserId = null;
    _lastErrorMessage = null;
    _stepGoal = null;
    _displayName = null;
    _sessionToken = null;
    _coins = 0;
    _isAdmin = false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyIdentityToken);
    await prefs.remove(_keyUserIdentifier);
    await prefs.remove(_keyBackendUserId);
    await prefs.remove(_keyStepGoal);
    await prefs.remove(_keyDisplayName);
    await prefs.remove(_keySessionToken);
    await prefs.remove(_keyIsAdmin);
  }

  Future<void> updateSessionToken(String? token) async {
    _sessionToken = token;
    final prefs = await SharedPreferences.getInstance();
    if (token != null) {
      await prefs.setString(_keySessionToken, token);
    } else {
      await prefs.remove(_keySessionToken);
    }
  }

  Future<void> updateCoins(int coins) async {
    _coins = coins;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyCoins, coins);
  }

  Future<void> updateAdminAccess(bool isAdmin) async {
    _isAdmin = isAdmin;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsAdmin, isAdmin);
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
    if (_sessionToken != null) {
      await prefs.setString(_keySessionToken, _sessionToken!);
    }
    await prefs.setBool(_keyIsAdmin, _isAdmin);
    await prefs.setInt(_keyCoins, _coins);
  }

  String? _buildDisplayName(AuthorizationCredentialAppleID credential) {
    final given = credential.givenName ?? '';
    final family = credential.familyName ?? '';
    final full = '$given $family'.trim();

    return full.isEmpty ? null : full;
  }
}
