import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/item_slot.dart';

/// Upgrade tier prices must come from the backend when it sends
/// powerupData.upgradeCosts (authoritative ladders), and fall back to the
/// bundled tables against an older backend that omits the field.
class _UpgradeCostsBackendApiService extends BackendApiService {
  _UpgradeCostsBackendApiService({this.upgradeCosts});

  /// Value for powerupData['upgradeCosts']; null = older backend (omitted).
  final Map<String, dynamic>? upgradeCosts;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async {
    return {
      'id': raceId,
      'name': 'Powerup Race',
      'status': 'ACTIVE',
      'targetSteps': 100000,
      'maxDurationDays': 7,
      'buyInAmount': 0,
      'payoutPreset': 'WINNER_TAKES_ALL',
      'potCoins': 0,
      'heldPotCoins': 0,
      'projectedPotCoins': 0,
      'payouts': {'first': 0, 'second': 0, 'third': 0},
      'myStatus': 'ACCEPTED',
      'isCreator': false,
      'powerupsEnabled': true,
      'endsAt': '2026-12-10T12:00:00.000Z',
      'participants': const [
        {'userId': 'user-1', 'displayName': 'Trail Walker', 'status': 'ACCEPTED'},
        {'userId': 'user-2', 'displayName': 'Hill Climber', 'status': 'ACCEPTED'},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async {
    // Mutable maps: the screen mutates powerupData in place after a use.
    return {
      'status': 'ACTIVE',
      'participants': [
        {
          'userId': 'user-1',
          'displayName': 'Trail Walker',
          'totalSteps': 42000,
          'finishedAt': null,
        },
        {
          'userId': 'user-2',
          'displayName': 'Hill Climber',
          'totalSteps': 38000,
          'finishedAt': null,
        },
      ],
      'powerupData': {
        'enabled': true,
        'inventory': [
          {
            'id': 'pw-cramp-1',
            'type': 'LEG_CRAMP',
            'rarity': 'UNCOMMON',
            'status': 'HELD',
          },
        ],
        'powerupSlots': 3,
        'queuedBoxCount': 0,
        'activeEffects': [],
        if (upgradeCosts != null) 'upgradeCosts': upgradeCosts,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaceFeed({
    String? cursor,
    required String identityToken,
    required String raceId,
  }) async {
    return const {'events': []};
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    return const {'coins': 500, 'heldCoins': 0};
  }
}

Future<AuthService> _createAuthService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_coins': 500,
    'auth_held_coins': 0,
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

// Fixed frames instead of pumpAndSettle: the actions sheet contains a spinning
// PowerupIcon (infinite animation) that never settles.
Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _openActionsSheet(WidgetTester tester, dynamic api) async {
  // Phone-sized viewport: the tier sheet (4 buttons) overflows the default
  // 800x600 test surface.
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final authService = await _createAuthService();
  await tester.pumpWidget(
    MaterialApp(
      home: RaceDetailScreen(
        authService: authService,
        raceId: 'race-costs',
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();

  final heldSlot = find.byWidgetPredicate(
    (w) => w is ItemSlot && w.state == ItemSlotState.held,
  );
  expect(heldSlot, findsOneWidget);
  await tester.ensureVisible(heldSlot);
  await tester.tap(heldSlot);
  await _pumpFrames(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'tier prices come from backend upgradeCosts when present',
    (WidgetTester tester) async {
      // Deliberately different from the bundled UNCOMMON [0, 10, 30, 90] so a
      // pass proves the server table wins.
      final api = _UpgradeCostsBackendApiService(
        upgradeCosts: {
          'byRarity': {
            'COMMON': [0, 1, 2, 3],
            'UNCOMMON': [0, 111, 222, 333],
            'RARE': [0, 4, 5, 6],
          },
          'byType': {},
        },
      );

      await _openActionsSheet(tester, api);

      expect(find.textContaining('LVL 1'), findsOneWidget);
      expect(find.text('111'), findsOneWidget);
      expect(find.text('222'), findsOneWidget);
      expect(find.text('333'), findsOneWidget);

      Navigator.of(tester.element(find.textContaining('LVL 1'))).pop();
      await _pumpFrames(tester);
    },
  );

  testWidgets(
    'tier prices fall back to bundled table when backend omits upgradeCosts',
    (WidgetTester tester) async {
      final api = _UpgradeCostsBackendApiService(upgradeCosts: null);

      await _openActionsSheet(tester, api);

      // Bundled UNCOMMON ladder: 10 / 30 / 90.
      expect(find.textContaining('LVL 1'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
      expect(find.text('90'), findsOneWidget);

      Navigator.of(tester.element(find.textContaining('LVL 1'))).pop();
      await _pumpFrames(tester);
    },
  );
}
