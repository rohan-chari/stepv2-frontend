import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/powerup_icon.dart';

/// Active effects in solo standings use readable polarity-tinted plates. The
/// entire cluster is a single tap target that opens the participant status
/// sheet; this keeps an eight-effect racer from widening the row indefinitely.
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
    int? participantsLimit,
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
  // Common compact-phone width: the second-line tray must not compete with
  // the participant name or step total even in the eight-effect state.
  await tester.binding.setSurfaceSize(const Size(390, 1400));
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

_EffectsApi _overflowApi() => _EffectsApi(
  activeEffects: const [
    {'type': 'RUNNERS_HIGH', 'targetUserId': 'u2', 'sourceUserId': 'u2'},
    {'type': 'UPRISING', 'targetUserId': 'u2', 'sourceUserId': 'u1'},
    {'type': 'LEG_CRAMP', 'targetUserId': 'u2', 'sourceUserId': 'u1'},
    {'type': 'RAINSTORM', 'targetUserId': 'u2', 'sourceUserId': 'u1'},
    {'type': 'WRONG_TURN', 'targetUserId': 'u2', 'sourceUserId': 'u1'},
    {'type': 'POWER_OUTAGE', 'targetUserId': 'u2', 'sourceUserId': 'u1'},
    {'type': 'LEECH', 'targetUserId': 'u2', 'sourceUserId': 'u1'},
    {'type': 'SIGNAL_JAMMER', 'targetUserId': 'u2', 'sourceUserId': 'u1'},
  ],
);

BoxDecoration _plateDecoration(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.byKey(const Key('participant-effect-plate-debuff')).first,
  );
  return container.decoration as BoxDecoration;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the badge paints a framed polarity plate in day mode', (
    tester,
  ) async {
    await _pump(tester, _darkSpriteApi(), night: false);

    final decoration = _plateDecoration(tester);
    expect(decoration.color, isNot(Colors.transparent));
    expect(decoration.border, isNotNull);
    expect(decoration.borderRadius, isNotNull);
  });

  testWidgets('night mode keeps the contrast plate', (tester) async {
    await _pump(tester, _darkSpriteApi(), night: true);

    expect(_plateDecoration(tester).color, isNot(Colors.transparent));
    expect(_plateDecoration(tester).border, isNotNull);
  });

  testWidgets('the framed tray draws one crisp sprite', (tester) async {
    await _pump(tester, _darkSpriteApi(), night: true);

    final plate = find
        .byKey(const Key('participant-effect-plate-debuff'))
        .first;
    expect(
      find.descendant(of: plate, matching: find.byType(PowerupIcon)),
      findsOneWidget,
    );
  });

  testWidgets('tapping the tray opens the participant status sheet', (
    tester,
  ) async {
    await _pump(tester, _darkSpriteApi(), night: false);

    await tester.tap(find.byKey(const Key('participant-effect-tray')).first);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('@Bob STATUS'), findsOneWidget);
    expect(find.text('1 active effect'), findsOneWidget);
    expect(find.text('Power Outage'), findsWidgets);
    expect(find.text('DEBUFFS'), findsWidgets);
  });

  testWidgets(
    'eight effects stay beside the name, swipe horizontally, and open in sheet',
    (tester) async {
      await _pump(tester, _overflowApi(), night: false);

      final tray = find.byKey(const Key('participant-effect-tray')).first;
      final list = find.descendant(
        of: tray,
        matching: find.byKey(const Key('participant-effect-scroll')),
      );
      expect(list, findsOneWidget);
      expect(tester.widget<ListView>(list).scrollDirection, Axis.horizontal);
      expect(
        find.descendant(
          of: tray,
          matching: find.byKey(const Key('participant-effect-overflow')),
        ),
        findsNothing,
      );

      final scrollable = find.descendant(
        of: tray,
        matching: find.byType(Scrollable),
      );
      final before = tester.state<ScrollableState>(scrollable).position.pixels;
      await tester.drag(tray, const Offset(-90, 0));
      await tester.pump();
      final after = tester.state<ScrollableState>(scrollable).position.pixels;
      expect(after, greaterThan(before));

      expect(tester.getSize(list).width, lessThanOrEqualTo(103));

      await tester.tap(tray);
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('8 active effects'), findsOneWidget);
      expect(find.text('Signal Jammer'), findsWidgets);
      expect(find.text('BOOSTS'), findsWidgets);
      expect(find.text('DEBUFFS'), findsWidgets);
    },
  );
}
