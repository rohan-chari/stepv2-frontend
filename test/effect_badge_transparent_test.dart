import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/powerup_icon.dart';

/// The active-effect badge in the standings has now had three backgrounds: a
/// near-white plate, then a polarity-tinted plate inside a `woodDark` frame —
/// which on a cream standings row read as a dark green chip glued to the
/// sprite — and now nothing at all.
///
/// The sprite carries its own black keylines, so a cream row needs no help.
/// Night mode does: on the night parchment (#1B2A34) the darkest sprites sit
/// near 1:1 against the background, so they get a halo shaped like the art
/// instead of a box.
///
/// Pumped through the real race screen rather than the badge widget, because
/// the defect was about what the badge looks like *on the row it sits on*.

class _EffectsApi extends BackendApiService {
  _EffectsApi({required this.activeEffects});

  final List<Map<String, dynamic>> activeEffects;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async => {
    'id': raceId,
    'name': 'Effects Race',
    'status': 'ACTIVE',
    'targetSteps': 100000,
    'maxDurationDays': 7,
    'buyInAmount': 0,
    'payoutPreset': 'WINNER_TAKES_ALL',
    'potCoins': 0,
    'heldPotCoins': 0,
    'projectedPotCoins': 0,
    'payouts': const {'first': 0, 'second': 0, 'third': 0},
    'myStatus': 'ACCEPTED',
    'isCreator': false,
    'powerupsEnabled': true,
    'endsAt': '2026-12-10T12:00:00.000Z',
    'participants': const [
      {'userId': 'u1', 'displayName': 'Ann', 'status': 'ACCEPTED'},
      {'userId': 'u2', 'displayName': 'Bob', 'status': 'ACCEPTED'},
    ],
  };

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async => {
    'status': 'ACTIVE',
    'participants': const [
      {'userId': 'u1', 'displayName': 'Ann', 'totalSteps': 9000},
      {'userId': 'u2', 'displayName': 'Bob', 'totalSteps': 5000},
    ],
    'powerupData': {
      'enabled': true,
      'inventory': const [],
      'powerupSlots': 3,
      'queuedBoxCount': 0,
      'activeEffects': activeEffects,
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
      const {'coins': 0, 'heldCoins': 0};
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'u2',
    'auth_display_name': 'Bob',
    'auth_coins': 0,
    'auth_held_coins': 0,
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Future<void> _pump(
  WidgetTester tester,
  BackendApiService api, {
  required bool night,
}) async {
  await tester.binding.setSurfaceSize(const Size(500, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: night ? AppThemeData.night() : AppThemeData.light(),
      home: RaceDetailScreen(
        authService: await _auth(),
        raceId: 'race-1',
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// The darkest sprite in the catalogue — 1.04:1 against the night parchment,
/// so it is the one that proves the halo is doing real work.
_EffectsApi _darkSpriteApi() => _EffectsApi(
  activeEffects: const [
    {
      'type': 'POWER_OUTAGE',
      'targetUserId': 'u2',
      'sourceUserId': 'u1',
      'onSelf': true,
    },
  ],
);

BoxDecoration _plateDecoration(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.byKey(const Key('effect-badge-plate')).first,
  );
  return container.decoration as BoxDecoration;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the badge paints no plate behind the sprite in day mode', (
    tester,
  ) async {
    await _pump(tester, _darkSpriteApi(), night: false);

    final decoration = _plateDecoration(tester);
    expect(decoration.color, Colors.transparent);
    // The `woodDark` frame that made it read as a green chip is gone too.
    expect(decoration.border, isNull);
    expect(decoration.borderRadius, isNull);
  });

  testWidgets('night mode paints no plate either', (tester) async {
    await _pump(tester, _darkSpriteApi(), night: true);

    expect(_plateDecoration(tester).color, Colors.transparent);
    expect(_plateDecoration(tester).border, isNull);
  });

  testWidgets('a near-invisible sprite gets a halo at night, not a box', (
    tester,
  ) async {
    await _pump(tester, _darkSpriteApi(), night: true);

    final plate = find.byKey(const Key('effect-badge-plate')).first;
    // The halo is the sprite itself, flooded and blurred, painted under the
    // real one — so the badge draws the same art more than once.
    expect(
      find.descendant(of: plate, matching: find.byType(PowerupIcon)),
      findsNWidgets(3),
    );
    expect(
      find.descendant(of: plate, matching: find.byType(ImageFiltered)),
      findsNWidgets(2),
    );
  });

  testWidgets('day mode draws the sprite once, with no halo', (tester) async {
    await _pump(tester, _darkSpriteApi(), night: false);

    final plate = find.byKey(const Key('effect-badge-plate')).first;
    expect(
      find.descendant(of: plate, matching: find.byType(PowerupIcon)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: plate, matching: find.byType(ImageFiltered)),
      findsNothing,
    );
  });
}
