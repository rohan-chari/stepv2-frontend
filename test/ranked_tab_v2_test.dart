import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/ranked_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

enum _Mode { inCohort, noCohort, promotedLastWeek, v2Missing }

const _kTiersV2 = [
  {'key': 'BRONZE', 'label': 'Bronze', 'promotionBonus': 0},
  {'key': 'SILVER', 'label': 'Silver', 'promotionBonus': 100},
  {'key': 'GOLD', 'label': 'Gold', 'promotionBonus': 200},
  {'key': 'PLATINUM', 'label': 'Platinum', 'promotionBonus': 350},
  {'key': 'DIAMOND', 'label': 'Diamond', 'promotionBonus': 500},
  {'key': 'LEGEND', 'label': 'Legend', 'promotionBonus': 1000},
];

Map<String, dynamic> _week() => {
      'index': 5,
      'startsOn': DateTime.now()
          .subtract(const Duration(days: 2))
          .toIso8601String(),
      'endsOn': DateTime.now().add(const Duration(days: 5)).toIso8601String(),
      'settlesAt':
          DateTime.now().add(const Duration(days: 5, hours: 18)).toIso8601String(),
      'status': 'ACTIVE',
    };

Map<String, dynamic> _memberRow(
  int rank,
  String userId,
  String name,
  int steps,
  String zone,
) =>
    {
      'rank': rank,
      'userId': userId,
      'displayName': name,
      'profilePhotoUrl': null,
      'equippedAccessories': const [],
      'weeklySteps': steps,
      'zone': zone,
    };

class _FakeRankedV2Api extends BackendApiService {
  _FakeRankedV2Api(this.mode);
  final _Mode mode;

  @override
  Future<Map<String, dynamic>> fetchRankedV2({
    required String identityToken,
  }) async {
    if (mode == _Mode.v2Missing) {
      throw const ApiException('Not found', statusCode: 404);
    }

    if (mode == _Mode.noCohort) {
      return {
        'week': _week(),
        'currentUser': {
          'ranked': false,
          'tier': 'SILVER',
          'rank': null,
          'weeklySteps': 0,
          'zone': null,
        },
        'cohort': null,
        'tiers': _kTiersV2,
        'lastWeek': null,
      };
    }

    return {
      'week': _week(),
      'currentUser': {
        'ranked': true,
        'tier': 'GOLD',
        'rank': 2,
        'weeklySteps': 41250,
        'zone': 'PROMOTION',
        'projectedCoins': 225,
      },
      'cohort': {
        'id': 'cohort-1',
        'tier': 'GOLD',
        'size': 4,
        'promoteCount': 1,
        'demoteCount': 1,
        'members': [
          _memberRow(1, 'other-1', 'AceWalker', 52000, 'PROMOTION'),
          _memberRow(2, 'user-1', 'Trail Walker', 41250, 'HOLD'),
          _memberRow(3, 'other-2', 'SlowPoke', 9000, 'HOLD'),
          _memberRow(4, 'other-3', 'CouchFan', 200, 'DEMOTION'),
        ],
        'rewards': [
          {'rank': 1, 'coins': 300},
          {'rank': 2, 'coins': 225},
          {'rank': 3, 'coins': 180},
          {'rank': 4, 'coins': 0},
        ],
      },
      'tiers': _kTiersV2,
      'lastWeek': mode == _Mode.promotedLastWeek
          ? {
              'weekIndex': 4,
              'finalRank': 3,
              'tier': 'SILVER',
              'resultTier': 'GOLD',
              'outcome': 'PROMOTE',
              'rewardCoins': 150,
              'promotionCoins': 200,
            }
          : null,
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRanked({
    required String identityToken,
  }) async {
    // The legacy fallback used when /ranked/v2 is missing.
    if (mode != _Mode.v2Missing) {
      throw StateError('legacy /ranked should not be called when v2 is live');
    }
    return {
      'season': {
        'index': 3,
        'endsAt':
            DateTime.now().add(const Duration(days: 10)).toIso8601String(),
        'status': 'active',
      },
      'currentUser': {
        'rank': 2,
        'points': 700,
        'tier': 'GOLD',
        'division': 3,
        'ranked': true,
      },
      'ladder': const [],
      'tiers': const [
        {'key': 'GOLD', 'label': 'Gold', 'floor': 550, 'reward': 0},
      ],
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

  testWidgets('shows the cohort hero, zones, and rewards when in a cohort', (
    tester,
  ) async {
    final auth = await _createAuthService();
    await tester.pumpWidget(_build(auth, _FakeRankedV2Api(_Mode.inCohort)));
    await tester.pump();

    expect(find.text('RANKED'), findsOneWidget);
    expect(find.text('GOLD'), findsAtLeastNWidgets(1));
    expect(find.text('STEPS THIS WEEK'), findsOneWidget);
    expect(find.text('41,250'), findsAtLeastNWidgets(1));
    expect(find.text('#2 of 4'), findsOneWidget);
    expect(find.text('COHORT RANK'), findsOneWidget);

    // Zone dividers around the cohort list.
    expect(find.text('PROMOTION ZONE · TOP 1'), findsOneWidget);
    expect(find.text('DEMOTION ZONE · BOTTOM 1'), findsOneWidget);

    // Cohort members render with their weekly steps.
    expect(find.text('@AceWalker'), findsOneWidget);
    expect(find.text('@CouchFan'), findsOneWidget);
    expect(find.text('52,000'), findsOneWidget);

    // Projected payout comes from the server reward table.
    expect(find.text('On pace for → 225 coins'), findsOneWidget);

    // The six-tier ladder strip is server-driven.
    expect(find.text('LEGEND'), findsOneWidget);
    expect(find.text('PLATINUM'), findsOneWidget);
  });

  testWidgets('shows the join hint when the user has no cohort yet', (
    tester,
  ) async {
    final auth = await _createAuthService();
    await tester.pumpWidget(_build(auth, _FakeRankedV2Api(_Mode.noCohort)));
    await tester.pump();

    expect(find.text('Your cohort is waiting'), findsOneWidget);
    // Home tier still shown (Silver), sourced from the server.
    expect(find.text('SILVER'), findsAtLeastNWidgets(1));
  });

  testWidgets('surfaces last week’s promotion with the combined coin total', (
    tester,
  ) async {
    final auth = await _createAuthService();
    await tester
        .pumpWidget(_build(auth, _FakeRankedV2Api(_Mode.promotedLastWeek)));
    await tester.pump();

    expect(find.text('Last week: Promoted to Gold!'), findsOneWidget);
    expect(find.text('+350'), findsOneWidget); // 150 reward + 200 bonus
  });

  testWidgets('falls back to the legacy season ladder when /ranked/v2 404s', (
    tester,
  ) async {
    final auth = await _createAuthService();
    await tester.pumpWidget(_build(auth, _FakeRankedV2Api(_Mode.v2Missing)));
    await tester.pump();
    await tester.pump();

    // Legacy hero renders from the old endpoint's data.
    expect(find.text('GOLD III'), findsOneWidget);
    expect(find.text('RANKED POINTS'), findsOneWidget);
  });
}
