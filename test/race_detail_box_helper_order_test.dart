import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/item_slot.dart';

/// Spec §3.2 — the compact next-powerup helper must render ABOVE the box/item
/// slots Row, not below it.
class _HelperApi extends BackendApiService {
  _HelperApi({
    this.inventory = const [
      {'id': 'held-1', 'type': 'PROTEIN_SHAKE', 'status': 'HELD'},
      {'id': 'box-1', 'type': 'MYSTERY_BOX', 'status': 'MYSTERY_BOX'},
      {'id': 'box-2', 'type': 'MYSTERY_BOX', 'status': 'MYSTERY_BOX'},
    ],
  });

  final Object? inventory;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async => {
    'id': raceId,
    'name': 'Helper Alley',
    'status': 'ACTIVE',
    'maxDurationDays': 7,
    'buyInAmount': 0,
    'myStatus': 'ACCEPTED',
    'powerupsEnabled': true,
    'endsAt': '2027-12-10T12:00:00.000Z',
    'participants': [
      {'userId': 'me', 'displayName': 'Bara', 'status': 'ACCEPTED'},
      {'userId': 'u1', 'displayName': 'Otter42', 'status': 'ACCEPTED'},
    ],
  };

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async => {
    'status': 'ACTIVE',
    'participants': [
      {'userId': 'me', 'displayName': 'Bara', 'totalSteps': 5000},
      {'userId': 'u1', 'displayName': 'Otter42', 'totalSteps': 4000},
    ],
    'powerupData': {
      'enabled': true,
      'inventory': inventory,
      'powerupSlots': 3,
      'queuedBoxCount': 0,
      'activeEffects': const [],
      'powerupStepInterval': 5000,
      'stepsUntilNextPowerup': 1000,
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
      const {'coins': 300, 'heldCoins': 0};
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'token',
    'auth_user_identifier': 'user',
    'auth_session_token': 'session',
    'auth_backend_user_id': 'me',
    'auth_display_name': 'Bara',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Future<void> _pump(
  WidgetTester tester,
  _HelperApi api, {
  Size surfaceSize = const Size(430, 2400),
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: RaceDetailScreen(
        key: ValueKey(api),
        authService: await _auth(),
        raceId: 'race-helper',
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('next-powerup helper renders above the box/item slots Row', (
    tester,
  ) async {
    await _pump(tester, _HelperApi());

    final helper = find.textContaining('NEXT POWERUP IN');
    expect(helper, findsOneWidget);

    final slots = find.byWidgetPredicate((widget) => widget is ItemSlot);
    expect(slots, findsWidgets);

    final helperY = tester.getTopLeft(helper).dy;
    final firstSlotY = tester.getTopLeft(slots.first).dy;
    expect(
      helperY,
      lessThan(firstSlotY),
      reason: 'helper text should sit above the slots Row (spec §3.2)',
    );
  });

  testWidgets('POWERUPS renders above STANDINGS on race detail', (
    tester,
  ) async {
    await _pump(tester, _HelperApi());

    final powerups = find.text('POWERUPS');
    final standings = find.text('STANDINGS');

    expect(powerups, findsOneWidget);
    expect(standings, findsOneWidget);
    expect(
      tester.getTopLeft(powerups).dy,
      lessThan(tester.getTopLeft(standings).dy),
      reason: 'the actionable POWERUPS section should precede the standings',
    );
  });

  testWidgets(
    'unopened boxes go directly to POWERUPS without a separate alert',
    (tester) async {
      await _pump(tester, _HelperApi());

      final box = find.byType(MysteryBoxButton);
      expect(box, findsNWidgets(2));
      expect(find.text('POWERUPS'), findsOneWidget);
      expect(find.text('2 unopened boxes. Open them now'), findsNothing);
      expect(find.byKey(const Key('unopened-box-alert-card')), findsNothing);
      expect(find.text('MYSTERY BOXES'), findsNothing);
    },
  );

  testWidgets('unopened boxes remain actionable in the focus row', (
    tester,
  ) async {
    await _pump(tester, _HelperApi());

    final boxes = find.byType(MysteryBoxButton);
    expect(boxes, findsNWidgets(2));
    expect(
      tester
          .widgetList<MysteryBoxButton>(boxes)
          .every((box) => box.onTap != null && box.crateSize == 68),
      isTrue,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is ItemSlot && widget.state == ItemSlotState.empty,
      ),
      findsNothing,
      reason: 'an unopened box must occupy its original inventory slot',
    );
  });

  testWidgets('one unopened box is centered with no empty slot cards', (
    tester,
  ) async {
    await _pump(
      tester,
      _HelperApi(
        inventory: const [
          {'id': 'box-1', 'type': 'MYSTERY_BOX', 'status': 'MYSTERY_BOX'},
        ],
      ),
    );

    final focusRow = find.byKey(const Key('mystery-box-focus-row'));
    expect(focusRow, findsOneWidget);
    expect(
      tester.widget<Row>(focusRow).mainAxisAlignment,
      MainAxisAlignment.center,
    );
    expect(
      tester.widget<MysteryBoxButton>(find.byType(MysteryBoxButton)).crateSize,
      76,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is ItemSlot && widget.state == ItemSlotState.empty,
      ),
      findsNothing,
    );
  });

  testWidgets('one-box POWERUPS card stays compact with wrapped helper copy', (
    tester,
  ) async {
    await _pump(
      tester,
      _HelperApi(
        inventory: const [
          {'id': 'box-1', 'type': 'MYSTERY_BOX', 'status': 'MYSTERY_BOX'},
        ],
      ),
      surfaceSize: const Size(320, 2400),
    );

    final card = find.byKey(const Key('race-powerups-card'));
    expect(card, findsOneWidget);
    expect(
      tester.widget<Text>(find.textContaining('NEXT POWERUP IN')).textAlign,
      TextAlign.center,
    );
    expect(
      tester.getSize(card).height,
      lessThanOrEqualTo(170),
      reason: 'helper, crate, and OPEN label should read as one compact group',
    );
  });

  testWidgets('two and three unopened boxes distribute across one row', (
    tester,
  ) async {
    for (final count in [2, 3]) {
      await _pump(
        tester,
        _HelperApi(
          inventory: [
            for (var i = 0; i < count; i++)
              {'id': 'box-$i', 'type': 'MYSTERY_BOX', 'status': 'MYSTERY_BOX'},
          ],
        ),
      );

      final focusRow = find.byKey(const Key('mystery-box-focus-row'));
      expect(focusRow, findsOneWidget);
      expect(
        tester.widget<Row>(focusRow).mainAxisAlignment,
        MainAxisAlignment.spaceEvenly,
      );
      final boxes = find.byType(MysteryBoxButton);
      expect(boxes, findsNWidgets(count));
      expect(
        tester
            .widgetList<MysteryBoxButton>(boxes)
            .every((box) => box.crateSize == (count == 2 ? 68 : 60)),
        isTrue,
      );
      if (count == 3) {
        final tops = [
          for (final box in boxes.evaluate())
            tester.getTopLeft(find.byWidget(box.widget)).dy,
        ];
        expect(tops.toSet(), hasLength(1));
      }
    }
  });

  testWidgets('three standalone boxes fit a compact phone width', (
    tester,
  ) async {
    await _pump(
      tester,
      _HelperApi(
        inventory: const [
          {'id': 'box-1', 'type': 'MYSTERY_BOX', 'status': 'MYSTERY_BOX'},
          {'id': 'box-2', 'type': 'MYSTERY_BOX', 'status': 'MYSTERY_BOX'},
          {'id': 'box-3', 'type': 'MYSTERY_BOX', 'status': 'MYSTERY_BOX'},
        ],
      ),
      surfaceSize: const Size(320, 2400),
    );

    final boxes = find.byType(MysteryBoxButton);
    expect(boxes, findsNWidgets(3));
    expect(
      boxes.evaluate().every(
        (element) => tester.getSize(find.byWidget(element.widget)).width <= 90,
      ),
      isTrue,
      reason: 'equal flexible targets must fit the 268px POWERUPS card width',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('malformed unopened-box ids are visibly disabled', (
    tester,
  ) async {
    await _pump(
      tester,
      _HelperApi(
        inventory: const [
          {'id': '', 'type': 'MYSTERY_BOX', 'status': 'MYSTERY_BOX'},
          {'id': 7, 'type': 'MYSTERY_BOX', 'status': 'MYSTERY_BOX'},
        ],
      ),
    );

    expect(
      tester
          .widgetList<MysteryBoxButton>(find.byType(MysteryBoxButton))
          .every((box) => box.onTap == null),
      isTrue,
    );
  });

  testWidgets('malformed inventories render safely without an alert card', (
    tester,
  ) async {
    final cases = <_HelperApi>[
      _HelperApi(inventory: const []),
      _HelperApi(
        inventory: const [
          {'id': 'held-1', 'type': 'PROTEIN_SHAKE', 'status': 'HELD'},
        ],
      ),
      _HelperApi(
        inventory: const [
          {'id': 'queued-1', 'type': 'MYSTERY_BOX', 'status': 'QUEUED'},
        ],
      ),
      _HelperApi(inventory: null),
      _HelperApi(
        inventory: const [
          'not-a-map',
          {'id': '', 'status': 'MYSTERY_BOX'},
          {'id': 7, 'status': 'MYSTERY_BOX'},
          {'id': 'held-bad', 'status': 'HELD', 'type': 7, 'rarity': {}},
        ],
      ),
      _HelperApi(inventory: 'not-a-list'),
    ];

    for (final api in cases) {
      await _pump(tester, api);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('unopened-box-alert-card')), findsNothing);
    }
  });

  testWidgets('a malformed held item is inert when tapped', (tester) async {
    await _pump(
      tester,
      _HelperApi(
        inventory: const [
          {'id': 'held-bad', 'status': 'HELD', 'type': 7, 'rarity': {}},
        ],
      ),
    );

    final malformedHeldSlot = find.byWidgetPredicate(
      (widget) => widget is ItemSlot && widget.state == ItemSlotState.held,
    );
    expect(malformedHeldSlot, findsOneWidget);
    expect(tester.widget<ItemSlot>(malformedHeldSlot).onTap, isNull);

    await tester.tap(malformedHeldSlot);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
