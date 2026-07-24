import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/public_races_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

/// Item 2 — the auto-join toggle is now visibly on the Public Races page (not
/// only behind the gear), bound to the same authService state/handler.
class _FakeApi extends BackendApiService {
  final List<bool> autoJoinCalls = [];

  @override
  Future<List<Map<String, dynamic>>> fetchPublicRaces({
    required String identityToken,
  }) async => const [];

  @override
  Future<Map<String, dynamic>> updateFeaturedAutoJoin({
    required String identityToken,
    required bool enabled,
  }) async {
    autoJoinCalls.add(enabled);
    return {'autoJoinFeaturedRaces': enabled};
  }
}

Future<AuthService> _auth(BackendApiService api) async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Walker',
    'auth_coins': 500,
    'auth_held_coins': 0,
  });
  final service = AuthService(backendApiService: api);
  await service.restoreSession();
  return service;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('visible auto-join toggle renders and flips the setting', (
    tester,
  ) async {
    final api = _FakeApi();
    final auth = await _auth(api);
    expect(auth.autoJoinFeaturedRaces, isFalse);

    await tester.pumpWidget(
      MaterialApp(
        home: PublicRacesScreen(authService: auth, backendApiService: api),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // The labeled card is visible on the page (not hidden behind the gear).
    expect(find.text('Auto-join daily & weekly races'), findsWidgets);
    expect(find.byType(CupertinoSwitch), findsWidgets);

    await tester.tap(find.byType(CupertinoSwitch).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Same handler the gear sheet uses fired through to the backend.
    expect(api.autoJoinCalls, contains(true));
    expect(auth.autoJoinFeaturedRaces, isTrue);
  });
}
