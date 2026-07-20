import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/powerup_icon.dart';

// Spec §4: team-roster cells must stay aligned regardless of how many powerup
// effects sit on each racer. Effects live in a narrow right-hand rail (reserved
// even when empty), stacked vertically, with a `+N` overflow chip so the card
// never grows. The manual tooltip must clamp on-screen instead of using the old
// hardcoded off-screen offsets.

class _RailApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
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
      {'userId': 'user-1', 'displayName': 'Me Myself', 'status': 'ACCEPTED', 'team': 'TEAM_A'},
      {'userId': 'ally-1', 'displayName': 'Ally Alice', 'status': 'ACCEPTED', 'team': 'TEAM_A'},
      {'userId': 'enemy-1', 'displayName': 'Enemy Eve', 'status': 'ACCEPTED', 'team': 'TEAM_B'},
      {'userId': 'enemy-2', 'displayName': 'Enemy Ed', 'status': 'ACCEPTED', 'team': 'TEAM_B'},
    ],
  };

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async => {
    'status': 'ACTIVE',
    'participants': [
      {'userId': 'user-1', 'displayName': 'Me Myself', 'team': 'TEAM_A', 'totalSteps': 6200, 'finishedAt': null},
      {'userId': 'ally-1', 'displayName': 'Ally Alice', 'team': 'TEAM_A', 'totalSteps': 6100, 'finishedAt': null},
      {'userId': 'enemy-1', 'displayName': 'Enemy Eve', 'team': 'TEAM_B', 'totalSteps': 5900, 'finishedAt': null},
      {'userId': 'enemy-2', 'displayName': 'Enemy Ed', 'team': 'TEAM_B', 'totalSteps': 5000, 'finishedAt': null},
    ],
    'powerupData': {
      'enabled': true,
      'inventory': [],
      'powerupSlots': 3,
      'queuedBoxCount': 0,
      'powerupStepInterval': 5000,
      'stepsUntilNextPowerup': 1000,
      'activeEffects': [
        // enemy-1: five effects → overflow into a +N chip.
        {'type': 'RAINSTORM', 'targetUserId': 'enemy-1', 'sourceUserId': 'user-1'},
        {'type': 'LEG_CRAMP', 'targetUserId': 'enemy-1', 'sourceUserId': 'user-1'},
        {'type': 'WRONG_TURN', 'targetUserId': 'enemy-1', 'sourceUserId': 'user-1'},
        {'type': 'DETOUR_SIGN', 'targetUserId': 'enemy-1', 'sourceUserId': 'user-1'},
        {'type': 'SIGNAL_JAMMER', 'targetUserId': 'enemy-1', 'sourceUserId': 'user-1'},
        // ally-1: zero effects (the empty-but-reserved rail baseline).
        // enemy-2 (right column, right edge): one tappable effect for the
        // tooltip-clamping check.
        {'type': 'RED_CARD', 'targetUserId': 'enemy-2', 'sourceUserId': 'user-1'},
      ],
    },
  };

  @override
  Future<Map<String, dynamic>> fetchRaceFeed({
    String? cursor,
    required String identityToken,
    required String raceId,
  }) async => const {'events': []};

  @override
  Future<Map<String, dynamic>> fetchMe({
    required String identityToken,
  }) async => const {'coins': 320, 'heldCoins': 0};
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

Future<void> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(430, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final auth = await _auth();
  await tester.pumpWidget(
    MaterialApp(
      home: RaceDetailScreen(
        authService: auth,
        raceId: 'race-rail',
        backendApiService: _RailApi(),
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

  testWidgets('opposing cells stay equal height with 0, 1, and 5 effects',
      (tester) async {
    await _pump(tester);

    // Compare cells with the same (non-"me") border so the only variable is the
    // effect count. (The "me" cell has a deliberately thicker highlight border,
    // a pre-existing 1px difference unrelated to this work.)
    final zero = _cellHeight(tester, 'ally-1'); // 0 effects
    final one = _cellHeight(tester, 'enemy-2'); // 1 effect
    final five = _cellHeight(tester, 'enemy-1'); // 5 effects (overflow)

    expect(one, zero);
    // The card must not grow vertically no matter how many effects are active.
    expect(five, zero);
  });

  testWidgets('overflowing effects collapse into a +N chip', (tester) async {
    await _pump(tester);

    // Five effects, ~3 slots fit → 2 icons + a "+3" chip.
    expect(find.text('+3'), findsOneWidget);
  });

  testWidgets('a right-edge effect icon shows its tooltip fully on-screen',
      (tester) async {
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
    // …and clamped fully within the 430pt-wide screen (the old fixed offset
    // would have pushed a right-column bubble off the right edge).
    final rect = tester.getRect(bubble);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(430));

    // Dismiss the 3s auto-hide timer before teardown.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('every rail effect exposes a semantics label', (tester) async {
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
  });
}
