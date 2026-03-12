import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'backend_api_service.dart';

class AuthService {
  AuthService({BackendApiService? backendApiService})
    : _backendApiService = backendApiService ?? BackendApiService();

  static const _keyIdentityToken = 'auth_identity_token';
  static const _keyUserIdentifier = 'auth_user_identifier';
  static const _keyBackendUserId = 'auth_backend_user_id';
  static const _keyStepGoal = 'auth_step_goal';
  static const _keyDisplayName = 'auth_display_name';

  final BackendApiService _backendApiService;
  String? _identityToken;
  String? _userIdentifier;
  String? _backendUserId;
  String? _lastErrorMessage;
  int? _stepGoal;
  String? _displayName;

  String? get identityToken => _identityToken;
  String? get userId => _backendUserId;
  String? get lastErrorMessage => _lastErrorMessage;
  int? get stepGoal => _stepGoal;
  String? get displayName => _displayName;
  bool get isSignedIn => _identityToken != null && _userIdentifier != null;

  /// Loads persisted auth state. Returns true if a session exists.
  Future<bool> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    _identityToken = prefs.getString(_keyIdentityToken);
    _userIdentifier = prefs.getString(_keyUserIdentifier);
    _backendUserId = prefs.getString(_keyBackendUserId);
    _stepGoal = prefs.getInt(_keyStepGoal);
    _displayName = prefs.getString(_keyDisplayName);
    return isSignedIn;
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

      final backendUser = await _backendApiService.provisionAppleUser(
        identityToken: identityToken,
        userIdentifier: userIdentifier,
        email: credential.email,
        name: _buildDisplayName(credential),
      );

      _identityToken = identityToken;
      _userIdentifier = userIdentifier;
      _backendUserId = backendUser['id'] as String?;
      _displayName = backendUser['displayName'] as String?;
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

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyIdentityToken);
    await prefs.remove(_keyUserIdentifier);
    await prefs.remove(_keyBackendUserId);
    await prefs.remove(_keyStepGoal);
    await prefs.remove(_keyDisplayName);
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
  }

  String? _buildDisplayName(AuthorizationCredentialAppleID credential) {
    final given = credential.givenName ?? '';
    final family = credential.familyName ?? '';
    final full = '$given $family'.trim();

    return full.isEmpty ? null : full;
  }
}
