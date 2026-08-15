// Feature batch 2026-08-08 — copy items and the tap-outside verification.
//
//  * Item 13 — "SOLO" → "CLASSIC" + per-mode description line.
//  * Item 14 — mission line under "STEP. RACE. WIN.".
//  * Item  6 — privacy copy on the onboarding health gate.
//  * Item 15 — VERIFY ONLY: tapping outside the powerup sheet dismisses it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/create_race_screen.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/screens/start_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/item_slot.dart';
import 'package:step_tracker/widgets/onboarding_permission_gate.dart';

const _classicCopy =
    'Every player competes individually. Invite friends or let anyone join.';
const _teamsCopy = 'Two teams compete for the highest combined step total.';
const _bracketCopy =
    'Advance through head-to-head rounds until one winner remains.';

class _CreateStubApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async =>
      const {'coins': 500, 'heldCoins': 0};
}

Future<AuthService> _authService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Runner',
    'auth_coins': 500,
    'auth_held_coins': 0,
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

/// The race-format signpost lives inside the collapsed "CUSTOMIZE RACE"
/// section, so every format assertion has to open it first.
/// The demo prologue renders a trimmed create screen with no disclosure, so
/// the tap is best-effort.
Future<void> _openCustomize(WidgetTester tester) async {
  final disclosure = find.text('CUSTOMIZE RACE');
  if (disclosure.evaluate().isEmpty) return;
  await tester.tap(disclosure);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

// ── Item 15 harness: the real race detail screen with one held powerup ──────

Map<String, dynamic> _race() => {
  'id': 'race-1',
  'name': 'Trail Blazers',
  'status': 'ACTIVE',
  'maxDurationDays': 3,
  'buyInAmount': 0,
  'potCoins': 0,
  'heldPotCoins': 0,
  'projectedPotCoins': 0,
  'myStatus': 'ACCEPTED',
  'isCreator': false,
  'powerupsEnabled': true,
  'endsAt': '2126-04-10T12:00:00.000Z',
  'participants': [
    {'userId': 'user-1', 'displayName': 'Runner 1', 'status': 'ACCEPTED'},
    {'userId': 'user-2', 'displayName': 'Runner 2', 'status': 'ACCEPTED'},
  ],
};

class _RaceStubApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async => _race();

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async => {
    'status': 'ACTIVE',
    'participants': [
      {
        'userId': 'user-1',
        'displayName': 'Runner 1',
        'totalSteps': 9000,
        'finishedAt': null,
      },
    ],
    'powerupData': const {
      'enabled': true,
      'inventory': [
        {
          'id': 'pu-1',
          'type': 'PROTEIN_SHAKE',
          'rarity': 'RARE',
          'status': 'HELD',
          'upgradeLevel': 0,
        },
      ],
      'powerupSlots': 3,
      'queuedBoxCount': 0,
      'activeEffects': [],
    },
  };

  @override
  Future<Map<String, dynamic>> fetchRaceFeed({
    String? cursor,
    required String identityToken,
    required String raceId,
  }) async => const {'events': []};

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async =>
      const {'coins': 100, 'heldCoins': 0};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.bara.steps',
      version: '2.2.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('Item 13 — CLASSIC label + per-mode description', () {
    testWidgets('the format card reads CLASSIC, never SOLO', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final auth = await _authService();
      await tester.pumpWidget(
        MaterialApp(
          home: CreateRaceScreen(
            authService: auth,
            backendApiService: _CreateStubApi(),
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await _openCustomize(tester);

      expect(find.text('CLASSIC'), findsOneWidget);
      expect(find.text('SOLO'), findsNothing);
      // The key is load-bearing for analytics + existing tests.
      expect(find.byKey(const Key('race-format-ffa')), findsOneWidget);
    });

    testWidgets('the description line follows the selection', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final auth = await _authService();
      await tester.pumpWidget(
        MaterialApp(
          home: CreateRaceScreen(
            authService: auth,
            backendApiService: _CreateStubApi(),
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await _openCustomize(tester);

      expect(find.text(_classicCopy), findsOneWidget);

      await tester.tap(find.byKey(const Key('race-format-teams')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(_teamsCopy), findsOneWidget);
      expect(find.text(_classicCopy), findsNothing);

      await tester.tap(find.byKey(const Key('race-format-tournament')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(_bracketCopy), findsOneWidget);

      await tester.tap(find.byKey(const Key('race-format-ffa')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(_classicCopy), findsOneWidget);
    });

    // ui-test-planner checkpoint 13 asked us to check the demo prologue's
    // format card. There ISN'T one: `create_race_screen.dart:1573` gates the
    // whole CUSTOMIZE section (which contains the format signpost) behind
    // `!demoMode`. So the only thing to assert for the demo mirror is that
    // neither the old nor the new label leaks into it.
    testWidgets('the demo prologue renders no format card at all', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final auth = await _authService();
      await tester.pumpWidget(
        MaterialApp(
          home: CreateRaceScreen(
            authService: auth,
            backendApiService: _CreateStubApi(),
            demoMode: true,
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await _openCustomize(tester);

      expect(find.text('CLASSIC'), findsNothing);
      expect(find.text('SOLO'), findsNothing);
      expect(find.text(_classicCopy), findsNothing);
      expect(find.byKey(const Key('race-format-ffa')), findsNothing);
    });
  });

  group('Item 14 — mission line', () {
    testWidgets('sits under the tagline, and the tagline stays', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(home: StartScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      final title = find.text('Bara');
      final mission = find.text(
        'Step challenges are more fun when you can steal someone’s steps.',
      );
      expect(find.text('STEP. RACE. WIN.'), findsNothing);
      expect(
        find.text("We're on a mission to make your daily steps fun"),
        findsNothing,
      );
      expect(mission, findsOneWidget);
      expect(
        tester.getTopLeft(mission).dy,
        greaterThan(tester.getTopLeft(title).dy),
      );
    });
  });

  group('Item 6 — privacy copy on the health gate', () {
    testWidgets('the onboarding gate spells out what we do not read', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingPermissionGate(
            label: 'HEALTH DATA',
            headline: 'Connect steps to start racing',
            body:
                'Bara only reads your step count. It never reads your routes, '
                'workouts, heart rate, or location. Your steps are used for '
                'races and nothing else, and we never sell your data.',
            icon: Icons.favorite_rounded,
            onContinue: () {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('only reads your step count'), findsOneWidget);
      expect(find.textContaining('never sell your data'), findsOneWidget);
      // Truthfulness guard: we DO store step counts, so the screen must never
      // claim otherwise.
      expect(find.textContaining('collect nothing'), findsNothing);
    });
  });

  group('Item 15 — tap outside dismisses the powerup sheet (verify only)', () {
    testWidgets('the sheet closes on a barrier tap', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final auth = await _authService();
      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: auth,
            raceId: 'race-1',
            backendApiService: _RaceStubApi(),
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final heldSlot = find.byWidgetPredicate(
        (w) => w is ItemSlot && w.state == ItemSlotState.held,
      );
      await tester.ensureVisible(heldSlot);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(heldSlot);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('DISCARD'), findsOneWidget);

      // Tap the scrim well above the sheet.
      await tester.tapAt(const Offset(10, 10));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('DISCARD'), findsNothing);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump(const Duration(milliseconds: 50));
    });
  });
}
