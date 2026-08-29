import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/constants/powerup_copy.dart';
import 'package:step_tracker/screens/case_opening_screen.dart';
import 'package:step_tracker/screens/tabs/home_tab.dart';
import 'package:step_tracker/screens/tabs/profile_tab.dart';
import 'package:step_tracker/screens/tabs/races_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/notification_service.dart';
import 'package:step_tracker/services/race_feed_service.dart';
import 'package:step_tracker/utils/race_participant_display.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/powerup_guide_sheet.dart';
import 'package:step_tracker/widgets/race_card_capybara_row.dart';
import 'package:step_tracker/widgets/powerup_reveal_modal.dart';

class _FavoriteApi extends BackendApiService {
  final List<(String, bool)> calls = [];

  @override
  Future<Map<String, dynamic>> updateRaceFavorite({
    required String identityToken,
    required String raceId,
    required bool favorite,
  }) async {
    calls.add((raceId, favorite));
    return {
      'raceId': raceId,
      'isFavorite': favorite,
      'favoritedAt': favorite ? '2026-08-28T18:10:00.000Z' : null,
    };
  }
}

class _DeferredFailingFavoriteApi extends BackendApiService {
  final Completer<Map<String, dynamic>> result = Completer();
  int calls = 0;

  @override
  Future<Map<String, dynamic>> updateRaceFavorite({
    required String identityToken,
    required String raceId,
    required bool favorite,
  }) {
    calls += 1;
    return result.future;
  }
}

class _FailingFavoriteApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> updateRaceFavorite({
    required String identityToken,
    required String raceId,
    required bool favorite,
  }) => throw const ApiException('network failed');
}

Future<AuthService> _auth({String userId = 'user-1'}) async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': userId,
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Map<String, dynamic> _race(
  String id,
  String name,
  String endsAt, {
  Object? isFavorite = false,
}) => {
  'id': id,
  'name': name,
  'status': 'ACTIVE',
  'myStatus': 'ACCEPTED',
  'endsAt': endsAt,
  'participantCount': 2,
  'isFavorite': isFavorite,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'privacy-safe ranks compact visible gaps without touching canonical rank',
    () {
      final ordered = orderRaceParticipantsForDisplay([
        {'userId': 'hidden', 'stealthed': true, 'placement': null},
        {'userId': 'first', 'stealthed': false, 'placement': 1},
        {'userId': 'third', 'stealthed': false, 'placement': 3},
      ]);

      expect(ordered.map((row) => row['userId']), ['hidden', 'first', 'third']);
      expect(ordered.map(displayPlacementOf), [null, 1, 2]);
      expect(serverPlacementOf(ordered.last), 3);
    },
  );

  test(
    'paged privacy projection trusts explicit display rank without hidden row',
    () {
      final ordered = orderRaceParticipantsForDisplay([
        {'userId': 'canonical-4', 'placement': 4, 'displayPlacement': 3},
        {'userId': 'canonical-5', 'placement': 5, 'displayPlacement': 4},
      ], placementPrivacyActive: true);

      expect(ordered.map(displayPlacementOf), [3, 4]);
      expect(ordered.map(serverPlacementOf), [4, 5]);
    },
  );

  test(
    'catalog stacking is additive and malformed metadata keeps usable copy',
    () {
      final snapshot = PowerupCopySnapshot.parse({
        'version': '2026-08-28',
        'stackingVersion': 1,
        'powerups': [
          {
            'type': 'RUNNERS_HIGH',
            'name': "Runner's High",
            'description': '2x steps',
            'stacking': {
              'samePowerup': 'BLOCKED',
              'otherEffects': 'CONDITIONAL',
              'summary': 'Different boosts add, with scoring precedence.',
            },
          },
          {
            'type': 'RED_CARD',
            'name': 'Red Card',
            'description': 'Remove steps',
            'stacking': {'samePowerup': 'FUTURE_ENUM'},
          },
        ],
      });

      expect(snapshot, isNotNull);
      expect(
        snapshot!.entries['RUNNERS_HIGH']!.stacking?.samePowerup,
        SamePowerupStacking.blocked,
      );
      expect(snapshot.entries['RED_CARD']!.stacking, isNull);
    },
  );

  test('old catalog snapshots merge missing bundled guide rows', () async {
    PowerupCopy.resetForTest();
    addTearDown(PowerupCopy.resetForTest);
    await PowerupCopy.refresh(
      fetch: () async => {
        'version': 'legacy',
        'powerups': [
          {
            'type': 'RED_CARD',
            'name': 'Red Card',
            'description': 'Remove steps',
          },
        ],
      },
    );

    final types = PowerupCopy.guideEntries.map((entry) => entry.type).toSet();
    expect(types, containsAll(['RED_CARD', 'RUNNERS_HIGH', 'QUICK_RINSE']));
    expect(
      PowerupCopy.guideEntries
          .firstWhere((entry) => entry.type == 'RUNNERS_HIGH')
          .stacking,
      isNotNull,
    );
  });

  testWidgets('legacy Home top-three compacts ranks around Stealth', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RaceCardCapybaraRow(
            top3: [
              {'displayName': '???', 'rank': 2, 'isStealthed': true},
              {'displayName': 'Leader', 'rank': 1},
              {'displayName': 'Third', 'rank': 3},
            ],
          ),
        ),
      ),
    );

    expect(find.text('?'), findsOneWidget);
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget);
    expect(find.text('3.'), findsNothing);
  });

  testWidgets(
    'legacy Home hides truncated ranks but preserves the raw runner count',
    (tester) async {
      final auth = await _auth();
      final home = HomeTab(
        stepData: null,
        isLoading: false,
        error: null,
        healthAuthorized: true,
        notificationsState: true,
        displayName: 'Viewer',
        authService: auth,
        backendApiService: BackendApiService(),
        onRefresh: () async {},
        onEnableHealth: () {},
        onEnableNotifications: () {},
        onDisplayNameChanged: () {},
        friendsSteps: const [],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: home.buildLegacyActiveRacesRow({
              'data': {
                'races': [
                  {
                    'raceId': 'legacy-race',
                    'name': 'Legacy Race',
                    'top3': [
                      {'userId': 'first', 'displayName': 'First', 'rank': 1},
                      {'userId': 'second', 'displayName': 'Second', 'rank': 2},
                      {'userId': 'third', 'displayName': 'Third', 'rank': 3},
                    ],
                  },
                ],
              },
            }),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('3 racers'), findsOneWidget);
      expect(find.text('First'), findsNothing);
      expect(find.text('Second'), findsNothing);
      expect(find.text('Third'), findsNothing);
      expect(privacySafeHomeTopThree(const {'top3': []}), isEmpty);
    },
  );

  testWidgets(
    'real case-opening help defaults to POWERUPS and reaches STACKING',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CaseOpeningScreen(
            openMysteryBox: () async => const {
              'result': {'type': 'RED_CARD', 'rarity': 'RARE'},
            },
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('?'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('POWERUP CHEAT SHEET'), findsOneWidget);
      expect(
        find.byKey(const Key('powerup-guide-powerups-page')),
        findsOneWidget,
      );
      await tester.tap(find.text('STACKING'));
      await tester.pump();
      expect(
        find.byKey(const Key('powerup-guide-stacking-page')),
        findsOneWidget,
      );
      expect(find.text('SAME POWERUP'), findsWidgets);
      expect(find.text('OTHER EFFECTS'), findsWidgets);
    },
  );

  testWidgets(
    'guide fits narrow large-text night mode and preserves each page scroll',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
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

      expect(tester.takeException(), isNull);
      final powerups = tester.widget<ListView>(
        find.byKey(const Key('powerup-guide-powerups-page')),
      );
      await tester.drag(
        find.byKey(const Key('powerup-guide-powerups-page')),
        const Offset(0, -240),
      );
      await tester.pump();
      final powerupsOffset = powerups.controller!.offset;
      expect(powerupsOffset, greaterThan(0));

      await tester.tap(find.text('STACKING'));
      await tester.pump();
      final stacking = tester.widget<ListView>(
        find.byKey(const Key('powerup-guide-stacking-page')),
      );
      expect(stacking.controller!.offset, 0);
      await tester.drag(
        find.byKey(const Key('powerup-guide-stacking-page')),
        const Offset(0, -180),
      );
      await tester.pump();
      expect(stacking.controller!.offset, greaterThan(0));

      await tester.tap(find.text('POWERUPS'));
      await tester.pump();
      expect(powerups.controller!.offset, powerupsOffset);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('favorite stars pin ordinary races and do not open the card', (
    tester,
  ) async {
    final api = _FavoriteApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RacesTab(
            authService: await _auth(),
            backendApiService: api,
            racesData: {
              'active': [
                _race('soon', 'Soon', '2026-08-29T00:00:00.000Z'),
                _race(
                  'later',
                  'Later',
                  '2026-08-30T00:00:00.000Z',
                  isFavorite: true,
                ),
              ],
              'pending': const [],
              'completed': const [],
            },
            friendsSteps: const [],
            onRacesChanged: () async {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Later'), findsNWidgets(2));
    expect(
      tester.getTopLeft(find.text('Later').first).dy,
      lessThan(tester.getTopLeft(find.text('Soon').first).dy),
    );
    expect(find.text('??? PLACE'), findsNWidgets(3));
    final soonFavorite = find.byKey(const Key('race-favorite-soon'));
    await tester.ensureVisible(soonFavorite);
    await tester.pumpAndSettle();
    await tester.tap(soonFavorite);
    await tester.pump();
    expect(api.calls, [('soon', true)]);
    expect(find.byType(RacesTab), findsOneWidget);
  });

  testWidgets('failed favorite yields to the opposite authoritative refresh', (
    tester,
  ) async {
    final api = _DeferredFailingFavoriteApi();
    final auth = await _auth();

    Widget build(bool authoritativeFavorite) => MaterialApp(
      home: Scaffold(
        body: RacesTab(
          authService: auth,
          backendApiService: api,
          racesData: {
            'active': [
              _race(
                'race-1',
                'Authoritative Race',
                '2026-08-30T00:00:00.000Z',
                isFavorite: authoritativeFavorite,
              ),
            ],
            'pending': const [],
            'completed': const [],
          },
          friendsSteps: const [],
          onRacesChanged: () async {},
        ),
      ),
    );

    await tester.pumpWidget(build(false));
    await tester.pump();
    await tester.tap(find.byKey(const Key('race-favorite-race-1')));
    await tester.pumpWidget(build(true));
    await tester.pump();
    api.result.completeError(const ApiException('network failed'));
    await tester.pump();

    final semantics = tester.getSemantics(
      find.byKey(const Key('race-favorite-race-1')),
    );
    expect(
      semantics.getSemanticsData().flagsCollection.isToggled,
      Tristate.isTrue,
    );
  });

  testWidgets(
    'favorite rapid repeats coalesce and ordinary failures roll back',
    (tester) async {
      final auth = await _auth();
      final delayed = _DeferredFailingFavoriteApi();

      Widget build(BackendApiService api) => MaterialApp(
        home: Scaffold(
          body: RacesTab(
            authService: auth,
            backendApiService: api,
            racesData: {
              'active': [
                _race('race-1', 'Race One', '2026-08-30T00:00:00.000Z'),
              ],
              'pending': const [],
              'completed': const [],
            },
            friendsSteps: const [],
            onRacesChanged: () async {},
          ),
        ),
      );

      await tester.pumpWidget(build(delayed));
      await tester.pump();
      final star = find.byKey(const Key('race-favorite-race-1'));
      await tester.tap(star);
      await tester.tap(star, warnIfMissed: false);
      expect(delayed.calls, 1);
      delayed.result.complete({
        'raceId': 'race-1',
        'isFavorite': true,
        'favoritedAt': '2026-08-28T18:10:00.000Z',
      });
      await tester.pump();

      await tester.pumpWidget(build(_FailingFavoriteApi()));
      await tester.pump();
      expect(
        tester.getSemantics(star).getSemanticsData().flagsCollection.isToggled,
        Tristate.isTrue,
      );
      await tester.tap(star);
      await tester.pump();
      expect(find.text('network failed'), findsOneWidget);
      expect(
        tester.getSemantics(star).getSemanticsData().flagsCollection.isToggled,
        Tristate.isTrue,
      );
    },
  );

  testWidgets('favorite optimistic state is cleared across an account switch', (
    tester,
  ) async {
    final firstAuth = await _auth(userId: 'first-user');
    final api = _DeferredFailingFavoriteApi();

    Widget build(AuthService auth) => MaterialApp(
      home: Scaffold(
        body: RacesTab(
          authService: auth,
          backendApiService: api,
          racesData: {
            'active': [_race('race-1', 'Race One', '2026-08-30T00:00:00.000Z')],
            'pending': const [],
            'completed': const [],
          },
          friendsSteps: const [],
          onRacesChanged: () async {},
        ),
      ),
    );

    await tester.pumpWidget(build(firstAuth));
    await tester.pump();
    final star = find.byKey(const Key('race-favorite-race-1'));
    await tester.tap(star);
    await tester.pump();
    final secondAuth = await _auth(userId: 'second-user');
    await tester.pumpWidget(build(secondAuth));
    await tester.pump();
    expect(
      tester.getSemantics(star).getSemanticsData().flagsCollection.isToggled,
      Tristate.isFalse,
    );
    api.result.complete({
      'raceId': 'race-1',
      'isFavorite': true,
      'favoritedAt': '2026-08-28T18:10:00.000Z',
    });
    await tester.pump();
    expect(
      tester.getSemantics(star).getSemanticsData().flagsCollection.isToggled,
      Tristate.isFalse,
    );
  });

  testWidgets(
    'favorite eligibility excludes invites and tournaments and defaults malformed fields',
    (tester) async {
      final missingFavorite = _race(
        'missing',
        'Missing',
        '2026-08-31T00:00:00.000Z',
      )..remove('isFavorite');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RacesTab(
              authService: await _auth(),
              backendApiService: _FavoriteApi(),
              racesData: {
                'active': [
                  _race(
                    'active',
                    'Active',
                    '2026-08-30T00:00:00.000Z',
                    isFavorite: 'malformed',
                  ),
                  missingFavorite,
                ],
                'pending': [
                  {
                    ..._race('invite', 'Invite', '2026-08-30T00:00:00.000Z'),
                    'status': 'PENDING',
                    'myStatus': 'INVITED',
                  },
                ],
                'completed': [
                  {
                    ..._race(
                      'complete',
                      'Complete',
                      '2026-08-27T00:00:00.000Z',
                    ),
                    'status': 'COMPLETED',
                  },
                ],
                'tournaments': const [
                  {
                    'id': 'tournament-1',
                    'name': 'Tournament',
                    'status': 'ACTIVE',
                    'myStatus': 'ACCEPTED',
                  },
                ],
              },
              friendsSteps: const [],
              onRacesChanged: () async {},
            ),
          ),
        ),
      );
      await tester.pump();

      final activeStar = find.byKey(const Key('race-favorite-active'));
      expect(activeStar, findsOneWidget);
      expect(
        tester
            .getSemantics(activeStar)
            .getSemanticsData()
            .flagsCollection
            .isToggled,
        Tristate.isFalse,
      );
      expect(
        tester
            .getSemantics(find.byKey(const Key('race-favorite-missing')))
            .getSemanticsData()
            .flagsCollection
            .isToggled,
        Tristate.isFalse,
      );
      expect(find.byKey(const Key('race-favorite-invite')), findsNothing);
      expect(find.byKey(const Key('race-favorite-tournament-1')), findsNothing);

      await tester.tap(find.byKey(const Key('personal-state-completed')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('race-favorite-complete')), findsOneWidget);
    },
  );

  test(
    'attack taps normalize APNs maps, FCM JSON and legacy top-level IDs',
    () async {
      final ios = NotificationService(isIosForTesting: true);
      await ios.handleNotificationTapForTesting({
        'type': 'POWERUP_USED',
        'params': {'raceId': 'race-ios'},
      });
      expect(ios.pendingAction.value?.params['raceId'], 'race-ios');

      final android = NotificationService(isIosForTesting: false);
      await android.handleNotificationTapForTesting({
        'type': 'POWERUP_USED',
        'params': '{"raceId":"race-android"}',
      });
      expect(android.pendingAction.value?.params['raceId'], 'race-android');
      await android.handleNotificationTapForTesting({
        'type': 'POWERUP_USED',
        'raceId': 'race-legacy',
      });
      expect(android.pendingAction.value?.params['raceId'], 'race-legacy');
    },
  );

  testWidgets('impact reveal renders privacy-safe attacker attribution', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PowerupRevealModal(
            iconType: 'RED_CARD',
            title: 'POWERUP SUMMARY',
            subtitle: 'Your race steps changed.',
            signedSteps: -1200,
            attackerDisplayName: 'TrailRunner',
            accent: Colors.red,
            onDismiss: () {},
          ),
        ),
      ),
    );
    expect(find.text('Attacked by @TrailRunner'), findsOneWidget);
    expect(find.text('-1,200 steps'), findsOneWidget);
  });

  test(
    'Profile All Time uses one-decimal million notation only at the boundary',
    () {
      expect(formatProfileAllTimeSteps(999), '999');
      expect(formatProfileAllTimeSteps(1000), '1.0k');
      expect(formatProfileAllTimeSteps(999900), '999.9k');
      expect(formatProfileAllTimeSteps(1000000), '1.0M');
      expect(formatProfileAllTimeSteps(1503300), '1.5M');
      expect(formatProfileAllTimeSteps(12960000), '13.0M');
    },
  );

  test(
    'private expiry Activity retains exact authoritative copy and typed delta',
    () {
      final event = RaceFeedEvent.tryFromJson({
        'id': 'impact:expiry-1',
        'eventType': 'EFFECT_IMPACT',
        'powerupType': 'WRONG_TURN',
        'description': 'Wrong Turn wore off. You gained 1,250 steps.',
        'deltaSteps': 1250,
        'sourceFeedEventId': 'feed:expiry-1',
        'attackerDisplayName': 'TrailRunner',
        'createdAt': '2026-08-28T18:10:00.000Z',
      });

      expect(
        event?.description,
        'Wrong Turn wore off. You gained 1,250 steps.',
      );
      expect(event?.deltaSteps, 1250);
      expect(event?.attackerDisplayName, 'TrailRunner');
    },
  );

  test(
    'display-rank capability is advertised on the shared client contract',
    () {
      expect(
        BackendApiService.clientFeaturesHeader.split(','),
        contains('privacy_safe_display_ranks'),
      );
      expect(
        BackendApiService.clientFeaturesHeader.split(','),
        contains('powerup_stacking_guide_v1'),
      );
      expect(
        BackendApiService.clientFeaturesHeaderForPlatform(
          isIos: false,
          adsSupported: false,
          racePayoutDoubleSupported: false,
        ).split(','),
        contains('privacy_safe_display_ranks'),
      );
      expect(
        BackendApiService.clientFeaturesHeaderForPlatform(
          isIos: false,
          adsSupported: false,
          racePayoutDoubleSupported: false,
        ).split(','),
        contains('powerup_stacking_guide_v1'),
      );
    },
  );
}
