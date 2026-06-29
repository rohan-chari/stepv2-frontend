import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/ranked_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

enum _Mode { inCohort, noCohort, v2Missing }

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
      'startsOn':
          DateTime.now().subtract(const Duration(days: 2)).toIso8601String(),
      'endsOn': DateTime.now().add(const Duration(days: 5)).toIso8601String(),
      'settlesAt': DateTime.now()
          .add(const Duration(days: 5, hours: 18))
          .toIso8601String(),
      'status': 'ACTIVE',
    };

Map<String, dynamic> _row(
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

// A coherent 8-walker Silver cohort: top 2 promote, bottom 2 drop. The user
// (user-1) sits 4th — safely holding, chasing the move-up line.
List<Map<String, dynamic>> _members() => [
      _row(1, 'a', 'AceWalker', 70000, 'PROMOTION'),
      _row(2, 'b', 'Runner-Up', 60000, 'PROMOTION'),
      _row(3, 'c', 'OnTheBubble', 52000, 'HOLD'),
      _row(4, 'user-1', 'Trail Walker', 41250, 'HOLD'),
      _row(5, 'e', 'MidPack', 30000, 'HOLD'),
      _row(6, 'f', 'Straggler', 20000, 'HOLD'),
      _row(7, 'g', 'SlowPoke', 9000, 'DEMOTION'),
      _row(8, 'h', 'CouchFan', 200, 'DEMOTION'),
    ];

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
        'tier': 'SILVER',
        'rank': 4,
        'weeklySteps': 41250,
        'zone': 'HOLD',
        'projectedCoins': 40,
      },
      'cohort': {
        'id': 'cohort-1',
        'tier': 'SILVER',
        'size': 8,
        'promoteCount': 2,
        'demoteCount': 2,
        'members': _members(),
        'rewards': [
          {'rank': 1, 'coins': 250},
          {'rank': 2, 'coins': 190},
          {'rank': 3, 'coins': 100},
          {'rank': 4, 'coins': 50},
        ],
      },
      'tiers': _kTiersV2,
      'lastWeek': null,
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRanked({
    required String identityToken,
  }) async {
    if (mode != _Mode.v2Missing) {
      throw StateError('legacy /ranked should not be called when v2 is live');
    }
    return {
      'season': {
        'index': 3,
        'endsAt': DateTime.now().add(const Duration(days: 10)).toIso8601String(),
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

  testWidgets('hero states a plain-language status and the path to move up', (
    tester,
  ) async {
    final auth = await _createAuthService();
    await tester.pumpWidget(_build(auth, _FakeRankedV2Api(_Mode.inCohort)));
    await tester.pump();

    // Status headline + the actionable caption (chasing the move-up line).
    expect(find.text('HOLDING'), findsOneWidget);
    expect(
      find.textContaining('to pass 2nd and reach Gold'),
      findsOneWidget,
    );
    // Footer line summarises position + stakes, with the on-pace coins.
    expect(find.textContaining('4th of 8'), findsOneWidget);
    expect(find.text('+40'), findsOneWidget);
  });

  testWidgets('group is collapsed to what matters, with the cutlines labelled', (
    tester,
  ) async {
    final auth = await _createAuthService();
    await tester.pumpWidget(_build(auth, _FakeRankedV2Api(_Mode.inCohort)));
    await tester.pump();

    expect(find.text('Your group'), findsOneWidget);
    expect(find.text('8 walkers'), findsOneWidget);
    expect(find.text('Top 2 move up · bottom 2 drop'), findsOneWidget);
    // Plain-language cutline (the move-up boundary sits within the top six).
    expect(find.text('Top 2 move up to Gold'), findsOneWidget);
    // The drop boundary is near the bottom — not shown until expanded.
    expect(find.text('Bottom 2 drop to Bronze'), findsNothing);
    // Progressive disclosure: full list is behind a toggle.
    expect(find.text('See full group (8)'), findsOneWidget);
    // Top six + the user are in the focused window.
    expect(find.text('@Trail Walker'), findsOneWidget);
    expect(find.text('@AceWalker'), findsOneWidget);
  });

  testWidgets('"See full group" expands to every walker', (tester) async {
    final auth = await _createAuthService();
    await tester.pumpWidget(_build(auth, _FakeRankedV2Api(_Mode.inCohort)));
    await tester.pump();

    // CouchFan (rank 8) is outside the collapsed window.
    expect(find.text('@CouchFan'), findsNothing);
    final toggle = find.text('See full group (8)');
    await tester.ensureVisible(toggle);
    await tester.pump();
    await tester.tap(toggle);
    await tester.pump();
    expect(find.text('@CouchFan'), findsOneWidget);
    expect(find.text('Show less'), findsOneWidget);
    // The drop cutline becomes visible once the whole group is shown.
    expect(find.text('Bottom 2 drop to Bronze'), findsOneWidget);
  });

  testWidgets('the in-card "How Ranked works" button opens the explainer', (
    tester,
  ) async {
    final auth = await _createAuthService();
    await tester.pumpWidget(_build(auth, _FakeRankedV2Api(_Mode.inCohort)));
    await tester.pump();

    final button = find.text('How Ranked works');
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    // The bottom-sheet explainer content is shown.
    expect(find.textContaining('matched with'), findsOneWidget);
    expect(find.textContaining('Resets every Monday'), findsOneWidget);
  });

  testWidgets('shows the join hint when the user has no cohort yet', (
    tester,
  ) async {
    final auth = await _createAuthService();
    await tester.pumpWidget(_build(auth, _FakeRankedV2Api(_Mode.noCohort)));
    await tester.pump();

    expect(find.textContaining("You're in"), findsOneWidget);
    expect(find.text('How Ranked works'), findsOneWidget);
  });

  testWidgets('falls back to the legacy season ladder when /ranked/v2 404s', (
    tester,
  ) async {
    final auth = await _createAuthService();
    await tester.pumpWidget(_build(auth, _FakeRankedV2Api(_Mode.v2Missing)));
    await tester.pump();
    await tester.pump();

    expect(find.text('GOLD III'), findsOneWidget);
    expect(find.text('RANKED POINTS'), findsOneWidget);
  });
}
