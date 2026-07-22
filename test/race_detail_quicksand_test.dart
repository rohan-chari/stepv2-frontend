import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/item_slot.dart';
import 'package:step_tracker/widgets/pill_button.dart';

class _QuicksandApi extends BackendApiService {
  List<String>? sentTargets;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async => {
    'id': raceId,
    'name': 'Sand Trap Sprint',
    'status': 'ACTIVE',
    'maxDurationDays': 7,
    'buyInAmount': 0,
    'myStatus': 'ACCEPTED',
    'powerupsEnabled': true,
    'endsAt': '2027-12-10T12:00:00.000Z',
    'participants': [
      {'userId': 'me', 'displayName': 'Bara', 'status': 'ACCEPTED'},
      for (var i = 1; i <= 4; i++)
        {'userId': 'u$i', 'displayName': 'Rival $i', 'status': 'ACCEPTED'},
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
      for (var i = 1; i <= 4; i++)
        {'userId': 'u$i', 'displayName': 'Rival $i', 'totalSteps': 4000 - i},
    ],
    'powerupData': {
      'enabled': true,
      'inventory': [
        {'id': 'sand-1', 'type': 'QUICKSAND', 'status': 'HELD'},
      ],
      'powerupSlots': 3,
      'queuedBoxCount': 0,
      'activeEffects': [],
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

  @override
  Future<Map<String, dynamic>> useQuicksand({
    required String identityToken,
    required String raceId,
    required String powerupId,
    required List<String> targetUserIds,
  }) async {
    sentTargets = targetUserIds;
    return {
      'result': {
        'outcome': 'PARTIAL',
        'blocked': false,
        'targetResults': [
          for (final id in targetUserIds)
            {
              'targetUserId': id,
              'outcome': id == 'u2' ? 'BLOCKED' : 'APPLIED',
              'expiresAt': id == 'u2' ? null : '2027-01-01T02:00:00Z',
            },
        ],
      },
    };
  }
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Quicksand selects at most three and presents ordered results', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _QuicksandApi();
    await tester.pumpWidget(
      MaterialApp(
        home: RaceDetailScreen(
          authService: await _auth(),
          raceId: 'race-sand',
          backendApiService: api,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final held = find.byWidgetPredicate(
      (widget) => widget is ItemSlot && widget.state == ItemSlotState.held,
    );
    await tester.ensureVisible(held);
    await tester.tap(held);
    await tester.pump(const Duration(milliseconds: 400));
    final useButton = tester.widget<PillButton>(
      find.widgetWithText(PillButton, 'USE'),
    );
    useButton.onPressed!();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('quicksand-target-list')), findsOneWidget);
    expect(find.text('0/3'), findsOneWidget);
    for (var i = 1; i <= 3; i++) {
      final tile = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'Rival $i'),
      );
      tile.onChanged!(true);
      await tester.pump();
    }
    expect(find.text('3/3'), findsOneWidget);
    final fourth = find.widgetWithText(CheckboxListTile, 'Rival 4');
    expect(tester.widget<CheckboxListTile>(fourth).onChanged, isNull);

    tester
        .widget<PillButton>(find.byKey(const Key('quicksand-confirm')))
        .onPressed!();
    await tester.pump();
    expect(api.sentTargets, const ['u1', 'u2', 'u3']);
    expect(find.text('QUICKSAND RESULTS'), findsOneWidget);
    expect(find.text('FROZEN'), findsNWidgets(2));
    expect(find.text('BLOCKED'), findsOneWidget);
  });
}
