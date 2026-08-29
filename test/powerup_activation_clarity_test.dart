import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/constants/powerup_copy.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/item_slot.dart';
import 'package:step_tracker/widgets/powerup_guide_sheet.dart';

class _ClarityApi extends BackendApiService {
  _ClarityApi({
    this.preview,
    this.includePreview = true,
    this.activeEffects = const [],
    this.teamRace = false,
    this.useResult = const {
      'result': {'bonus': 500, 'uniqueTypes': 5, 'perType': 100},
    },
  });

  final Object? preview;
  final bool includePreview;
  final List<Map<String, dynamic>> activeEffects;
  final bool teamRace;
  final Map<String, dynamic> useResult;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async => {
    'id': raceId,
    'name': 'Clarity Trail',
    'status': 'ACTIVE',
    'isTeamRace': teamRace,
    if (teamRace) 'teamSize': 1,
    if (teamRace) 'teamAName': 'Bara Brigade',
    if (teamRace) 'teamBName': 'Otter Outfit',
    'maxDurationDays': 7,
    'buyInAmount': 0,
    'payoutPreset': 'WINNER_TAKES_ALL',
    'potCoins': 0,
    'myStatus': 'ACCEPTED',
    'isCreator': false,
    'powerupsEnabled': true,
    'endsAt': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
    'participants': [
      {
        'userId': 'me',
        'displayName': 'Bara',
        'status': 'ACCEPTED',
        if (teamRace) 'team': 'TEAM_A',
      },
      {
        'userId': 'rival',
        'displayName': 'Otter42',
        'status': 'ACCEPTED',
        if (teamRace) 'team': 'TEAM_B',
      },
    ],
  };

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async => {
    'status': 'ACTIVE',
    'participants': [
      {
        'userId': 'me',
        'displayName': 'Bara',
        'totalSteps': 5000,
        if (teamRace) 'team': 'TEAM_A',
      },
      {
        'userId': 'rival',
        'displayName': 'Otter42',
        'totalSteps': 4000,
        if (teamRace) 'team': 'TEAM_B',
      },
    ],
    'powerupData': {
      'enabled': true,
      'inventory': [
        {
          'id': 'pw-1',
          'type': 'TRAIL_MIX',
          'rarity': 'COMMON',
          'status': 'HELD',
        },
      ],
      'powerupSlots': 3,
      'queuedBoxCount': 0,
      'activeEffects': activeEffects,
      if (includePreview) 'trailMix': {'uniqueTypesIfUsedNow': preview},
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
      const {'coins': 5000, 'heldCoins': 0};

  @override
  Future<Map<String, dynamic>> usePowerup({
    required String identityToken,
    required String raceId,
    required String powerupId,
    String? targetUserId,
    String? targetDirection,
    String? targetEffectId,
    int upgradeLevel = 0,
  }) => Future.value(useResult);
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'token',
    'auth_user_identifier': 'user',
    'auth_session_token': 'session',
    'auth_backend_user_id': 'me',
    'auth_display_name': 'Bara',
    'auth_coins': 5000,
    'auth_held_coins': 0,
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Future<void> _pumpRace(WidgetTester tester, _ClarityApi api) async {
  await tester.binding.setSurfaceSize(const Size(430, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: RaceDetailScreen(
        authService: await _auth(),
        raceId: 'race-clarity',
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _openHeldSheet(WidgetTester tester, _ClarityApi api) async {
  await _pumpRace(tester, api);
  final held = find.byWidgetPredicate(
    (widget) => widget is ItemSlot && widget.state == ItemSlotState.held,
  );
  expect(held, findsOneWidget);
  await tester.ensureVisible(held);
  await tester.tap(held);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PowerupCopy.resetForTest();
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  tearDown(PowerupCopy.resetForTest);

  testWidgets(
    'Trail Mix sheet shows every exact server-count tier calculation',
    (tester) async {
      await _openHeldSheet(tester, _ClarityApi(preview: 4));

      expect(
        find.text('4 unique powerups × 100 = 400 bonus steps'),
        findsOneWidget,
      );
      expect(
        find.text('4 unique powerups × 150 = 600 bonus steps'),
        findsOneWidget,
      );
      expect(
        find.text('4 unique powerups × 200 = 800 bonus steps'),
        findsOneWidget,
      );
      expect(
        find.text('4 unique powerups × 300 = 1,200 bonus steps'),
        findsOneWidget,
      );
    },
  );

  testWidgets('Trail Mix hides its plate when preview is absent or malformed', (
    tester,
  ) async {
    await _openHeldSheet(
      tester,
      _ClarityApi(preview: 'four', includePreview: true),
    );

    expect(find.byKey(const Key('trail-mix-calculation-plate')), findsNothing);
    expect(find.textContaining('unique powerups ×'), findsNothing);
    expect(find.textContaining('USE BASE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Trail Mix success uses authoritative use-time count and bonus', (
    tester,
  ) async {
    await _openHeldSheet(tester, _ClarityApi(preview: 4));

    await tester.tap(find.textContaining('USE BASE'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('Trail Mix: 5 unique powerups · +500 steps'),
      findsOneWidget,
    );
    expect(find.textContaining('Trail Mix activated'), findsNothing);
  });

  testWidgets('malformed Trail Mix result degrades to generic success copy', (
    tester,
  ) async {
    await _openHeldSheet(
      tester,
      _ClarityApi(preview: 4, useResult: const {'result': []}),
    );

    await tester.tap(find.textContaining('USE BASE'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Trail Mix activated!'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('availability v2 manual labels box, shop, and dual sources', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await PowerupCopy.refresh(
      fetch: () async => {
        'version': 'clarity-v2',
        'availabilityVersion': 2,
        'powerups': const [
          {
            'type': 'RED_CARD',
            'name': 'Red Card',
            'description': 'Remove steps',
            'availability': {'shop': false, 'roll': true},
          },
          {
            'type': 'RUNNERS_HIGH',
            'name': "Runner's High",
            'description': 'Double steps',
            'availability': {'shop': true, 'roll': false},
          },
          {
            'type': 'TRAIL_MIX',
            'name': 'Trail Mix',
            'description': 'Bonus steps',
            'availability': {'shop': true, 'roll': true},
          },
          {
            'type': 'LEECH',
            'name': 'Leech',
            'description': 'Unavailable',
            'availability': {'shop': false, 'roll': false},
          },
        ],
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeData.night(),
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(320, 700),
            textScaler: TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: Scaffold(body: PowerupGuideSheet()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('BOX'), findsOneWidget);
    expect(find.text('SHOP'), findsOneWidget);
    await tester.drag(
      find.byKey(const Key('powerup-guide-powerups-page')),
      const Offset(0, -360),
    );
    await tester.pump();
    expect(find.text('BOX + SHOP'), findsOneWidget);
    expect(find.text('Leech'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'old manual catalog stays complete and omits guessed source chips',
    (tester) async {
      await PowerupCopy.refresh(
        fetch: () async => {
          'version': 'legacy',
          'powerups': const [
            {
              'type': 'RED_CARD',
              'name': 'Red Card',
              'description': 'Remove steps',
            },
          ],
        },
      );

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PowerupGuideSheet())),
      );
      await tester.pump();

      expect(
        PowerupCopy.guideEntries.map((entry) => entry.type),
        contains('LEECH'),
      );
      expect(find.byKey(const Key('powerup-source-chip')), findsNothing);
    },
  );

  testWidgets('Ghost Pepper uses phase-local personal and team countdowns', (
    tester,
  ) async {
    final now = DateTime.now();
    final effects = [
      {
        'type': 'GHOST_PEPPER',
        'onSelf': true,
        'sourceUserId': 'me',
        'targetUserId': 'me',
        'startsAt': now.subtract(const Duration(minutes: 5)).toIso8601String(),
        'expiresAt': now.add(const Duration(minutes: 55)).toIso8601String(),
        'phaseDurations': const {'boostMs': 1800000, 'burnoutMs': 1800000},
      },
      {
        'type': 'GHOST_PEPPER',
        'sourceUserId': 'me',
        'targetUserId': 'rival',
        'startsAt': now.subtract(const Duration(minutes: 35)).toIso8601String(),
        'expiresAt': now.add(const Duration(minutes: 25)).toIso8601String(),
        'phaseDurations': const {'boostMs': 1800000, 'burnoutMs': 1800000},
      },
    ];
    await _pumpRace(
      tester,
      _ClarityApi(activeEffects: effects, teamRace: true),
    );

    expect(find.textContaining('BOOST · 24:'), findsOneWidget);

    final rivalEffect = find.byKey(const ValueKey('team-effect-rival-0'));
    expect(rivalEffect, findsOneWidget);
    await tester.ensureVisible(rivalEffect);
    await tester.tap(rivalEffect);
    await tester.pump();

    expect(find.textContaining('BURNOUT · 24:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('malformed Ghost Pepper metadata falls back to legacy expiry', (
    tester,
  ) async {
    final now = DateTime.now();
    await _pumpRace(
      tester,
      _ClarityApi(
        activeEffects: [
          {
            'type': 'GHOST_PEPPER',
            'onSelf': true,
            'sourceUserId': 'me',
            'targetUserId': 'me',
            'startsAt': 'not-a-date',
            'expiresAt': now.add(const Duration(minutes: 55)).toIso8601String(),
            'phaseDurations': const {'boostMs': 0, 'burnoutMs': 'lots'},
          },
        ],
      ),
    );

    expect(find.textContaining('BOOST ·'), findsNothing);
    expect(find.textContaining('BURNOUT ·'), findsNothing);
    expect(find.textContaining('54m'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inconsistent Ghost Pepper timeline falls back to legacy expiry', (
    tester,
  ) async {
    final now = DateTime.now();
    await _pumpRace(
      tester,
      _ClarityApi(
        activeEffects: [
          {
            'type': 'GHOST_PEPPER',
            'onSelf': true,
            'sourceUserId': 'me',
            'targetUserId': 'me',
            'startsAt': now.subtract(const Duration(minutes: 5)).toIso8601String(),
            'expiresAt': now.add(const Duration(minutes: 55)).toIso8601String(),
            'phaseDurations': const {'boostMs': 600000, 'burnoutMs': 600000},
          },
        ],
      ),
    );

    expect(find.textContaining('BOOST ·'), findsNothing);
    expect(find.textContaining('BURNOUT ·'), findsNothing);
    expect(find.textContaining('54m'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
