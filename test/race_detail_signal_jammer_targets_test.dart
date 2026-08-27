import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/item_slot.dart';
import 'package:step_tracker/widgets/leaderboard_plank.dart';

/// Fake API for the Signal Jammer target-picker flow. Renders an ACTIVE race
/// with powerups enabled and a single held SIGNAL_JAMMER in the signed-in
/// user's inventory. Unlike Sneaky Swap (which has its own targets endpoint),
/// the jammer uses the generic picker built from the progress participants,
/// excluding self and stealthed racers.
class _SignalJammerBackendApiService extends BackendApiService {
  _SignalJammerBackendApiService({
    this.heldPowerupType = 'SIGNAL_JAMMER',
    this.viewerDetoured = false,
  });

  final String heldPowerupType;
  final bool viewerDetoured;

  int usePowerupCalls = 0;
  int fetchPublicProfileCalls = 0;
  String? lastUsedPowerupId;
  String? lastTargetUserId;
  int lastUpgradeLevel = -1;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
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
        {
          'userId': 'user-1',
          'displayName': 'Trail Walker',
          'status': 'ACCEPTED',
        },
        {
          'userId': 'user-2',
          'displayName': 'Hill Climber',
          'status': 'ACCEPTED',
        },
        {
          'userId': 'user-3',
          'displayName': 'Ridge Runner',
          'status': 'ACCEPTED',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async {
    // Deliberately mutable (no const): the screen's optimistic inventory
    // removal mutates powerupData in place after a use.
    return {
      'status': 'ACTIVE',
      'participants': [
        {
          'userId': 'user-1',
          'displayName': viewerDetoured ? '???' : 'Trail Walker',
          'totalSteps': viewerDetoured ? null : 42000,
          'finishedAt': null,
          if (viewerDetoured) 'stealthed': true,
          if (viewerDetoured) 'targetable': true,
        },
        {
          'userId': 'user-2',
          'displayName': viewerDetoured ? '???' : 'Hill Climber',
          'totalSteps': viewerDetoured ? null : 38000,
          'finishedAt': null,
          if (viewerDetoured) 'stealthed': true,
          if (viewerDetoured) 'targetable': true,
        },
        {
          'userId': 'user-3',
          'displayName': 'Ridge Runner',
          'totalSteps': 31000,
          'finishedAt': null,
          // Stealthed racers are excluded from the target picker.
          'stealthed': true,
          'targetable': false,
        },
      ],
      'powerupData': {
        'enabled': true,
        'inventory': [
          {
            'id': 'pw-jammer-1',
            'type': heldPowerupType,
            'rarity': 'RARE',
            'status': 'HELD',
          },
        ],
        'powerupSlots': 3,
        'queuedBoxCount': 0,
        'activeEffects': [],
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

  @override
  Future<Map<String, dynamic>> fetchPublicProfile({
    required String identityToken,
    required String userId,
  }) async {
    fetchPublicProfileCalls += 1;
    return const {};
  }

  @override
  Future<Map<String, dynamic>> usePowerup({
    required String identityToken,
    required String raceId,
    required String powerupId,
    String? targetUserId,
    String? targetDirection,
    String? targetEffectId,
    int upgradeLevel = 0,
  }) async {
    usePowerupCalls += 1;
    lastUsedPowerupId = powerupId;
    lastTargetUserId = targetUserId;
    lastUpgradeLevel = upgradeLevel;
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

// Pumps fixed frames instead of pumpAndSettle: the powerup actions sheet and
// pickers contain a spinning PowerupIcon (infinite animation) that never
// "settles".
Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _openSignalJammerUse(WidgetTester tester) async {
  // Tap the held SIGNAL_JAMMER inventory slot to open the powerup actions
  // sheet.
  final heldSlot = find.byWidgetPredicate(
    (w) => w is ItemSlot && w.state == ItemSlotState.held,
  );
  expect(heldSlot, findsOneWidget);
  await tester.ensureVisible(heldSlot);
  await tester.tap(heldSlot);
  await _pumpFrames(tester);

  // Non-upgradeable powerups show USE; upgradeable offensive powerups expose
  // a free base tier instead.
  final useButton = find.text('USE').evaluate().isNotEmpty
      ? find.text('USE')
      : find.textContaining('USE BASE:');
  expect(useButton, findsOneWidget);
  await tester.tap(useButton);
  await _pumpFrames(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Signal Jammer opens the target picker and uses on the chosen racer',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final api = _SignalJammerBackendApiService();

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-jammer',
            backendApiService: api,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      await _openSignalJammerUse(tester);

      // The generic target picker is shown.
      expect(find.text('CHOOSE A TARGET'), findsOneWidget);

      // Scope name assertions to the picker sheet subtree (these names also
      // appear in the race board behind the sheet).
      final pickerColumn = find
          .ancestor(
            of: find.text('CHOOSE A TARGET'),
            matching: find.byType(Column),
          )
          .last;
      // Rival racer appears in the picker; self does not; stealthed racer is
      // excluded.
      expect(
        find.descendant(of: pickerColumn, matching: find.text('@Hill Climber')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: pickerColumn, matching: find.text('38,000 steps')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: pickerColumn, matching: find.text('@Trail Walker')),
        findsNothing,
      );
      expect(
        find.descendant(of: pickerColumn, matching: find.text('@Ridge Runner')),
        findsNothing,
      );

      // Pick the rival -> the use call goes out with their userId, base level.
      await tester.tap(
        find.descendant(of: pickerColumn, matching: find.text('@Hill Climber')),
      );
      await _pumpFrames(tester);

      expect(api.usePowerupCalls, 1);
      expect(api.lastUsedPowerupId, 'pw-jammer-1');
      expect(api.lastTargetUserId, 'user-2');
      expect(api.lastUpgradeLevel, 0);

      // Let any post-use toast/refresh timers finish so nothing is pending at
      // teardown.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));
    },
  );

  testWidgets('Detour-masked rival appears as ??? and can receive Leg Cramp', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final authService = await _createAuthService();
    final api = _SignalJammerBackendApiService(
      heldPowerupType: 'LEG_CRAMP',
      viewerDetoured: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RaceDetailScreen(
          authService: authService,
          raceId: 'race-detoured-targeting',
          backendApiService: api,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // Detour masking must continue to disable the ordinary leaderboard
    // profile action; otherwise a tap would reveal who "???" really is.
    final maskedPlanks = tester
        .widgetList<LeaderboardPlank>(find.byType(LeaderboardPlank))
        .where((plank) => plank.name == '???');
    expect(maskedPlanks, isNotEmpty);
    expect(maskedPlanks.every((plank) => plank.onProfileTap == null), isTrue);
    expect(api.fetchPublicProfileCalls, 0);

    await _openSignalJammerUse(tester);

    expect(find.text('CHOOSE A TARGET'), findsOneWidget);
    final picker = find.byKey(const Key('powerup-target-list'));
    expect(
      find.descendant(of: picker, matching: find.text('???')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: picker, matching: find.textContaining('steps')),
      findsNothing,
    );

    await tester.tap(find.descendant(of: picker, matching: find.text('???')));
    await _pumpFrames(tester);

    expect(api.usePowerupCalls, 1);
    expect(api.lastTargetUserId, 'user-2');

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
  });
}
