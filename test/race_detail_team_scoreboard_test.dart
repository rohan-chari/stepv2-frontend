import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/demo/demo_race_engine.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/utils/team_race.dart';
import 'package:step_tracker/widgets/home_course_track.dart';
import 'package:step_tracker/widgets/home_hero_scene.dart';
import 'package:step_tracker/widgets/remote_or_bundled_accessory_image.dart';
import 'package:step_tracker/widgets/team_scoreboard_cards.dart';
import 'package:step_tracker/tutorial/tutorial_preview_data.dart';

// Integration cover for the redesigned ACTIVE team SCOREBOARD, pumped through
// the REAL screen (CLAUDE.md: integration over unit). The leaf widgets have
// their own tests in team_scoreboard_cards_test.dart; what can only be checked
// here is the SCREEN's plumbing — which totals feed the ribbon, which member
// gets the portrait, and which side the viewer is judged to be on.
//
// The stealth case is the one that matters: the cards render the backend's
// honest `teams` block while the portrait/roster read the participants list,
// and those two disagree exactly when a member is hidden.

class _ScoreboardApi extends BackendApiService {
  _ScoreboardApi({
    this.teamATotal = 12340,
    this.teamBTotal = 11900,
    this.stealthTeamB = false,
    this.omitTeamsBlock = false,
    this.myTeam = 'TEAM_A',
    this.emptyParticipants = false,
    this.teamALeaderName = 'Hill Climber',
    this.teamALeaderHasWideCosmetics = false,
    this.teamAAnimal,
    this.teamAAccessories,
    this.pollLeaderSwap = false,
    this.pollFlipTotals = false,
    this.allTeamBStealthed = false,
  });

  final int teamATotal;
  final int teamBTotal;
  final bool stealthTeamB;

  /// Drops the honest `teams` block so totals fall back to summing planks —
  /// the path where a stealthed member makes a side genuinely unknowable.
  final bool omitTeamsBlock;

  /// The side `user-1` (the viewer) sits on; null makes them a spectator.
  final String? myTeam;
  final bool emptyParticipants;
  final String teamALeaderName;
  final bool teamALeaderHasWideCosmetics;
  final String? teamAAnimal;
  final List<dynamic>? teamAAccessories;
  final bool pollLeaderSwap;
  final bool pollFlipTotals;
  final bool allTeamBStealthed;
  int progressCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async {
    return {
      'id': raceId,
      'name': 'Team Clash',
      'status': 'ACTIVE',
      'isTeamRace': true,
      'teamSize': 2,
      'teamAName': 'Swift Capys',
      'teamBName': 'Turbo Beavers',
      'maxDurationDays': 7,
      'buyInAmount': 0,
      'payoutPreset': 'WINNER_TAKES_ALL',
      'potCoins': 0,
      'myStatus': myTeam == null ? 'NONE' : 'ACCEPTED',
      'isCreator': false,
      'powerupsEnabled': false,
      'endsAt': '2026-08-10T12:00:00.000Z',
      'participants': [
        if (!emptyParticipants && myTeam != null)
          {
            'userId': 'user-1',
            'displayName': 'Trail Walker',
            'status': 'ACCEPTED',
            'team': myTeam,
          },
        if (!emptyParticipants)
          {
            'userId': 'u2',
            'displayName': teamALeaderName,
            'status': 'ACCEPTED',
            'team': 'TEAM_A',
          },
        if (!emptyParticipants)
          {
            'userId': 'u3',
            'displayName': 'Sneaky Pete',
            'status': 'ACCEPTED',
            'team': 'TEAM_B',
          },
        if (!emptyParticipants)
          {
            'userId': 'u4',
            'displayName': 'Marsh Mellow',
            'status': 'ACCEPTED',
            'team': 'TEAM_B',
          },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async {
    progressCalls += 1;
    final swapped = pollLeaderSwap && progressCalls >= 2;
    final flippedTotals = pollFlipTotals && progressCalls >= 2;
    return {
      'status': 'ACTIVE',
      if (!omitTeamsBlock)
        'teams': {
          'teamA': {
            'name': 'Swift Capys',
            'totalSteps': flippedTotals ? 8000 : teamATotal,
          },
          'teamB': {
            'name': 'Turbo Beavers',
            'totalSteps': flippedTotals ? 20000 : teamBTotal,
          },
        },
      'participants': [
        if (!emptyParticipants && myTeam != null)
          {
            'userId': 'user-1',
            'displayName': 'Trail Walker',
            'team': myTeam,
            'totalSteps': 6200,
            'finishedAt': null,
          },
        if (!emptyParticipants)
          {
            'userId': 'u2',
            'displayName': teamALeaderName,
            'team': 'TEAM_A',
            if (teamAAnimal != null || teamALeaderHasWideCosmetics)
              'animal': teamAAnimal ?? 'corgi_puppy',
            if (teamAAccessories != null)
              'accessories': teamAAccessories
            else if (teamALeaderHasWideCosmetics)
              'accessories': const [
                {
                  'slot': 'BACK',
                  'assetKey': 'angel_wings',
                  'renderMetadata': {
                    // Fixed-pixel metadata is also valid; unlike fractional
                    // offsets, it must not shrink with the hero sprite.
                    'offsetX': -30.0,
                    'offsetY': -30.0,
                    'scale': 1.35,
                    'renderLayer': 'behind',
                  },
                },
              ],
            // Deliberately the biggest number on Team A, so the portrait has a
            // clear winner that is NOT the viewer.
            'totalSteps': 9000,
            'finishedAt': null,
          },
        if (!emptyParticipants && swapped)
          {
            'userId': 'u5',
            'displayName': 'Fresh Leader',
            'team': 'TEAM_A',
            'animal': 'turtle',
            'totalSteps': 12000,
            'finishedAt': null,
          },
        if (!emptyParticipants)
          {
            'userId': 'u3',
            'displayName': stealthTeamB || allTeamBStealthed
                ? '???'
                : 'Sneaky Pete',
            if (stealthTeamB || allTeamBStealthed) 'stealthed': true,
            'team': 'TEAM_B',
            // null (not 0) is what the backend sends for a hidden member.
            'totalSteps': stealthTeamB ? null : 7000,
            'finishedAt': null,
          },
        if (!emptyParticipants)
          {
            'userId': 'u4',
            'displayName': allTeamBStealthed ? '???' : 'Marsh Mellow',
            if (allTeamBStealthed) 'stealthed': true,
            'team': 'TEAM_B',
            'totalSteps': 5000,
            'finishedAt': null,
          },
      ],
      'powerupData': const {
        'enabled': false,
        'inventory': [],
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
    return const {'coins': 320, 'heldCoins': 0};
  }
}

Future<void> _pump(
  WidgetTester tester,
  BackendApiService api, {
  ThemeData? theme,
  double? width,
  ValueNotifier<bool>? disableAnimations,
  ValueNotifier<bool>? tickerEnabled,
}) async {
  if (width != null) {
    await tester.binding.setSurfaceSize(Size(width, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_coins': 420,
    'auth_held_coins': 0,
  });
  final authService = AuthService();
  await authService.restoreSession();
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      theme: theme,
      builder: (context, child) {
        Widget result = child!;
        if (tickerEnabled case final enabled?) {
          result = ValueListenableBuilder<bool>(
            valueListenable: enabled,
            builder: (context, value, child) =>
                TickerMode(enabled: value, child: child!),
            child: result,
          );
        }
        if (disableAnimations case final disabled?) {
          result = ValueListenableBuilder<bool>(
            valueListenable: disabled,
            builder: (context, value, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: value),
              child: child!,
            ),
            child: result,
          );
        }
        return result;
      },
      home: RaceDetailScreen(
        authService: authService,
        raceId: 'race-scoreboard',
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

// The LEADING ribbon became an outline on the card itself; this key marks the
// crowned card so "which side is leading?" stays assertable.
final _leadingA = find.byKey(const ValueKey('team-leading-TEAM_A'));
final _leadingB = find.byKey(const ValueKey('team-leading-TEAM_B'));
final _banner = find.byKey(const Key('team-lead-banner'));
final _cardA = find.byKey(const ValueKey('team-card-TEAM_A'));
final _cardB = find.byKey(const ValueKey('team-card-TEAM_B'));
final _sceneA = find.byKey(const ValueKey('team-hero-scene-TEAM_A'));
final _sceneB = find.byKey(const ValueKey('team-hero-scene-TEAM_B'));

Finder _inScene(Finder scene, Finder matching) =>
    find.descendant(of: scene, matching: matching);

double _groundDx(WidgetTester tester, Finder scene) {
  final finder = _inScene(
    scene,
    find.ancestor(
      of: find.byKey(const Key('hero-ground-strip')),
      matching: find.byType(Transform),
    ),
  );
  if (finder.evaluate().isEmpty) return 0;
  final transform = tester.widget<Transform>(finder);
  return transform.transform.getTranslation().x;
}

int _animalFrame(WidgetTester tester, Finder scene) => tester
    .widget<CapybaraSpriteWithAccessories>(
      _inScene(scene, find.byType(CapybaraSpriteWithAccessories)),
    )
    .frameIndex;

double _cloudLeft(WidgetTester tester, Finder scene) => tester
    .widget<Positioned>(
      _inScene(
        scene,
        find.descendant(
          of: find.byKey(const ValueKey('home-cloud-0')),
          matching: find.byType(Positioned),
        ),
      ).first,
    )
    .left!;

Rect _transformedRect(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  final points = <Offset>[
    box.localToGlobal(Offset.zero),
    box.localToGlobal(Offset(box.size.width, 0)),
    box.localToGlobal(Offset(0, box.size.height)),
    box.localToGlobal(Offset(box.size.width, box.size.height)),
  ];
  return Rect.fromLTRB(
    points.map((point) => point.dx).reduce(math.min),
    points.map((point) => point.dy).reduce(math.min),
    points.map((point) => point.dx).reduce(math.max),
    points.map((point) => point.dy).reduce(math.max),
  );
}

Color _coloredBoxColor(WidgetTester tester, String key) =>
    tester.widget<ColoredBox>(find.byKey(ValueKey(key))).color;

Finder _heroAsset(Finder scene, String path) => _inScene(
  scene,
  find.byWidgetPredicate(
    (widget) =>
        widget is Image &&
        widget.image is AssetImage &&
        (widget.image as AssetImage).assetName == path,
    description: 'Image asset $path in team scene',
  ),
);

/// Scopes a finder to one team CARD. The `@name` caption also appears in the
/// roster cell below, so an unscoped find.text matches twice.
Finder _inCard(RaceTeam team, Finder matching) => find.descendant(
  of: find.byKey(ValueKey('team-card-${team.wireValue}')),
  matching: matching,
);

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

  testWidgets('team heroes reuse the moving Home scene and walking leader', (
    tester,
  ) async {
    await _pump(tester, _ScoreboardApi(), theme: AppThemeData.light());

    final scenes = tester.widgetList<HomeHeroScene>(find.byType(HomeHeroScene));
    expect(scenes, hasLength(2));
    expect(scenes.map((scene) => scene.groundHeight), everyElement(34));
    expect(scenes.map((scene) => scene.groundScrollSpeed), everyElement(26));
    expect(
      find.descendant(
        of: find.byType(TeamScoreboardCards),
        matching: find.byType(AnimatedCapybaraWithAccessories),
      ),
      findsNWidgets(2),
    );
    for (final scene in [_sceneA, _sceneB]) {
      expect(tester.widget(scene), isA<RepaintBoundary>());
    }
  });

  testWidgets('ground and leader advance at the locked 720ms cadence', (
    tester,
  ) async {
    await _pump(tester, _ScoreboardApi(), theme: AppThemeData.light());

    final startGround = _groundDx(tester, _sceneA);
    final startFrame = _animalFrame(tester, _sceneA);
    await tester.pump(const Duration(milliseconds: 121));
    expect(_groundDx(tester, _sceneA), lessThan(startGround));
    expect(_animalFrame(tester, _sceneA), isNot(startFrame));

    final animated = tester.widget<AnimatedCapybaraWithAccessories>(
      _inScene(_sceneA, find.byType(AnimatedCapybaraWithAccessories)),
    );
    expect(animated.stepDuration, const Duration(milliseconds: 720));
  });

  testWidgets('reduced motion freezes and runtime toggle resets both layers', (
    tester,
  ) async {
    final disabled = ValueNotifier<bool>(true);
    addTearDown(disabled.dispose);
    await _pump(
      tester,
      _ScoreboardApi(),
      theme: AppThemeData.light(),
      disableAnimations: disabled,
    );

    expect(_groundDx(tester, _sceneA), 0);
    expect(_animalFrame(tester, _sceneA), 0);
    final frozenCloud = _cloudLeft(tester, _sceneA);
    await tester.pump(const Duration(milliseconds: 900));
    expect(_groundDx(tester, _sceneA), 0);
    expect(_animalFrame(tester, _sceneA), 0);
    expect(_cloudLeft(tester, _sceneA), frozenCloud);

    disabled.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 121));
    expect(_groundDx(tester, _sceneA), lessThan(0));
    expect(_animalFrame(tester, _sceneA), isNot(0));
    expect(_cloudLeft(tester, _sceneA), isNot(frozenCloud));

    disabled.value = true;
    await tester.pump();
    expect(_groundDx(tester, _sceneA), 0);
    expect(_animalFrame(tester, _sceneA), 0);
    expect(_cloudLeft(tester, _sceneA), frozenCloud);
  });

  testWidgets('TickerMode mutes scene and sprite without changing layout', (
    tester,
  ) async {
    final tickerEnabled = ValueNotifier<bool>(true);
    addTearDown(tickerEnabled.dispose);
    await _pump(
      tester,
      _ScoreboardApi(),
      theme: AppThemeData.light(),
      tickerEnabled: tickerEnabled,
    );
    await tester.pump(const Duration(milliseconds: 121));

    tickerEnabled.value = false;
    await tester.pump();
    final ground = _groundDx(tester, _sceneA);
    final frame = _animalFrame(tester, _sceneA);
    final cloud = _cloudLeft(tester, _sceneA);
    final rect = tester.getRect(_sceneA);
    await tester.pump(const Duration(milliseconds: 900));
    expect(_groundDx(tester, _sceneA), ground);
    expect(_animalFrame(tester, _sceneA), frame);
    expect(_cloudLeft(tester, _sceneA), cloud);
    expect(tester.getRect(_sceneA), rect);
  });

  testWidgets('animated sprite API remains enabled by default', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AnimatedCapybaraWithAccessories(accessories: [], size: 80),
      ),
    );

    final dynamic sprite = tester.widget<AnimatedCapybaraWithAccessories>(
      find.byType(AnimatedCapybaraWithAccessories),
    );
    expect(sprite.animate, isTrue);
  });

  testWidgets('the scoreboard separates hero cards, momentum, and rosters', (
    tester,
  ) async {
    await _pump(tester, _ScoreboardApi());

    final scoreboardShell = find.byKey(const ValueKey('team-scoreboard-shell'));
    final standingsShell = find.byKey(const ValueKey('team-standings-shell'));
    final powerupsHeader = find.text('POWERUPS');
    final standingsHeader = find.text('STANDINGS');
    expect(powerupsHeader, findsOneWidget);
    expect(find.byType(TeamVsChips), findsOneWidget);
    expect(find.byType(TeamScoreboardCards), findsOneWidget);
    expect(_banner, findsOneWidget);
    expect(scoreboardShell, findsOneWidget);
    expect(standingsHeader, findsOneWidget);
    expect(standingsShell, findsOneWidget);
    expect(_cardA, findsOneWidget);
    expect(_cardB, findsOneWidget);
    expect(
      tester.getTopLeft(powerupsHeader).dy,
      lessThan(tester.getTopLeft(scoreboardShell).dy),
      reason: 'POWERUPS should precede the team scoreboard on race detail',
    );
    expect(
      tester.getTopLeft(_cardA).dy,
      lessThan(tester.getTopLeft(_banner).dy),
    );
    expect(
      tester.getBottomLeft(_banner).dy,
      lessThan(tester.getTopLeft(standingsHeader).dy),
    );
    expect(
      tester.getBottomLeft(scoreboardShell).dy -
          tester.getBottomLeft(_banner).dy,
      lessThanOrEqualTo(10),
    );
    expect(
      tester.getBottomLeft(standingsHeader).dy,
      lessThanOrEqualTo(tester.getTopLeft(standingsShell).dy),
    );
    expect(
      find.descendant(
        of: scoreboardShell,
        matching: find.byKey(const ValueKey('team-cell-user-1')),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: standingsShell,
        matching: find.byKey(const ValueKey('team-cell-user-1')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _cardA,
        matching: find.byKey(const ValueKey('team-cell-user-1')),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: _cardB,
        matching: find.byKey(const ValueKey('team-cell-u3')),
      ),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('team-lane-TEAM_A')), findsNothing);
    expect(find.byKey(const ValueKey('team-lane-TEAM_B')), findsNothing);
    expect(find.text('12,340'), findsOneWidget);
    expect(find.text('11,900'), findsOneWidget);
  });

  testWidgets(
    'day hero scenes use the Home sky and ground with distinct crops',
    (tester) async {
      await _pump(tester, _ScoreboardApi(), theme: AppThemeData.light());

      expect(_sceneA, findsOneWidget);
      expect(_sceneB, findsOneWidget);
      expect(
        _heroAsset(_sceneA, 'assets/images/home_hero_sky.png'),
        findsOneWidget,
      );
      expect(
        _heroAsset(_sceneB, 'assets/images/home_hero_sky.png'),
        findsOneWidget,
      );
      expect(
        _heroAsset(_sceneA, 'assets/images/home_hero_ground.png'),
        findsAtLeastNWidgets(1),
      );
      final scenes = tester.widgetList<HomeHeroScene>(
        find.byType(HomeHeroScene),
      );
      expect(scenes.first.skyAlignment, const Alignment(-0.45, 1));
      expect(scenes.last.skyAlignment, const Alignment(0.45, 1));
      final colors = AppColors.of(tester.element(_sceneA));
      expect(
        _coloredBoxColor(tester, 'team-hero-parchment-wash-TEAM_A'),
        colors.parchmentLight.withValues(alpha: 0.24),
      );
      expect(
        _coloredBoxColor(tester, 'team-hero-team-wash-TEAM_A'),
        TeamRace.colorLight(
          RaceTeam.teamA,
          tester.element(_sceneA),
        ).withValues(alpha: 0.10),
      );
      expect(
        _coloredBoxColor(tester, 'team-hero-team-wash-TEAM_B'),
        TeamRace.colorLight(
          RaceTeam.teamB,
          tester.element(_sceneB),
        ).withValues(alpha: 0.10),
      );
    },
  );

  testWidgets('night hero scenes use night Home art and caption scrims', (
    tester,
  ) async {
    await _pump(tester, _ScoreboardApi(), theme: AppThemeData.night());

    expect(
      _heroAsset(_sceneA, 'assets/images/home_hero_sky_night.png'),
      findsOneWidget,
    );
    expect(
      _heroAsset(_sceneB, 'assets/images/home_hero_sky_night.png'),
      findsOneWidget,
    );
    expect(
      _heroAsset(_sceneA, 'assets/images/home_hero_ground_night.png'),
      findsAtLeastNWidgets(1),
    );
    final captionScrims = find.descendant(
      of: find.byType(TeamScoreboardCards),
      matching: find.byKey(const ValueKey('team-hero-caption-scrim')),
    );
    expect(captionScrims, findsNWidgets(2));
    for (final element in captionScrims.evaluate()) {
      final decoration = (element.widget as Container).decoration!;
      expect(decoration, isA<BoxDecoration>());
      expect(
        (decoration as BoxDecoration).color,
        AppColors.of(element).parchment.withValues(alpha: 0.92),
      );
    }
    final colors = AppColors.of(tester.element(_sceneA));
    expect(
      _coloredBoxColor(tester, 'team-hero-parchment-wash-TEAM_A'),
      colors.parchmentLight.withValues(alpha: 0.14),
    );
    expect(
      _coloredBoxColor(tester, 'team-hero-team-wash-TEAM_A'),
      TeamRace.colorLight(
        RaceTeam.teamA,
        tester.element(_sceneA),
      ).withValues(alpha: 0.08),
    );
    expect(
      _coloredBoxColor(tester, 'team-hero-team-wash-TEAM_B'),
      TeamRace.colorLight(
        RaceTeam.teamB,
        tester.element(_sceneB),
      ).withValues(alpha: 0.08),
    );
    for (final caption in tester.widgetList<Text>(
      find.descendant(
        of: find.byType(TeamScoreboardCards),
        matching: find.byWidgetPredicate(
          (widget) => widget is Text && widget.data?.startsWith('@') == true,
        ),
      ),
    )) {
      expect(caption.style?.color, colors.textDark);
    }
  });

  testWidgets('course art is decorative while leader names stay semantic', (
    tester,
  ) async {
    await _pump(tester, _ScoreboardApi(), theme: AppThemeData.light());

    for (final scene in [_sceneA, _sceneB]) {
      final sky = _heroAsset(scene, 'assets/images/home_hero_sky.png');
      expect(sky, findsOneWidget);
      expect(
        _inScene(
          scene,
          find.ancestor(of: sky, matching: find.byType(ExcludeSemantics)),
        ),
        findsAtLeastNWidgets(1),
      );
    }
    Finder leaderSemantics(String label) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
      description: 'Semantics(label: $label)',
    );
    expect(leaderSemantics('@Hill Climber'), findsOneWidget);
    expect(leaderSemantics('@Sneaky Pete'), findsOneWidget);
  });

  for (final width in [320.0, 375.0, 390.0, 430.0]) {
    testWidgets('hero scenes stay equal and bounded at ${width.toInt()}px', (
      tester,
    ) async {
      await _pump(
        tester,
        _ScoreboardApi(),
        theme: AppThemeData.light(),
        width: width,
      );

      expect(tester.takeException(), isNull);
      final cardA = tester.getRect(_cardA);
      final cardB = tester.getRect(_cardB);
      final sceneA = tester.getRect(_sceneA);
      final sceneB = tester.getRect(_sceneB);
      expect(cardA.size, cardB.size);
      expect(sceneA.size, sceneB.size);
      expect(sceneA.height, 148);
      expect(sceneB.height, 148);
      expect(cardA.contains(sceneA.topLeft), isTrue);
      expect(
        cardA.contains(sceneA.bottomRight - const Offset(0.01, 0.01)),
        isTrue,
      );
      expect(cardB.contains(sceneB.topLeft), isTrue);
      expect(
        cardB.contains(sceneB.bottomRight - const Offset(0.01, 0.01)),
        isTrue,
      );
    });
  }

  testWidgets('empty teams keep both scenes and calm empty copy', (
    tester,
  ) async {
    await _pump(
      tester,
      _ScoreboardApi(emptyParticipants: true, myTeam: null),
      theme: AppThemeData.light(),
    );

    expect(_sceneA, findsOneWidget);
    expect(_sceneB, findsOneWidget);
    expect(_inScene(_sceneA, find.byType(HomeHeroScene)), findsOneWidget);
    expect(_inScene(_sceneB, find.byType(HomeHeroScene)), findsOneWidget);
    expect(
      find.descendant(of: _sceneA, matching: find.text('No one yet')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _sceneB, matching: find.text('No one yet')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(TeamScoreboardCards),
        matching: find.byType(AnimatedCapybaraWithAccessories),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an all-stealthed side exposes no sprite or username', (
    tester,
  ) async {
    await _pump(
      tester,
      _ScoreboardApi(allTeamBStealthed: true),
      theme: AppThemeData.light(),
    );

    expect(_inScene(_sceneB, find.text('No one yet')), findsOneWidget);
    expect(
      _inScene(_sceneB, find.byType(AnimatedCapybaraWithAccessories)),
      findsNothing,
    );
    expect(_inScene(_sceneB, find.textContaining('@')), findsNothing);
    expect(find.text('Sneaky Pete'), findsNothing);
    expect(find.text('Marsh Mellow'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'progress polling swaps leader without resetting team scene state',
    (tester) async {
      final api = _ScoreboardApi(pollLeaderSwap: true, pollFlipTotals: true);
      await _pump(tester, api, theme: AppThemeData.light());
      await tester.pump(const Duration(milliseconds: 500));

      final homeSceneA = find.byKey(const ValueKey('team-home-hero-TEAM_A'));
      final homeSceneB = find.byKey(const ValueKey('team-home-hero-TEAM_B'));
      final stateABefore = tester.state(homeSceneA);
      final stateBBefore = tester.state(homeSceneB);
      expect(_leadingA, findsOneWidget);
      expect(_leadingB, findsNothing);
      expect(_inScene(_sceneA, find.text('@Hill Climber')), findsOneWidget);
      expect(_inScene(_sceneA, find.text('@Fresh Leader')), findsNothing);

      await tester.pump(const Duration(seconds: 30));
      await tester.pump();

      expect(api.progressCalls, greaterThanOrEqualTo(2));
      expect(tester.state(homeSceneA), same(stateABefore));
      expect(tester.state(homeSceneB), same(stateBBefore));
      expect(_leadingA, findsNothing);
      expect(_leadingB, findsOneWidget);
      expect(_inScene(_sceneA, find.text('@Fresh Leader')), findsOneWidget);
      expect(_inScene(_sceneA, find.text('@Hill Climber')), findsNothing);
      expect(
        _inScene(_sceneA, find.byType(AnimatedCapybaraWithAccessories)),
        findsOneWidget,
      );
    },
  );

  testWidgets('long leader caption ellipsizes inside its scene', (
    tester,
  ) async {
    const longName = 'Hill Climber With A Very Long Display Name For Bounds';
    await _pump(
      tester,
      _ScoreboardApi(teamALeaderName: longName),
      theme: AppThemeData.light(),
      width: 320,
    );

    final captionFinder = _inCard(RaceTeam.teamA, find.text('@$longName'));
    final caption = tester.widget<Text>(captionFinder);
    expect(caption.maxLines, 1);
    expect(caption.overflow, TextOverflow.ellipsis);
    final captionRect = tester.getRect(captionFinder);
    final sceneRect = tester.getRect(_sceneA);
    final summaryTop = tester
        .getTopLeft(_inCard(RaceTeam.teamA, find.text('Swift Capys')))
        .dy;
    expect(sceneRect.contains(captionRect.topLeft), isTrue);
    expect(sceneRect.contains(captionRect.bottomRight), isTrue);
    expect(captionRect.bottom, lessThanOrEqualTo(summaryTop));
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide cosmetics and non-default animal stay in the 320px scene', (
    tester,
  ) async {
    await _pump(
      tester,
      _ScoreboardApi(teamALeaderHasWideCosmetics: true),
      theme: AppThemeData.light(),
      width: 320,
    );

    final spriteFinder = find.descendant(
      of: _sceneA,
      matching: find.byType(CapybaraSpriteWithAccessories),
    );
    final sprite = tester.widget<CapybaraSpriteWithAccessories>(spriteFinder);
    expect(sprite.animal, 'corgi_puppy');
    expect(sprite.accessories.single['assetKey'], 'angel_wings');
    final spriteRect = tester.getRect(spriteFinder);
    final sceneRect = tester.getRect(_sceneA);
    expect(sceneRect.contains(spriteRect.topLeft), isTrue);
    expect(sceneRect.contains(spriteRect.bottomRight), isTrue);
    expect(spriteRect.width, lessThanOrEqualTo(108));
    expect(spriteRect.height, closeTo(spriteRect.width, 0.001));

    final accessoryFinder = find.descendant(
      of: spriteFinder,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is RemoteOrBundledAccessoryImage &&
            widget.remoteKey == 'angel_wings',
      ),
    );
    final accessoryRect = _transformedRect(tester, accessoryFinder);
    expect(sceneRect.contains(accessoryRect.topLeft), isTrue);
    expect(sceneRect.contains(accessoryRect.bottomRight), isTrue);
    await tester.pump(const Duration(milliseconds: 121));
    final movingAccessoryRect = _transformedRect(tester, accessoryFinder);
    expect(sceneRect.contains(movingAccessoryRect.topLeft), isTrue);
    expect(sceneRect.contains(movingAccessoryRect.bottomRight), isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final animal in <String?>[null, 'corgi_puppy', 'turtle']) {
    testWidgets('${animal ?? 'capybara'} uses the exact fixed Home baseline', (
      tester,
    ) async {
      await _pump(
        tester,
        _ScoreboardApi(teamAAnimal: animal),
        theme: AppThemeData.light(),
        width: 320,
      );

      final animatedFinder = _inScene(
        _sceneA,
        find.byType(AnimatedCapybaraWithAccessories),
      );
      for (var sample = 0; sample < 4; sample++) {
        final animated = tester.widget<AnimatedCapybaraWithAccessories>(
          animatedFinder,
        );
        final sceneRect = tester.getRect(_sceneA);
        final spriteRect = tester.getRect(animatedFinder);
        final expectedBottom = 34 - 4 - animated.size * 0.22;
        expect(
          sceneRect.bottom - spriteRect.bottom,
          closeTo(expectedBottom, .01),
        );
        expect(animated.size, inInclusiveRange(48, 108));
        expect(_animalFrame(tester, _sceneA), inInclusiveRange(0, 7));
        await tester.pump(const Duration(milliseconds: 91));
      }
    });
  }

  testWidgets('fractional rotated behind art stays within transformed bounds', (
    tester,
  ) async {
    await _pump(
      tester,
      _ScoreboardApi(
        teamAAccessories: const [
          {
            'slot': 'BACK',
            'assetKey': 'angel_wings',
            'renderMetadata': {
              'offsetX': -.08,
              'offsetY': -.12,
              'rotation': .12,
              'scale': 1.2,
              'renderLayer': 'behind',
            },
          },
        ],
      ),
      theme: AppThemeData.light(),
      width: 320,
    );

    final scene = tester.getRect(_sceneA);
    final image = _inScene(
      _sceneA,
      find.byWidgetPredicate(
        (widget) =>
            widget is RemoteOrBundledAccessoryImage &&
            widget.remoteKey == 'angel_wings',
      ),
    );
    for (var sample = 0; sample < 4; sample++) {
      final bounds = _transformedRect(tester, image);
      expect(scene.contains(bounds.topLeft), isTrue);
      expect(scene.contains(bounds.bottomRight), isTrue);
      await tester.pump(const Duration(milliseconds: 91));
    }
  });

  testWidgets('malformed accessories omit safely and keep a grounded leader', (
    tester,
  ) async {
    await _pump(
      tester,
      _ScoreboardApi(
        teamAAccessories: [
          {'slot': 7, 'assetKey': 'angel_wings'},
          {'slot': 'BACK', 'assetKey': false},
          {
            'slot': 'BACK',
            'assetKey': 'nan',
            'renderMetadata': {'offsetX': double.nan},
          },
          {
            'slot': 'BACK',
            'assetKey': 'infinity',
            'renderMetadata': {'rotation': double.infinity},
          },
          {
            'slot': 'BACK',
            'assetKey': 'huge-offset',
            'renderMetadata': {'offsetY': 513},
          },
          {
            'slot': 'BACK',
            'assetKey': 'huge-scale',
            'renderMetadata': {'scale': 9},
          },
          {
            'slot': 'BACK',
            'assetKey': 'zero-scale',
            'renderMetadata': {'scale': 0},
          },
          {
            'slot': 'BACK',
            'assetKey': 'negative-scale',
            'renderMetadata': {'scale': -1},
          },
          {
            'slot': 'BACK',
            'assetKey': 'too-many-frames',
            'renderMetadata': {'animationFrames': 65},
          },
          {
            'slot': 'BACK',
            'assetKey': 'uncontainable',
            'renderMetadata': {
              'offsetX': 100,
              'scale': 8,
              'renderLayer': 'behind',
            },
          },
        ],
      ),
      theme: AppThemeData.light(),
      width: 320,
    );

    expect(tester.takeException(), isNull);
    final animatedFinder = _inScene(
      _sceneA,
      find.byType(AnimatedCapybaraWithAccessories),
    );
    final animated = tester.widget<AnimatedCapybaraWithAccessories>(
      animatedFinder,
    );
    expect(animated.size, inInclusiveRange(48, 108));
    expect(animated.size.isFinite, isTrue);
    expect(animated.accessories, isEmpty);
    final sceneRect = tester.getRect(_sceneA);
    final spriteRect = tester.getRect(animatedFinder);
    expect(
      sceneRect.bottom - spriteRect.bottom,
      closeTo(34 - 4 - animated.size * .22, .01),
    );
    expect(find.text('@Hill Climber'), findsWidgets);
  });

  testWidgets('leader nameplate sits above an animal grounded on the course', (
    tester,
  ) async {
    await _pump(
      tester,
      _ScoreboardApi(teamALeaderHasWideCosmetics: true),
      theme: AppThemeData.light(),
      width: 320,
    );

    final caption = _inCard(RaceTeam.teamA, find.text('@Hill Climber'));
    final sprite = find.descendant(
      of: _sceneA,
      matching: find.byType(CapybaraSpriteWithAccessories),
    );
    final sceneRect = tester.getRect(_sceneA);
    final captionRect = tester.getRect(caption);
    final spriteRect = tester.getRect(sprite);
    expect(captionRect.bottom, lessThanOrEqualTo(spriteRect.top));
    expect(
      spriteRect.bottom,
      greaterThanOrEqualTo(sceneRect.top + sceneRect.height * 0.84),
    );
    expect(spriteRect.bottom, lessThanOrEqualTo(sceneRect.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the leading outline follows the higher BACKEND total', (
    tester,
  ) async {
    // Team B leads on the honest team block (20,000) even though the visible
    // planks sum higher for A — the ribbon must follow the rendered totals.
    await _pump(tester, _ScoreboardApi(teamATotal: 9000, teamBTotal: 20000));

    expect(_leadingB, findsOneWidget);
    expect(_leadingA, findsNothing);
  });

  testWidgets('hero and roster cards carry the column state without a slab', (
    tester,
  ) async {
    await _pump(tester, _ScoreboardApi(teamATotal: 20000, teamBTotal: 9000));

    final leading = tester.widget<Container>(_cardA);
    final trailing = tester.widget<Container>(_cardB);
    final leadingDecoration = leading.decoration! as BoxDecoration;
    final trailingDecoration = trailing.decoration! as BoxDecoration;
    final gold = AppColors.of(tester.element(_cardA)).medalGold;
    expect(leadingDecoration.color, isNot(trailingDecoration.color));
    expect(leadingDecoration.border!.top.color, gold);
    expect(trailingDecoration.border!.top.color, isNot(gold));
    expect(leadingDecoration.boxShadow, isNotEmpty);
    expect(trailingDecoration.boxShadow, isNull);

    final leadingRacer = tester.widget<Container>(
      find.byKey(const ValueKey('team-cell-user-1')),
    );
    final trailingRacer = tester.widget<Container>(
      find.byKey(const ValueKey('team-cell-u3')),
    );
    final leadingRacerDecoration = leadingRacer.decoration! as BoxDecoration;
    final trailingRacerDecoration = trailingRacer.decoration! as BoxDecoration;
    expect(leadingRacerDecoration.border!.top.color, gold);
    expect(trailingRacerDecoration.border!.top.color, isNot(gold));
    expect(find.byKey(const ValueKey('team-lane-TEAM_A')), findsNothing);
    expect(find.byKey(const ValueKey('team-lane-TEAM_B')), findsNothing);
    expect(
      find.descendant(of: _cardB, matching: find.byType(Opacity)),
      findsNothing,
    );
  });

  testWidgets('the portrait pictures that side\'s top scorer', (tester) async {
    await _pump(tester, _ScoreboardApi());

    // Hill Climber (9,000) outscores the viewer (6,200) on Team A, so the
    // card portrait is captioned with them, not with the viewer.
    expect(_inCard(RaceTeam.teamA, find.text('@Hill Climber')), findsOneWidget);
    expect(_inCard(RaceTeam.teamA, find.text('@Trail Walker')), findsNothing);
    // Team B's card is captioned with its own top scorer.
    expect(_inCard(RaceTeam.teamB, find.text('@Sneaky Pete')), findsOneWidget);
  });

  testWidgets('the banner cheers a viewer on the leading side', (tester) async {
    // Viewer on Team A, which leads 12,340 - 11,900.
    await _pump(tester, _ScoreboardApi());

    expect(find.textContaining('Keep it up!'), findsOneWidget);
    expect(find.textContaining('440'), findsOneWidget);
    expect(find.textContaining('Push!'), findsNothing);
  });

  testWidgets('the banner pushes a viewer on the trailing side', (
    tester,
  ) async {
    // Same scoreline, viewer moved to the trailing side. Deliberately a
    // separate test: re-pumping RaceDetailScreen in one body reuses the State
    // (didUpdateWidget, not initState), so the second scenario never refetches.
    await _pump(tester, _ScoreboardApi(myTeam: 'TEAM_B'));

    expect(find.textContaining('Push!'), findsOneWidget);
    expect(find.textContaining('440'), findsOneWidget);
    expect(find.textContaining('Keep it up!'), findsNothing);
  });

  testWidgets('a spectator gets neutral third-person copy', (tester) async {
    await _pump(tester, _ScoreboardApi(myTeam: null));

    expect(find.textContaining('leads by'), findsOneWidget);
    expect(find.textContaining('Keep it up!'), findsNothing);
    expect(find.textContaining('Push!'), findsNothing);
  });

  testWidgets('a tie crowns neither side', (tester) async {
    await _pump(tester, _ScoreboardApi(teamATotal: 9000, teamBTotal: 9000));

    expect(_leadingA, findsNothing);
    expect(_leadingB, findsNothing);
    expect(find.textContaining('Dead even'), findsOneWidget);
    final a = tester.widget<Container>(_cardA).decoration! as BoxDecoration;
    final b = tester.widget<Container>(_cardB).decoration! as BoxDecoration;
    expect(a.boxShadow, isNull);
    expect(b.boxShadow, isNull);
  });

  testWidgets('an unknowable total dashes out, crowns no one, hides the '
      'banner', (tester) async {
    // No `teams` block + a stealthed member on B => B's total is genuinely
    // unknown. Rendering 5,000 (the visible plank sum) would be a confident
    // undercount, and crowning A off it would compound the lie.
    await _pump(
      tester,
      _ScoreboardApi(stealthTeamB: true, omitTeamsBlock: true),
    );

    expect(find.text('—'), findsOneWidget);
    expect(_leadingA, findsNothing);
    expect(_leadingB, findsNothing);
    expect(_banner, findsNothing);
    expect(find.textContaining('ahead'), findsNothing);
    final a = tester.widget<Container>(_cardA).decoration! as BoxDecoration;
    final b = tester.widget<Container>(_cardB).decoration! as BoxDecoration;
    expect(a.boxShadow, isNull);
    expect(b.boxShadow, isNull);
  });

  testWidgets('a stealthed member keeps the honest total but leaves the '
      'portrait alone', (tester) async {
    // WITH the teams block the totals stay honest (11,900 includes the hidden
    // steps), but the portrait must still skip the stealthed racer rather than
    // leaking their name and cosmetics.
    await _pump(tester, _ScoreboardApi(stealthTeamB: true));

    expect(find.text('11,900'), findsOneWidget);
    expect(_inCard(RaceTeam.teamB, find.text('@Marsh Mellow')), findsOneWidget);
    expect(find.text('@Sneaky Pete'), findsNothing);
  });

  test(
    'demo and tab-tutorial fixtures remain on the solo standings branch',
    () {
      final now = DateTime(2026, 8, 11, 12);
      final demo = DemoRaceEngine(
        myUserId: 'demo-me',
        myDisplayName: 'Demo Me',
        startedAt: now,
        clock: () => now,
      );

      expect(TeamRace.isTeamRace(demo.raceDetails(now)), isFalse);
      expect(TeamRace.isTeamRace(tutorialPreviewRaceDetail()), isFalse);
      expect(
        demo.raceProgress(now)['participants'],
        everyElement(isNot(contains('team'))),
      );
      expect(
        tutorialPreviewRaceProgress()['participants'],
        everyElement(isNot(contains('team'))),
      );
    },
  );
}
