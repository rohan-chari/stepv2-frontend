import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/leaderboard_plank.dart';

// A big race must not turn the detail page into an endless wall of planks, and
// it must not trap the drag inside an inner scroller either. Past ten runners
// the board collapses to eight planks behind a "show all" row, keeping the page
// a single scroll surface. A viewer who ranks below the cut still sees their
// own plank, pinned under the visible rows.

List<Map<String, dynamic>> _participants(int count) => [
  for (int i = 1; i <= count; i++)
    {'userId': 'user-$i', 'displayName': 'Runner $i', 'status': 'ACCEPTED'},
];

List<Map<String, dynamic>> _progress(int count) => [
  for (int i = 1; i <= count; i++)
    {
      'userId': 'user-$i',
      'displayName': 'Runner $i',
      // Descending so Runner 1 leads and Runner N is last on the board.
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
  _StubApi(this.count, {this.pagination});

  final int count;

  /// When set, the progress payload carries server pagination metadata, as it
  /// does for a race whose roster is larger than one page.
  final Map<String, dynamic>? pagination;

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
    if (pagination != null) 'pagination': pagination,
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

Future<AuthService> _authService({required String myUserId}) async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': myUserId,
    'auth_display_name': 'Runner',
    'auth_coins': 0,
    'auth_held_coins': 0,
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

Future<void> _pump(
  WidgetTester tester,
  int count, {
  String myUserId = 'user-1',
  Map<String, dynamic>? pagination,
}) async {
  final authService = await _authService(myUserId: myUserId);
  await tester.pumpWidget(
    MaterialApp(
      home: RaceDetailScreen(
        authService: authService,
        raceId: 'race-1',
        backendApiService: _StubApi(count, pagination: pagination),
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

Finder get _toggle => find.byKey(const Key('standings-toggle'));
Finder get _loadMore => find.byKey(const Key('standings-load-more'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a ten-runner race shows every plank and no toggle', (
    tester,
  ) async {
    await _pump(tester, 10);

    expect(find.byType(LeaderboardPlank), findsNWidgets(10));
    expect(_toggle, findsNothing);

    await _teardown(tester);
  });

  testWidgets('past ten runners the board collapses to eight planks', (
    tester,
  ) async {
    await _pump(tester, 16);

    expect(find.byType(LeaderboardPlank), findsNWidgets(8));
    expect(_toggle, findsOneWidget);
    // 16 runners, 8 shown, viewer is Runner 1 and already visible.
    expect(find.text('SHOW 8 MORE'), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets('a collapsed paged board offers exactly one control', (
    tester,
  ) async {
    // 20 of 445 loaded: the roster is both collapsed locally AND incomplete on
    // the server, the state that used to stack "SHOW 425 MORE" on top of
    // "SHOW 12 MORE" with disagreeing counts.
    await _pump(
      tester,
      20,
      pagination: const {
        'offset': 0,
        'limit': 20,
        'total': 445,
        'hasMore': true,
        'nextOffset': 20,
      },
    );

    expect(find.byType(LeaderboardPlank), findsNWidgets(8));
    expect(_toggle, findsOneWidget);
    expect(_loadMore, findsNothing);
    // The count describes what THIS tap does: reveal the 12 already loaded.
    expect(find.text('SHOW 12 MORE'), findsOneWidget);

    // Expanding reveals the rest of the page and only then offers the fetch.
    await tester.ensureVisible(_toggle);
    await tester.pump();
    await tester.tap(_toggle);
    await tester.pump();

    expect(find.byType(LeaderboardPlank), findsNWidgets(20));
    expect(_loadMore, findsOneWidget);
    expect(find.text('SHOW 425 MORE'), findsOneWidget);
    expect(find.text('SHOW LESS'), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets('the toggle expands the full board and collapses it again', (
    tester,
  ) async {
    await _pump(tester, 16);

    // The board sits well down the page, so bring the control on-screen before
    // tapping — otherwise the hit lands outside the test viewport.
    await tester.ensureVisible(_toggle);
    await tester.pump();
    await tester.tap(_toggle);
    await tester.pump();

    expect(find.byType(LeaderboardPlank), findsNWidgets(16));
    expect(find.text('SHOW LESS'), findsOneWidget);

    await tester.ensureVisible(_toggle);
    await tester.pump();
    await tester.tap(_toggle);
    await tester.pump();

    expect(find.byType(LeaderboardPlank), findsNWidgets(8));

    await _teardown(tester);
  });

  testWidgets('a viewer below the cut keeps their own plank pinned', (
    tester,
  ) async {
    // Runner 14 sits 14th, well outside the visible eight.
    await _pump(tester, 16, myUserId: 'user-14');

    // Eight visible rows plus the pinned self row.
    expect(find.byType(LeaderboardPlank), findsNWidgets(9));
    expect(
      find.descendant(
        of: find.byType(LeaderboardPlank),
        matching: find.text('@Runner 14 (you)'),
      ),
      findsOneWidget,
    );
    // The skipped ranks are marked, so the pinned plank doesn't read as 9th.
    expect(find.text('• • •'), findsOneWidget);
    // The pinned row is not double-counted in the hidden total.
    expect(find.text('SHOW 7 MORE'), findsOneWidget);

    await _teardown(tester);
  });
}
