import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/ranked_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

const _kTiers = [
  {'key': 'BRONZE', 'label': 'Bronze', 'floor': 0, 'reward': 100},
  {'key': 'SILVER', 'label': 'Silver', 'floor': 200, 'reward': 250},
  {'key': 'GOLD', 'label': 'Gold', 'floor': 550, 'reward': 600},
  {'key': 'DIAMOND', 'label': 'Diamond', 'floor': 1400, 'reward': 1500},
];

/// Returns a ranked payload with a season ending ~10 days out, plus a
/// `durationDays` the (removed) "DAY x/30" counter used to read — so the test
/// proves the counter is gone even when the backend still sends durationDays.
class _FakeRankedApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchRanked({
    required String identityToken,
  }) async {
    final season = {
      'index': 3,
      'endsAt': DateTime.now().add(const Duration(days: 10)).toIso8601String(),
      'durationDays': 30,
      'status': 'active',
    };

    return {
      'season': season,
      'currentUser': {
        'rank': 2,
        'points': 700,
        'tier': 'GOLD',
        'division': 3,
        'ranked': true,
      },
      'ladder': [
        {
          'rank': 1,
          'userId': 'other',
          'displayName': 'AceWalker',
          'points': 1500,
          'tier': 'DIAMOND',
          'division': null,
        },
      ],
      'tiers': _kTiers,
    };
  }
}

Future<AuthService> _createAuthService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

Widget _build(AuthService auth, BackendApiService api) {
  return MaterialApp(
    home: Scaffold(
      body: RankedTab(authService: auth, backendApiService: api),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'season countdown shows "X days left" once and no "DAY x/30" counter',
    (tester) async {
      final auth = await _createAuthService();
      await tester.pumpWidget(_build(auth, _FakeRankedApi()));
      await tester.pump();

      // The "DAY x/30"-style elapsed-day counter is removed entirely.
      expect(find.textContaining('DAY '), findsNothing);
      expect(find.textContaining(RegExp(r'\d+/\d+')), findsNothing);

      // "X days left" is the only countdown text — shown exactly once.
      expect(find.text('10 days left'), findsOneWidget);
    },
  );
}
