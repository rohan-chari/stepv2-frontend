import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/capped_scroll_list.dart';

// A big race must not turn the detail page into an endless scroll of planks.
// Above ten runners the STANDINGS card stops growing and scrolls internally,
// so POWERUPS and ACTIVITY stay reachable. At or below ten it renders exactly
// as it always did.

List<Map<String, dynamic>> _participants(int count) => [
  for (int i = 1; i <= count; i++)
    {
      'userId': 'user-$i',
      'displayName': 'Runner $i',
      'status': 'ACCEPTED',
    },
];

List<Map<String, dynamic>> _progress(int count) => [
  for (int i = 1; i <= count; i++)
    {
      'userId': 'user-$i',
      'displayName': 'Runner $i',
      // Descending so Runner 1 is first and Runner N is last on the board.
      'totalSteps': (20000 - i * 100).toDouble(),
      'finishedAt': null,
    },
];

Map<String, dynamic> _race(int count) => {
  'id': 'race-1',
  'name': 'Trail Blazers',
  'status': 'ACTIVE',
  'maxDurationDays': 3,
  'buyInAmount': 0,
  'potCoins': 0,
  'heldPotCoins': 0,
  'projectedPotCoins': 0,
  'myStatus': 'ACCEPTED',
  'isCreator': false,
  'powerupsEnabled': false,
  'endsAt': '2126-04-10T12:00:00.000Z',
  'participants': _participants(count),
};

class _StubApi extends BackendApiService {
  _StubApi(this.count);

  final int count;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async => _race(count);

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async => {
    'status': 'ACTIVE',
    'participants': _progress(count),
    'powerupData': const {
      'enabled': false,
      'inventory': [],
      'powerupSlots': 3,
      'queuedBoxCount': 0,
      'activeEffects': [],
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

Future<AuthService> _authService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Runner 1',
    'auth_coins': 0,
    'auth_held_coins': 0,
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

Future<void> _pump(WidgetTester tester, int count) async {
  final authService = await _authService();
  await tester.pumpWidget(
    MaterialApp(
      home: RaceDetailScreen(
        authService: authService,
        raceId: 'race-1',
        backendApiService: _StubApi(count),
      ),
    ),
  );
  // Bounded pumps: the hero's spinning coin animates forever, so the tree
  // never fully settles.
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a ten-runner race still renders the standings uncapped', (
    tester,
  ) async {
    await _pump(tester, 10);

    expect(find.byType(CappedScrollList), findsNothing);

    await _teardown(tester);
  });

  testWidgets('past ten runners the standings get a fixed-height window', (
    tester,
  ) async {
    await _pump(tester, 16);

    final window = find.byType(CappedScrollList);
    expect(window, findsOneWidget);

    // The window is bounded: it must be shorter than the 16 planks it holds
    // (~52px each) and no taller than the cap.
    final height = tester.getSize(window).height;
    expect(height, lessThanOrEqualTo(520.0));
    expect(height, lessThan(16 * 52.0));

    await _teardown(tester);
  });

  testWidgets('scrolling the standings window moves rows, not the page', (
    tester,
  ) async {
    await _pump(tester, 16);

    final window = find.byType(CappedScrollList);
    final header = find.text('STANDINGS');
    expect(header, findsOneWidget);

    // The standings sit well down the page, so bring the card on-screen before
    // touching it — otherwise the drag lands outside the test viewport.
    await tester.ensureVisible(window);
    await tester.pump();

    final inner = tester.state<ScrollableState>(
      find.descendant(of: window, matching: find.byType(Scrollable)).first,
    );
    // There is genuinely more roster than window.
    expect(inner.position.maxScrollExtent, greaterThan(0));
    expect(inner.position.pixels, 0);

    final headerBefore = tester.getTopLeft(header);

    // Drag from a point that is definitely inside the window's visible area.
    final rect = tester.getRect(window);
    await tester.dragFrom(
      Offset(rect.center.dx, rect.top + 24),
      const Offset(0, -160),
    );
    await tester.pump();

    // The roster scrolled inside its own window...
    expect(inner.position.pixels, greaterThan(0));

    // ...while the page underneath stayed exactly where it was, so the section
    // header did not travel with the drag.
    expect(tester.getTopLeft(header), headerBefore);

    // And the runners at the bottom of a 16-strong board are reachable.
    inner.position.jumpTo(inner.position.maxScrollExtent);
    await tester.pump();
    expect(
      find.descendant(of: window, matching: find.text('@Runner 16')),
      findsOneWidget,
    );

    await _teardown(tester);
  });
}
