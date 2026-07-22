import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/item_slot.dart';

/// B5 — the Pocket Watch sheet must offer a DISCARD like every other powerup.
///
/// Pocket Watch early-returns into its own [PocketWatchSheet], which historically
/// had only the buffs/debuffs toggle + tier buttons — no way to throw the item
/// away. This pumps the real [RaceDetailScreen] with a HELD POCKET_WATCH, opens
/// the sheet, taps DISCARD, and asserts the discard endpoint fires and the item
/// leaves the rail.
class _PocketWatchBackendApiService extends BackendApiService {
  _PocketWatchBackendApiService();

  int discardCalls = 0;
  String? lastDiscardedPowerupId;
  bool _discarded = false;

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
    // After discard, the follow-up progress refresh returns an empty inventory
    // so the held slot must disappear from the rail.
    final inventory = _discarded
        ? const []
        : const [
            {
              'id': 'pw-watch-1',
              'type': 'POCKET_WATCH',
              'rarity': 'RARE',
              'status': 'HELD',
            },
          ];
    return {
      'status': 'ACTIVE',
      'participants': const [
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
        'inventory': inventory,
        'powerupSlots': 3,
        'queuedBoxCount': 0,
        'activeEffects': const [],
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
  Future<Map<String, dynamic>> fetchRaceMessages({
    required String identityToken,
    required String raceId,
    String? cursor,
    int? limit,
    String? kind,
  }) async {
    return const {'messages': [], 'nextCursor': null};
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    return const {'coins': 500, 'heldCoins': 0};
  }

  @override
  Future<Map<String, dynamic>> discardPowerup({
    required String identityToken,
    required String raceId,
    required String powerupId,
  }) async {
    discardCalls += 1;
    lastDiscardedPowerupId = powerupId;
    _discarded = true;
    return const {'success': true};
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

// Fixed frames instead of pumpAndSettle: the sheet's spinning PowerupIcon never
// "settles".
Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Pocket Watch sheet DISCARD calls the discard endpoint and clears the rail',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final api = _PocketWatchBackendApiService();

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-watch',
            backendApiService: api,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Open the held POCKET_WATCH slot -> its dedicated sheet.
      final heldSlot = find.byWidgetPredicate(
        (w) => w is ItemSlot && w.state == ItemSlotState.held,
      );
      expect(heldSlot, findsOneWidget);
      await tester.ensureVisible(heldSlot);
      await tester.tap(heldSlot);
      await _pumpFrames(tester);

      // The Pocket Watch sheet is up, and it now carries a DISCARD control.
      final discard = find.byKey(const Key('pocket-watch-discard'));
      expect(discard, findsOneWidget);

      await tester.tap(discard);
      await _pumpFrames(tester);

      expect(api.discardCalls, 1);
      expect(api.lastDiscardedPowerupId, 'pw-watch-1');

      // The follow-up progress refresh returns an empty inventory, so the held
      // slot is gone from the rail.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byWidgetPredicate(
          (w) => w is ItemSlot && w.state == ItemSlotState.held,
        ),
        findsNothing,
      );

      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));
    },
  );
}
