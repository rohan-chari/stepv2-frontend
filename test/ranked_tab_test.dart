import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/ranked_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/home_course_track.dart'
    show AnimatedCapybaraWithAccessories;

enum _Mode { ranked, unranked, notFound }

const _kTiers = [
  {'key': 'BRONZE', 'label': 'Bronze', 'floor': 0, 'reward': 100},
  {'key': 'SILVER', 'label': 'Silver', 'floor': 200, 'reward': 250},
  {'key': 'GOLD', 'label': 'Gold', 'floor': 550, 'reward': 600},
  {'key': 'DIAMOND', 'label': 'Diamond', 'floor': 1400, 'reward': 1500},
];

class _FakeRankedApi extends BackendApiService {
  _FakeRankedApi(this.mode);
  final _Mode mode;

  @override
  Future<Map<String, dynamic>> fetchRanked({
    required String identityToken,
  }) async {
    if (mode == _Mode.notFound) {
      throw const ApiException('Not found', statusCode: 404);
    }

    final season = {
      'index': 3,
      'endsAt': DateTime.now().add(const Duration(days: 10)).toIso8601String(),
      'status': 'active',
    };

    if (mode == _Mode.unranked) {
      return {
        'season': season,
        'currentUser': {
          'rank': null,
          'points': 0,
          'tier': null,
          'division': null,
          'ranked': false,
        },
        'ladder': [
          {
            'rank': 1,
            'userId': 'other',
            'displayName': 'AceWalker',
            'points': 1500,
            'tier': 'DIAMOND',
            'division': null,
            'equippedAccessories': [
              {'slot': 'HEAD', 'assetKey': 'top-hat'},
            ],
          },
        ],
        'tiers': _kTiers,
      };
    }

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
          'equippedAccessories': [
            {'slot': 'HEAD', 'assetKey': 'top-hat'},
          ],
        },
        {
          'rank': 2,
          'userId': 'user-1',
          'displayName': 'Trail Walker',
          'points': 700,
          'tier': 'GOLD',
          'division': 3,
          'equippedAccessories': [
            {'slot': 'BODY', 'assetKey': 'hoodie'},
          ],
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

  testWidgets('shows the tier hero and ladder when the user is ranked', (
    tester,
  ) async {
    final auth = await _createAuthService();
    await tester.pumpWidget(_build(auth, _FakeRankedApi(_Mode.ranked)));
    await tester.pump();

    expect(find.text('RANKED'), findsOneWidget);
    // Hero badge is uppercased; ladder badges are not.
    expect(find.text('GOLD III'), findsOneWidget);
    expect(find.text('2'), findsAtLeastNWidgets(1)); // hero GLOBAL RANK stat
    expect(find.text('RANKED POINTS'), findsOneWidget);
    expect(find.text('GLOBAL RANK'), findsOneWidget);
    expect(find.text('@AceWalker'), findsOneWidget);
    expect(find.text('@Trail Walker'), findsOneWidget);
    // Reward for the current tier is surfaced in the hero.
    expect(find.text('Finish Gold → 600 coins'), findsOneWidget);
  });

  testWidgets('shows the not-ranked hero when the user has no score', (
    tester,
  ) async {
    final auth = await _createAuthService();
    await tester.pumpWidget(_build(auth, _FakeRankedApi(_Mode.unranked)));
    await tester.pump();

    expect(find.text('Not ranked yet'), findsOneWidget);
    // The ladder still renders other players.
    expect(find.text('@AceWalker'), findsOneWidget);
  });

  testWidgets('podium capybaras wear equipped accessories', (tester) async {
    final auth = await _createAuthService();
    await tester.pumpWidget(_build(auth, _FakeRankedApi(_Mode.ranked)));
    await tester.pump();

    final capybaras = tester
        .widgetList<AnimatedCapybaraWithAccessories>(
          find.byType(AnimatedCapybaraWithAccessories),
        )
        .toList();
    expect(capybaras, hasLength(2));
    expect(
      capybaras.map((capybara) => capybara.accessories.single['assetKey']),
      containsAll(['top-hat', 'hoodie']),
    );
  });

  testWidgets(
    'degrades to "coming soon" when the backend has no /ranked (404)',
    (tester) async {
      final auth = await _createAuthService();
      await tester.pumpWidget(_build(auth, _FakeRankedApi(_Mode.notFound)));
      await tester.pump();

      expect(find.text('Ranked is coming soon'), findsOneWidget);
    },
  );
}
