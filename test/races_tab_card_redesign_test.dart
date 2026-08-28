import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/races_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/widgets/home_course_track.dart'
    show CapybaraSpriteWithAccessories;
import 'package:step_tracker/widgets/powerup_icon.dart';
import 'package:step_tracker/widgets/race_ui.dart' show RacerAvatar;
import 'package:step_tracker/widgets/spinning_crate.dart';

Future<void> _noop() async {}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'viewer',
    'auth_display_name': 'Trail Walker',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

/// `leader` is still served by the live backend this round (its removal is a
/// separate, later backend deploy), so the fixture keeps sending it — the row
/// must simply ignore it now.
Map<String, dynamic> _activeRace({bool includeLeader = true}) => {
  'id': 'race-1',
  'name': 'Sunset Sprint',
  'status': 'ACTIVE',
  'endsAt': DateTime.now()
      .add(const Duration(hours: 3, minutes: 20))
      .toUtc()
      .toIso8601String(),
  'participantCount': 4,
  'myPlacement': 2,
  'placementPrivacyActive': false,
  'slotItems': const [
    {'id': 'held-1', 'type': 'RUNNERS_HIGH', 'status': 'HELD'},
  ],
  'mysteryBoxCount': 1,
  'queuedBoxCount': 1,
  'myActiveEffects': const [
    {'type': 'LEG_CRAMP', 'sourceUserId': 'rival'},
  ],
  if (includeLeader)
    'leader': const {
      'userId': 'leader-1',
      'displayName': 'Maya Chen',
      'animal': null,
      'accessories': [
        {
          'id': 'hat-1',
          'sku': 'TRAIL_HAT',
          'name': 'Trail Hat',
          'slot': 'HEAD',
          'assetKey': 'trail_hat',
          'renderMetadata': <String, dynamic>{},
        },
      ],
    },
};

Map<String, dynamic> _pendingRace() => {
  'id': 'race-2',
  'name': 'Dawn Patrol',
  'status': 'PENDING',
  'maxDurationDays': 5,
  'participantCount': 3,
  'isCreator': true,
  'myPlacementHidden': true,
};

Future<void> _pump(
  WidgetTester tester, {
  Map<String, dynamic>? race,
  Map<String, dynamic>? pendingRace,
  double width = 390,
  double textScaleFactor = 1,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScaleFactor;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RacesTab(
          authService: await _auth(),
          racesData: {
            'active': [?race],
            'pending': [?pendingRace],
            'completed': const [],
          },
          friendsSteps: const [],
          onRacesChanged: _noop,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Supersedes the former "race ticket leads with first-place racer" test:
  // the leading rank-1 RacerAvatar was removed because it reads as the
  // viewer's own racer.
  testWidgets('race ticket renders no leading racer avatar', (tester) async {
    await _pump(tester, race: _activeRace());

    expect(find.byKey(const Key('race-leader-avatar-race-1')), findsNothing);
    // No race row on this screen renders a racer portrait at all (no
    // tournaments are in the fixture, so any hit would come from the race
    // row itself).
    expect(find.byType(RacerAvatar), findsNothing);
    expect(find.byType(CapybaraSpriteWithAccessories), findsNothing);

    final arrowFinder = find.byKey(const Key('race-card-arrow-race-1'));
    expect(arrowFinder, findsOneWidget);

    // The name now starts at the card's content edge instead of behind a
    // 52px portrait + 12px gutter.
    final surface = tester.getRect(
      find.byKey(const Key('race-card-surface-race-1')),
    );
    final titleRect = tester.getRect(find.text('Sunset Sprint'));
    expect(titleRect.left - surface.left, lessThan(30));
    expect(titleRect.right, lessThan(tester.getRect(arrowFinder).left));
  });

  // Supersedes the former avatar-geometry ordering assertion
  // (avatarRect.right < titleRect.left): the placement chip is now the
  // element whose position relative to the name is under test.
  testWidgets('placement chip sits level with the race name', (tester) async {
    await _pump(tester, race: _activeRace());

    final chipFinder = find.byKey(const Key('race-placement-chip-race-1'));
    expect(chipFinder, findsOneWidget);
    expect(
      find.descendant(of: chipFinder, matching: find.text('2ND PLACE')),
      findsOneWidget,
    );

    final chipRect = tester.getRect(chipFinder);
    final titleRect = tester.getRect(find.text('Sunset Sprint'));
    // Level with the name: to its right, sharing the same line.
    expect(chipRect.left, greaterThanOrEqualTo(titleRect.right));
    expect((chipRect.center.dy - titleRect.center.dy).abs(), lessThan(8));
    // ...and inside the same header row as the name.
    expect(
      find.descendant(
        of: find.byKey(const Key('race-card-header-race-1')),
        matching: chipFinder,
      ),
      findsOneWidget,
    );
  });

  testWidgets('time label renders exactly once, beneath the name row', (
    tester,
  ) async {
    await _pump(tester, race: _activeRace());

    final timeFinder = find.byKey(const Key('race-time-label-race-1'));
    expect(timeFinder, findsOneWidget);
    // The old card rendered the label twice (inline for ACTIVE, again in the
    // trailing column for other statuses).
    expect(find.textContaining('left'), findsOneWidget);

    final timeRect = tester.getRect(timeFinder);
    final chipRect = tester.getRect(
      find.byKey(const Key('race-placement-chip-race-1')),
    );
    final titleRect = tester.getRect(find.text('Sunset Sprint'));
    expect(timeRect.top, greaterThanOrEqualTo(chipRect.bottom - 1));
    expect(timeRect.left, lessThan(titleRect.left + 4));
  });

  testWidgets('non-active rows render one time label under a hidden chip', (
    tester,
  ) async {
    await _pump(tester, pendingRace: _pendingRace());
    // The personal list defaults to the ACTIVE shelf.
    await tester.tap(find.byKey(const Key('personal-state-pending')));
    await tester.pump(const Duration(milliseconds: 200));

    final chipFinder = find.byKey(const Key('race-placement-chip-race-2'));
    expect(chipFinder, findsOneWidget);
    expect(
      find.descendant(of: chipFinder, matching: find.text('??? PLACE')),
      findsOneWidget,
    );

    final timeFinder = find.byKey(const Key('race-time-label-race-2'));
    expect(timeFinder, findsOneWidget);
    expect(find.text('5d race'), findsOneWidget);
    expect(find.byType(RacerAvatar), findsNothing);

    final timeRect = tester.getRect(timeFinder);
    final chipRect = tester.getRect(chipFinder);
    expect(timeRect.top, greaterThanOrEqualTo(chipRect.bottom - 1));
    // The status badge stays on the trailing edge.
    expect(find.text('SETUP'), findsOneWidget);
  });

  testWidgets('time, boxes, powerups, and effects use the larger card scale', (
    tester,
  ) async {
    await _pump(tester, race: _activeRace());

    final time = tester.widget<Text>(
      find.byKey(const Key('race-time-label-race-1')),
    );
    expect(time.style?.fontSize, greaterThanOrEqualTo(15));

    final crates = tester.widgetList<CrateIcon>(find.byType(CrateIcon));
    expect(crates, isNotEmpty);
    expect(crates.every((crate) => crate.size >= 22), isTrue);

    final powerups = tester.widgetList<PowerupIcon>(find.byType(PowerupIcon));
    expect(powerups, isNotEmpty);
    expect(powerups.every((powerup) => powerup.size >= 18), isTrue);
  });

  // Supersedes the former "missing additive leader data falls back without
  // crashing" test: the row no longer reads `leader` at all, so a payload
  // with or without it must render identically.
  testWidgets('payload without leader renders the row unchanged', (
    tester,
  ) async {
    await _pump(tester, race: _activeRace(includeLeader: false));

    expect(tester.takeException(), isNull);
    expect(find.text('Sunset Sprint'), findsOneWidget);
    expect(find.byType(RacerAvatar), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('race-placement-chip-race-1')),
        matching: find.text('2ND PLACE'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('race-time-label-race-1')), findsOneWidget);
  });

  // Overflow guard kept from the previous suite, re-pointed at the new
  // leading content (name + placement chip) now that the portrait is gone.
  testWidgets(
    'dense ticket keeps name, chip and arrow inside a narrow high-text-scale card',
    (tester) async {
      await _pump(
        tester,
        width: 320,
        textScaleFactor: 1.5,
        race: {
          ..._activeRace(),
          'name': 'The Extremely Long Neighborhood Sunset Sprint',
        },
      );

      expect(tester.takeException(), isNull);
      final surface = tester.getRect(
        find.byKey(const Key('race-card-surface-race-1')),
      );
      final title = tester.getRect(find.textContaining('Neighborhood'));
      final chip = tester.getRect(
        find.byKey(const Key('race-placement-chip-race-1')),
      );
      final arrow = tester.getRect(
        find.byKey(const Key('race-card-arrow-race-1')),
      );
      expect(surface.left, 10);
      expect(surface.right, 310);
      expect(surface.contains(title.topLeft), isTrue);
      expect(surface.contains(chip.topLeft), isTrue);
      expect(surface.contains(chip.bottomRight), isTrue);
      expect(surface.contains(arrow.topLeft), isTrue);
      expect(surface.contains(arrow.bottomRight), isTrue);
    },
  );
}
