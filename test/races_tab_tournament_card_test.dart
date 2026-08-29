import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/loadable.dart';
import 'package:step_tracker/screens/tabs/races_tab.dart';
import 'package:step_tracker/screens/tournament_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/tutorial/tutorial_preview_data.dart';
import 'package:step_tracker/tutorial/tutorial_real_screens.dart';
import 'package:step_tracker/tutorial/tutorial_screen.dart'
    show TutorialMockPage;
import 'package:step_tracker/widgets/race_ui.dart' show RacerAvatar;

Future<void> _noop() async {}

class _NavigationObserver extends NavigatorObserver {
  Route<dynamic>? pushedRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoute = route;
    super.didPush(route, previousRoute);
  }
}

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

Map<String, dynamic> _activeTournament({bool includeIdentity = true}) => {
  'id': 'tournament-active',
  'name': 'The Extremely Long Eight Racer Tournament Name',
  'status': 'ACTIVE',
  'bracketSize': 8,
  'currentRound': 1,
  'totalRounds': 3,
  'myStatus': 'ACCEPTED',
  'championPrizeCoins': 300,
  'myCurrentMatch': {
    'raceId': 'match-1',
    'endsAt': DateTime.now().add(const Duration(days: 2)).toIso8601String(),
    'myPlacement': 2,
    'slotItems': const [
      {'type': 'SECOND_WIND', 'status': 'HELD'},
    ],
    'mysteryBoxCount': 1,
    'queuedBoxCount': 1,
  },
  if (includeIdentity)
    'myIdentity': const {
      'displayName': 'Trail Walker',
      'animal': 'corgi_puppy',
      'equippedAccessories': [
        {'slot': 'HEAD', 'assetId': 'trail_hat'},
      ],
    },
};

Map<String, dynamic> _pendingTournament() => {
  'id': 'tournament-pending',
  'name': 'Open Bracket',
  'status': 'PENDING',
  'seedKind': 'WEEKLY_SHOWDOWN',
  'bracketSize': 8,
  'acceptedCount': 5,
  'myStatus': 'ACCEPTED',
  'championPrizeCoins': 300,
  'myIdentity': const {
    'displayName': 'Trail Walker',
    'animal': 'CAPYBARA',
    'equippedAccessories': [],
  },
};

Map<String, dynamic> _championTournament() => {
  'id': 'tournament-complete',
  'name': 'Finished Bracket',
  'status': 'COMPLETED',
  'bracketSize': 4,
  'championUserId': 'viewer',
  'myStatus': 'ACCEPTED',
  'championPrizeCoins': 300,
  'myIdentity': const {
    'displayName': 'Trail Walker',
    'animal': null,
    'equippedAccessories': null,
  },
};

Future<void> _pump(
  WidgetTester tester, {
  required List<Map<String, dynamic>> tournaments,
  ThemeData? theme,
  double width = 390,
  double textScaleFactor = 1,
  NavigatorObserver? navigatorObserver,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScaleFactor;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppThemeData.light(),
      navigatorObservers: [?navigatorObserver],
      home: Scaffold(
        body: RacesTab(
          authService: await _auth(),
          racesState: Loadable.success({
            'active': const [],
            'pending': const [],
            'completed': const [],
            'tournaments': tournaments,
          }),
          friendsSteps: const [],
          onRacesChanged: _noop,
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _selectState(WidgetTester tester, String state) async {
  await tester.tap(find.byKey(Key('personal-state-$state')));
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'active tournament uses the race-card surface, identity, inventory, and chevron',
    (tester) async {
      await _pump(tester, tournaments: [_activeTournament()]);

      expect(
        find.byKey(const Key('tournament-card-surface-tournament-active')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('tournament-identity-avatar-tournament-active')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('tournament-card-inventory-tournament-active')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('tournament-card-arrow-tournament-active')),
        findsOneWidget,
      );
      expect(find.text('QUARTERFINALS'), findsOneWidget);
      expect(find.text('2ND PLACE'), findsOneWidget);
      expect(find.text('ALIVE'), findsOneWidget);
      expect(find.text('300'), findsOneWidget);

      final avatar = tester.widget<RacerAvatar>(
        find.byKey(const Key('tournament-identity-avatar-tournament-active')),
      );
      expect(avatar.animal, 'corgi_puppy');
      expect(avatar.accessories.single['assetKey'], 'trail_hat');
    },
  );

  testWidgets('pending and completed cards preserve their state hierarchy', (
    tester,
  ) async {
    await _pump(
      tester,
      tournaments: [_pendingTournament(), _championTournament()],
    );

    await _selectState(tester, 'pending');
    expect(
      find.byKey(const Key('tournament-card-surface-tournament-pending')),
      findsOneWidget,
    );
    expect(find.text('BRACKET'), findsOneWidget);
    expect(find.text('5/8 FILLED'), findsOneWidget);
    expect(find.text('LOBBY'), findsOneWidget);
    expect(
      find.byKey(const Key('tournament-card-inventory-tournament-pending')),
      findsNothing,
    );

    await _selectState(tester, 'completed');
    expect(
      find.byKey(const Key('tournament-card-surface-tournament-complete')),
      findsOneWidget,
    );
    expect(find.text('CHAMPION'), findsOneWidget);
    expect(
      find.byKey(const Key('tournament-card-arrow-tournament-complete')),
      findsOneWidget,
    );
  });

  testWidgets('missing or malformed optional identity falls back safely', (
    tester,
  ) async {
    await _pump(
      tester,
      tournaments: [
        _activeTournament(includeIdentity: false),
        {
          ..._pendingTournament(),
          'id': 'tournament-malformed-identity',
          'myIdentity': {
            'displayName': 42,
            'animal': <String>[],
            'equippedAccessories': [
              {'slot': 1, 'assetId': false},
              'not-an-accessory',
            ],
          },
        },
      ],
    );

    final missingAvatar = tester.widget<RacerAvatar>(
      find.byKey(const Key('tournament-identity-avatar-tournament-active')),
    );
    expect(missingAvatar.animal, isNull);
    expect(missingAvatar.accessories, isEmpty);
    expect(tester.takeException(), isNull);

    await _selectState(tester, 'pending');
    final malformedAvatar = tester.widget<RacerAvatar>(
      find.byKey(
        const Key('tournament-identity-avatar-tournament-malformed-identity'),
      ),
    );
    expect(malformedAvatar.animal, isNull);
    expect(malformedAvatar.accessories, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('card opens its tournament detail route', (tester) async {
    final observer = _NavigationObserver();
    await _pump(
      tester,
      tournaments: [_activeTournament()],
      navigatorObserver: observer,
    );
    observer.pushedRoute = null;

    await tester.tap(find.byKey(const Key('tournament-row-tournament-active')));
    await tester.pump();

    expect(observer.pushedRoute, isA<MaterialPageRoute<dynamic>>());
    expect(
      find.byType(TournamentDetailScreen, skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('dark and narrow layouts keep card content inside its surface', (
    tester,
  ) async {
    await _pump(
      tester,
      tournaments: [_activeTournament()],
      theme: AppThemeData.night(),
      width: 320,
      textScaleFactor: 1.3,
    );

    expect(tester.takeException(), isNull);
    final surface = tester.getRect(
      find.byKey(const Key('tournament-card-surface-tournament-active')),
    );
    final avatar = tester.getRect(
      find.byKey(const Key('tournament-identity-avatar-tournament-active')),
    );
    final arrow = tester.getRect(
      find.byKey(const Key('tournament-card-arrow-tournament-active')),
    );
    expect(surface.contains(avatar.topLeft), isTrue);
    expect(surface.contains(avatar.bottomRight), isTrue);
    expect(surface.contains(arrow.topLeft), isTrue);
    expect(surface.contains(arrow.bottomRight), isTrue);
  });

  testWidgets(
    'tutorial Races host keeps its spotlights on the first ordinary race',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final cardKey = GlobalKey();
      final boxKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemeData.light(),
          home: TutorialRealHost(
            page: TutorialMockPage.races,
            keys: {'races.card': cardKey, 'races.box': boxKey},
            authService: TutorialPreviewAuthService(),
            api: TutorialPreviewBackendApiService(),
          ),
        ),
      );
      await tester.pump();

      expect(cardKey.currentContext, isNotNull);
      expect(boxKey.currentContext, isNotNull);
      expect(
        find.byKey(const Key('race-card-surface-race-active-1')),
        findsNWidgets(2),
      );
      expect(
        find.byKey(
          const Key('tournament-card-surface-tournament-preview-active'),
        ),
        findsOneWidget,
      );
      expect(
        tester.getRect(find.byKey(cardKey)).top,
        lessThan(
          tester
              .getRect(
                find.byKey(
                  const Key(
                    'tournament-card-surface-tournament-preview-active',
                  ),
                ),
              )
              .top,
        ),
      );
    },
  );
}
