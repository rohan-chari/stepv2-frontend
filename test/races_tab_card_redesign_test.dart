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

Future<void> _pump(
  WidgetTester tester, {
  required Map<String, dynamic> race,
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
            'active': [race],
            'pending': const [],
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

  testWidgets(
    'race ticket leads with first-place racer and ends with a navigation arrow',
    (tester) async {
      await _pump(tester, race: _activeRace());

      final avatarFinder = find.byKey(const Key('race-leader-avatar-race-1'));
      final arrowFinder = find.byKey(const Key('race-card-arrow-race-1'));
      expect(avatarFinder, findsOneWidget);
      expect(arrowFinder, findsOneWidget);

      final avatar = tester.widget<RacerAvatar>(avatarFinder);
      expect(avatar.rank, 1);
      expect(avatar.accessories.single['assetKey'], 'trail_hat');
      expect(avatar.animal, isNull);
      expect(avatar.size, greaterThanOrEqualTo(48));
      expect(avatar.showMedalRing, isFalse);
      expect(
        find.descendant(
          of: avatarFinder,
          matching: find.byType(CapybaraSpriteWithAccessories),
        ),
        findsOneWidget,
      );

      final avatarRect = tester.getRect(avatarFinder);
      final titleRect = tester.getRect(find.text('Sunset Sprint'));
      final arrowRect = tester.getRect(arrowFinder);
      expect(avatarRect.right, lessThan(titleRect.left));
      expect(titleRect.right, lessThan(arrowRect.left));
    },
  );

  testWidgets('time, boxes, powerups, and effects use the larger card scale', (
    tester,
  ) async {
    await _pump(tester, race: _activeRace());

    final time = tester.widget<Text>(find.textContaining('left').first);
    expect(time.style?.fontSize, greaterThanOrEqualTo(15));

    final crates = tester.widgetList<CrateIcon>(find.byType(CrateIcon));
    expect(crates, isNotEmpty);
    expect(crates.every((crate) => crate.size >= 22), isTrue);

    final powerups = tester.widgetList<PowerupIcon>(find.byType(PowerupIcon));
    expect(powerups, isNotEmpty);
    expect(powerups.every((powerup) => powerup.size >= 18), isTrue);
  });

  testWidgets('missing additive leader data falls back without crashing', (
    tester,
  ) async {
    await _pump(tester, race: _activeRace(includeLeader: false));

    final avatar = tester.widget<RacerAvatar>(
      find.byKey(const Key('race-leader-avatar-race-1')),
    );
    expect(avatar.accessories, isEmpty);
    expect(avatar.animal, isNull);
    expect(find.text('Sunset Sprint'), findsOneWidget);
  });

  testWidgets(
    'dense ticket keeps portrait and arrow inside a narrow high-text-scale card',
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
      final avatar = tester.getRect(
        find.byKey(const Key('race-leader-avatar-race-1')),
      );
      final arrow = tester.getRect(
        find.byKey(const Key('race-card-arrow-race-1')),
      );
      expect(surface.left, 10);
      expect(surface.right, 310);
      expect(surface.contains(avatar.topLeft), isTrue);
      expect(surface.contains(avatar.bottomRight), isTrue);
      expect(surface.contains(arrow.topLeft), isTrue);
      expect(surface.contains(arrow.bottomRight), isTrue);
    },
  );
}
