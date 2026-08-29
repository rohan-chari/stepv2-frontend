import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/powerup_icon.dart';

// Compact-lanes integration coverage. This deliberately keeps the historical
// filename so the protected vertical-rail test has a clear diff: its `+N`
// assertion is replaced by reachability for every ordered horizontal effect,
// while polarity, tooltip clamping, Stealth, and gesture isolation remain.

class _RailApi extends BackendApiService {
  _RailApi({Object? activeEffects}) : _activeEffects = activeEffects;

  final Object? _activeEffects;

  List<Object?> get _defaultEffects => [
    {
      'type': 'PROTEIN_SHAKE',
      'targetUserId': 'user-1',
      'sourceUserId': 'user-1',
    },
    for (final type in const [
      'RAINSTORM',
      'LEG_CRAMP',
      'WRONG_TURN',
      'DETOUR_SIGN',
      'SIGNAL_JAMMER',
    ])
      {'type': type, 'targetUserId': 'enemy-1', 'sourceUserId': 'user-1'},
    {
      'type': 'RED_CARD',
      'targetUserId': 'enemy-2',
      'sourceUserId': 'user-1',
      'expiresAt': DateTime.now()
          .add(const Duration(hours: 3))
          .toIso8601String(),
    },
  ];

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async => {
    'id': raceId,
    'name': 'Rail Race',
    'status': 'ACTIVE',
    'isTeamRace': true,
    'teamSize': 2,
    'teamAName': 'Swift Capys',
    'teamBName': 'Turbo Beavers',
    'maxDurationDays': 7,
    'buyInAmount': 0,
    'payoutPreset': 'WINNER_TAKES_ALL',
    'potCoins': 0,
    'myStatus': 'ACCEPTED',
    'isCreator': false,
    'powerupsEnabled': true,
    'endsAt': '2026-12-10T12:00:00.000Z',
    'participants': const [
      {
        'userId': 'user-1',
        'displayName': 'Me Myself',
        'status': 'ACCEPTED',
        'team': 'TEAM_A',
      },
      {
        'userId': 'ally-1',
        'displayName': 'Ally Alice',
        'status': 'ACCEPTED',
        'team': 'TEAM_A',
      },
      {
        'userId': 'enemy-1',
        'displayName': 'Enemy Eve With A Very Long Trail Name',
        'status': 'ACCEPTED',
        'team': 'TEAM_B',
      },
      {
        'userId': 'enemy-2',
        'displayName': 'Enemy Ed',
        'status': 'ACCEPTED',
        'team': 'TEAM_B',
      },
      // The two cells whose CONTENT height differs from a plain cell: a frozen
      // racer (icon-only multiplier chip is 23pt tall vs a 20.25pt name row)
      // and a stealthed racer (draws no progress bar at all).
      {
        'userId': 'ally-2',
        'displayName': 'Frozen Fred',
        'status': 'ACCEPTED',
        'team': 'TEAM_A',
      },
      {
        'userId': 'enemy-3',
        'displayName': 'Sneaky Sue',
        'status': 'ACCEPTED',
        'team': 'TEAM_B',
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
        'userId': 'user-1',
        'displayName': 'Me Myself',
        'team': 'TEAM_A',
        'totalSteps': 6200,
        'finishedAt': null,
      },
      {
        'userId': 'ally-1',
        'displayName': 'Ally Alice',
        'team': 'TEAM_A',
        'totalSteps': 6100,
        'finishedAt': null,
      },
      {
        'userId': 'enemy-1',
        'displayName': 'Enemy Eve With A Very Long Trail Name',
        'team': 'TEAM_B',
        'totalSteps': 1234567,
        'currentMultiplier': 2,
        'finishedAt': null,
      },
      {
        'userId': 'enemy-2',
        'displayName': 'Enemy Ed',
        'team': 'TEAM_B',
        'totalSteps': 5000,
        'finishedAt': null,
      },
      {
        'userId': 'ally-2',
        'displayName': 'Frozen Fred',
        'team': 'TEAM_A',
        'totalSteps': 4800,
        // < 0.5 → the frost chip, which renders ICON-ONLY and taller.
        'currentMultiplier': 0.2,
        'forfeitedAt': '2026-08-01T12:00:00.000Z',
        'finishedAt': null,
      },
      {
        'userId': 'enemy-3',
        'displayName': '???',
        'stealthed': true,
        'team': 'TEAM_B',
        'totalSteps': null,
        'finishedAt': null,
      },
    ],
    'powerupData': {
      'enabled': true,
      'inventory': [],
      'powerupSlots': 3,
      'queuedBoxCount': 0,
      'powerupStepInterval': 5000,
      'stepsUntilNextPowerup': 1000,
      'activeEffects': _activeEffects ?? _defaultEffects,
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
      const {'coins': 320, 'heldCoins': 0};

  @override
  Future<Map<String, dynamic>> fetchFriends({
    required String identityToken,
  }) async => const {'friends': [], 'pending': {}};
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Me Myself',
    'auth_coins': 420,
    'auth_held_coins': 0,
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(430, 1600),
  double textScale = 1,
  Object? activeEffects,
  bool dark = false,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final auth = await _auth();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppThemeData.light(),
      darkTheme: AppThemeData.night(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: RaceDetailScreen(
        authService: auth,
        raceId: 'race-rail',
        backendApiService: _RailApi(activeEffects: activeEffects),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

double _cellHeight(WidgetTester tester, String userId) =>
    tester.getSize(find.byKey(ValueKey('team-cell-$userId'))).height;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('effects use one full row without growing again for overflow', (
    tester,
  ) async {
    await _pump(tester);

    final zero = _cellHeight(tester, 'ally-1'); // 0 effects
    final one = _cellHeight(tester, 'enemy-2'); // 1 effect
    final five = _cellHeight(tester, 'enemy-1'); // 5 effects (scrolling)

    expect(one, greaterThan(zero));
    // Overflow stays in the horizontal carousel instead of adding another row.
    // The one-point difference is the five-effect racer's multiplier chip.
    expect(five, closeTo(one, 2));
    expect(_cellHeight(tester, 'ally-2'), zero); // frozen multiplier chip
    expect(_cellHeight(tester, 'enemy-3'), zero); // stealthed racer
    expect(zero, lessThan(72));
    expect(one, inInclusiveRange(80, 100));
  });

  testWidgets('racer avatars omit placement pills', (tester) async {
    await _pump(tester);

    for (final userId in ['user-1', 'ally-1', 'enemy-1', 'enemy-2']) {
      final avatar = find.byKey(ValueKey('team-avatar-$userId'));
      expect(
        find.descendant(of: avatar, matching: find.byType(Text)),
        findsNothing,
      );
    }
  });

  testWidgets('dark green team cards use a subtle readable accent', (
    tester,
  ) async {
    await _pump(tester, dark: true);

    final palette = AppColors.of(
      tester.element(find.byKey(const ValueKey('team-cell-enemy-1'))),
    );
    final cell = tester.widget<Container>(
      find.byKey(const ValueKey('team-cell-enemy-1')),
    );
    final decoration = cell.decoration! as BoxDecoration;
    expect(
      decoration.color,
      Color.lerp(palette.parchmentLight, palette.roofRidge, 0.07),
    );
    final score = tester.widget<Text>(find.text('1,234,567'));
    final foreground = score.style!.color!;
    final background = decoration.color!;
    final lighter = foreground.computeLuminance() + 0.05;
    final darker = background.computeLuminance() + 0.05;
    expect(lighter / darker, greaterThanOrEqualTo(4.5));

    final hero = tester.widget<Container>(
      find.byKey(const ValueKey('team-card-TEAM_B')),
    );
    final heroDecoration = hero.decoration! as BoxDecoration;
    expect(
      heroDecoration.color,
      Color.lerp(palette.parchmentLight, palette.roofRidge, 0.08),
    );
    final heroScore = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(const ValueKey('team-card-TEAM_B')),
            matching: find.byType(Text),
          ),
        )
        .firstWhere((text) => text.style?.fontSize == 30);
    final heroForeground = heroScore.style!.color!;
    expect(
      (heroForeground.computeLuminance() + 0.05) /
          (heroDecoration.color!.computeLuminance() + 0.05),
      greaterThanOrEqualTo(4.5),
    );
  });

  testWidgets('team scoreboard reclaims shell and inner horizontal padding', (
    tester,
  ) async {
    await _pump(tester, size: const Size(430, 1600));

    final shell = find.byKey(const ValueKey('team-scoreboard-shell'));
    expect(shell, findsOneWidget);
    final shellRect = tester.getRect(shell);
    final heroRect = tester.getRect(
      find.byKey(const ValueKey('team-card-TEAM_A')),
    );
    expect(shellRect.left, lessThanOrEqualTo(8));
    expect(heroRect.left - shellRect.left, lessThanOrEqualTo(10));
  });

  testWidgets('all five ordered effects render in one horizontal tray, no +N', (
    tester,
  ) async {
    await _pump(tester);

    final tray = find.byKey(const ValueKey('team-effect-tray-enemy-1'));
    final icons = find.descendant(of: tray, matching: find.byType(PowerupIcon));
    expect(tray, findsOneWidget);
    expect(icons, findsNWidgets(5));
    expect(
      tester.widgetList<PowerupIcon>(icons).map((icon) => icon.type),
      const [
        'RAINSTORM',
        'LEG_CRAMP',
        'WRONG_TURN',
        'DETOUR_SIGN',
        'SIGNAL_JAMMER',
      ],
    );
    for (var i = 0; i < 5; i++) {
      expect(find.byKey(ValueKey('team-effect-enemy-1-$i')), findsOneWidget);
    }

    final scrollable = find.descendant(
      of: tray,
      matching: find.byType(Scrollable),
    );
    expect(scrollable, findsOneWidget);
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.pixels, 0);

    final trayRect = tester.getRect(tray);
    final lastEffect = find.byKey(const ValueKey('team-effect-enemy-1-4'));
    expect(position.maxScrollExtent, greaterThan(0));
    await tester.drag(tray, const Offset(-400, 0));
    await tester.pump();
    expect(position.pixels, greaterThan(0));
    expect(tester.getRect(lastEffect).right, lessThanOrEqualTo(trayRect.right));
    expect(
      find.descendant(of: tray, matching: find.textContaining('+')),
      findsNothing,
    );
  });

  testWidgets('team tray sprites use distinct framed polarity boxes', (
    tester,
  ) async {
    await _pump(tester);

    final debuff = find.descendant(
      of: find.byKey(const ValueKey('team-cell-enemy-2')),
      matching: find.byKey(const Key('team-effect-plate-debuff')),
    );
    final boost = find.descendant(
      of: find.byKey(const ValueKey('team-cell-user-1')),
      matching: find.byKey(const Key('team-effect-plate-boost')),
    );
    expect(debuff, findsOneWidget);
    expect(boost, findsOneWidget);

    final debuffDecoration =
        tester.widget<Container>(debuff).decoration as BoxDecoration;
    final boostDecoration =
        tester.widget<Container>(boost).decoration as BoxDecoration;
    expect(debuffDecoration.color, isNot(boostDecoration.color));
    expect(debuffDecoration.color, isNot(Colors.transparent));
    expect(boostDecoration.color, isNot(Colors.transparent));
    expect(debuffDecoration.border, isNotNull);
    expect(boostDecoration.border, isNotNull);
    expect(debuffDecoration.borderRadius, isNotNull);
    expect(boostDecoration.borderRadius, isNotNull);
  });

  testWidgets('a right-edge effect icon shows its tooltip fully on-screen', (
    tester,
  ) async {
    await _pump(tester);

    final cell = find.byKey(const ValueKey('team-cell-enemy-2'));
    await tester.ensureVisible(cell);
    await tester.pump();

    final icon = find.descendant(of: cell, matching: find.byType(PowerupIcon));
    expect(icon, findsOneWidget);
    await tester.tap(icon);
    await tester.pump();

    // The tooltip bubble text is present…
    final bubble = find.textContaining('Red Card:');
    expect(bubble, findsOneWidget);
    expect(find.textContaining('From @Me Myself'), findsOneWidget);
    // Assert the duration belongs to this tooltip. A broad page-level `2h`
    // finder also matches long live race countdowns as the fixture date ages.
    expect(tester.widget<Text>(bubble).data, contains('2h'));
    // …and clamped fully within the 430pt-wide screen (the old fixed offset
    // would have pushed a right-column bubble off the right edge).
    final rect = tester.getRect(bubble);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(430));

    // Dismiss the 3s auto-hide timer before teardown.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('every tray effect and overflowing tray expose semantics', (
    tester,
  ) async {
    await _pump(tester);
    // The single-effect opponent surfaces its powerup name to a11y (enemy-2 is
    // the only Red Card on screen). Assert the Semantics label is set directly,
    // independent of scroll/semantics-tree compilation.
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Red Card',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            (w.properties.label ?? '').contains('Swipe horizontally'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'the full-width row announces overflow only when content exceeds it',
    (tester) async {
      const fourEffects = [
        {
          'type': 'RAINSTORM',
          'targetUserId': 'enemy-2',
          'sourceUserId': 'user-1',
        },
        {
          'type': 'LEG_CRAMP',
          'targetUserId': 'enemy-2',
          'sourceUserId': 'user-1',
        },
        {
          'type': 'WRONG_TURN',
          'targetUserId': 'enemy-2',
          'sourceUserId': 'user-1',
        },
        {
          'type': 'RED_CARD',
          'targetUserId': 'enemy-2',
          'sourceUserId': 'user-1',
        },
      ];
      await _pump(
        tester,
        size: const Size(320, 1800),
        activeEffects: fourEffects,
      );
      var tray = find.byKey(const ValueKey('team-effect-tray-enemy-2'));
      expect(
        tester.widget<Semantics>(tray).properties.label,
        contains('Swipe horizontally'),
      );

      await _pump(
        tester,
        size: const Size(700, 1800),
        activeEffects: fourEffects,
      );
      tray = find.byKey(const ValueKey('team-effect-tray-enemy-2'));
      expect(
        tester.widget<Semantics>(tray).properties.label,
        isNot(contains('Swipe horizontally')),
      );
    },
  );

  testWidgets('effect artwork keeps a 44px tooltip hit target', (tester) async {
    await _pump(tester);
    final target = find.byKey(const ValueKey('team-effect-enemy-2-0'));
    final tray = find.byKey(const ValueKey('team-effect-tray-enemy-2'));
    final visibleTarget = tester
        .getRect(target)
        .intersect(tester.getRect(tray));
    expect(visibleTarget.width, greaterThanOrEqualTo(44));
    expect(visibleTarget.height, greaterThanOrEqualTo(44));
  });

  testWidgets('tray taps and drags stay inside the friend-card boundary', (
    tester,
  ) async {
    await _pump(tester);
    final tray = find.byKey(const ValueKey('team-effect-tray-enemy-1'));
    await tester.ensureVisible(tray);
    await tester.pump(const Duration(seconds: 1));

    final cell = find.byKey(const ValueKey('team-cell-enemy-1'));
    final name = find.descendant(
      of: cell,
      matching: find.textContaining('@Enemy Eve'),
    );
    await tester.tap(name);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 300));

    final firstIcon = find
        .descendant(of: tray, matching: find.byType(PowerupIcon))
        .first;
    await tester.tap(firstIcon);
    await tester.pump();
    expect(find.text('ADD FRIEND'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));

    await tester.drag(tray, const Offset(-80, 0));
    await tester.pump();
    expect(find.text('ADD FRIEND'), findsNothing);

    final oneEffectTray = find.byKey(
      const ValueKey('team-effect-tray-enemy-2'),
    );
    await tester.ensureVisible(oneEffectTray);
    await tester.pump();
    final trayRect = tester.getRect(oneEffectTray);
    await tester.tapAt(Offset(trayRect.right - 2, trayRect.center.dy));
    await tester.pump();
    expect(find.text('ADD FRIEND'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets(
    'exact score sits below the name with effects on the full row beneath',
    (tester) async {
      await _pump(tester, size: const Size(320, 1800), textScale: 1.3);

      expect(find.text('1,234,567'), findsOneWidget);
      expect(find.text('2x'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final cell = find.byKey(const ValueKey('team-cell-enemy-1'));
      final cellRect = tester.getRect(cell);
      final cellDecoration =
          tester.widget<Container>(cell).decoration! as BoxDecoration;
      final cellBorder = cellDecoration.border! as Border;
      final contentInset = 5 + cellBorder.left.width;
      final avatarRect = tester.getRect(
        find.byKey(const ValueKey('team-avatar-enemy-1')),
      );
      final nameRect = tester.getRect(
        find.byKey(const ValueKey('team-name-enemy-1')),
      );
      final scoreGroupRect = tester.getRect(
        find.byKey(const ValueKey('team-score-group-enemy-1')),
      );
      final scoreRect = tester.getRect(find.text('1,234,567'));
      final multiplierRect = tester.getRect(find.text('2x'));
      final trayRect = tester.getRect(
        find.byKey(const ValueKey('team-effect-tray-enemy-1')),
      );

      expect(cellRect.right, lessThanOrEqualTo(320));
      expect(avatarRect.top, lessThan(nameRect.bottom));
      expect(nameRect.top, lessThan(avatarRect.bottom));
      expect(scoreGroupRect.top, greaterThanOrEqualTo(nameRect.bottom - 1));
      expect(scoreGroupRect.left, closeTo(nameRect.left, 1));
      expect(scoreGroupRect.left, greaterThanOrEqualTo(cellRect.left));
      expect(scoreGroupRect.right, lessThanOrEqualTo(cellRect.right));
      expect(trayRect.left, closeTo(cellRect.left + contentInset, 0.1));
      expect(trayRect.top, greaterThanOrEqualTo(scoreGroupRect.bottom));
      expect(trayRect.right, closeTo(cellRect.right - contentInset, 0.1));
      expect(scoreRect.left, closeTo(nameRect.left, 1));
      expect(multiplierRect.left, greaterThanOrEqualTo(scoreRect.left));
      expect(multiplierRect.bottom, lessThanOrEqualTo(cellRect.bottom));
    },
  );

  testWidgets('two-times text scaling keeps the stacked score readable', (
    tester,
  ) async {
    await _pump(tester, size: const Size(430, 1800), textScale: 2);

    final nameRect = tester.getRect(
      find.byKey(const ValueKey('team-name-enemy-1')),
    );
    final scoreGroupRect = tester.getRect(
      find.byKey(const ValueKey('team-score-group-enemy-1')),
    );
    final scoreRect = tester.getRect(find.text('1,234,567'));
    expect(scoreGroupRect.top, greaterThanOrEqualTo(nameRect.bottom - 1));
    expect(scoreGroupRect.left, closeTo(nameRect.left, 1));
    expect(scoreRect.height, greaterThanOrEqualTo(9));
    expect(tester.takeException(), isNull);
  });

  testWidgets('self highlight and forfeited interaction survive compaction', (
    tester,
  ) async {
    await _pump(tester);

    final selfCell = find.byKey(const ValueKey('team-cell-user-1'));
    final selfDecoration =
        tester.widget<Container>(selfCell).decoration as BoxDecoration;
    expect(selfDecoration.border!.top.width, 2);

    await tester.tap(
      find.descendant(
        of: selfCell,
        matching: find.byKey(const ValueKey('team-name-user-1')),
      ),
    );
    await tester.pump();
    expect(find.byType(BottomSheet), findsNothing);

    final forfeitedCell = find.byKey(const ValueKey('team-cell-ally-2'));
    await tester.ensureVisible(forfeitedCell);
    await tester.pump();
    final forfeitedOpacity = find.ancestor(
      of: forfeitedCell,
      matching: find.byWidgetPredicate(
        (widget) => widget is Opacity && widget.opacity == 0.5,
      ),
    );
    expect(forfeitedOpacity, findsOneWidget);
    expect(tester.widget<Opacity>(forfeitedOpacity).opacity, 0.5);

    await tester.tap(
      find.descendant(
        of: forfeitedCell,
        matching: find.byKey(const ValueKey('team-name-ally-2')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 300));
  });

  for (final width in const [320.0, 375.0, 390.0, 430.0]) {
    for (final scale in const [1.0, 1.3]) {
      testWidgets(
        'separate cards do not overflow at ${width.toInt()}px / ${scale}x text',
        (tester) async {
          await _pump(tester, size: Size(width, 1800), textScale: scale);

          expect(tester.takeException(), isNull);
          expect(
            tester.getRect(find.byKey(const ValueKey('team-card-TEAM_A'))).left,
            greaterThanOrEqualTo(0),
          );
          expect(
            tester
                .getRect(find.byKey(const ValueKey('team-card-TEAM_B')))
                .right,
            lessThanOrEqualTo(width),
          );
          expect(find.byKey(const ValueKey('team-lane-TEAM_A')), findsNothing);
          expect(find.byKey(const ValueKey('team-lane-TEAM_B')), findsNothing);
          expect(find.text('1,234,567'), findsOneWidget);
          expect(find.text('2x'), findsOneWidget);
        },
      );
    }
  }

  testWidgets(
    'mixed-version effect shapes degrade individually without throw',
    (tester) async {
      for (final effects in <Object?>[
        'not-a-list',
        <Object?>[
          null,
          7,
          const {},
          const {'type': null},
        ],
        <Object?>[
          const {
            'type': 'RED_CARD',
            'targetUserId': 42,
            'sourceUserId': <String>[],
            'expiresAt': 'not-a-date',
          },
        ],
      ]) {
        await _pump(tester, activeEffects: effects);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('unknown effect still opens a fallback-name tooltip', (
    tester,
  ) async {
    await _pump(
      tester,
      activeEffects: const [
        {
          'type': 'FUTURE_WIND',
          'targetUserId': 'enemy-2',
          'sourceUserId': '',
          'expiresAt': 'bad',
        },
      ],
    );

    final tray = find.byKey(const ValueKey('team-effect-tray-enemy-2'));
    await tester.ensureVisible(tray);
    await tester.pump();
    await tester.tap(
      find.descendant(of: tray, matching: find.byType(PowerupIcon)),
    );
    await tester.pump();
    expect(find.textContaining('FUTURE_WIND'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('stealthed racers expose no multiplier or effect tray', (
    tester,
  ) async {
    await _pump(
      tester,
      activeEffects: const [
        {
          'type': 'RUNNERS_HIGH',
          'targetUserId': 'enemy-3',
          'sourceUserId': 'enemy-3',
        },
      ],
    );

    final cell = find.byKey(const ValueKey('team-cell-enemy-3'));
    expect(
      find.descendant(of: cell, matching: find.byType(PowerupIcon)),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('team-effect-tray-enemy-3')),
      findsNothing,
    );
  });
}
