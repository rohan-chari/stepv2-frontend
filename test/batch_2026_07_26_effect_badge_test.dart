import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';

/// Item 15 — the active-effect badge painted a near-white `textLight` plate
/// behind every PowerupIcon, in BOTH themes. Coin Flip exposed it worst (a
/// small round coin with a big transparent margin) but the plate is
/// type-agnostic.
///
/// Item 15's fix was a polarity-tinted low-alpha fill inside a `woodDark`
/// frame. That frame read as a dark green chip glued to the sprite on a cream
/// standings row, so the badge now paints NO plate at all — the sprites carry
/// their own black keylines. These tests keep their original job (the plate
/// must never come back) with the target moved from "the tint" to "nothing";
/// night-mode legibility is now a halo shaped like the art, covered in
/// effect_badge_transparent_test.dart.

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

BoxDecoration _plateDecoration(WidgetTester tester) {
  final container = tester.widget<Container>(
    find
        .byKey(
          find
                  .byKey(const Key('participant-effect-plate-boost'))
                  .evaluate()
                  .isNotEmpty
              ? const Key('participant-effect-plate-boost')
              : const Key('participant-effect-plate-debuff'),
        )
        .first,
  );
  return container.decoration as BoxDecoration;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a self-cast effect gets a boost-tinted plate', (tester) async {
    final api = _EffectsApi(
      activeEffects: const [
        {
          'type': 'COIN_FLIP',
          'targetUserId': 'u2',
          'sourceUserId': 'u2',
          'onSelf': true,
        },
      ],
    );
    await _pump(tester, api, night: false);

    final palette = AppColors.of(
      tester.element(
        find.byKey(const Key('participant-effect-plate-boost')).first,
      ),
    );
    final decoration = _plateDecoration(tester);
    expect(decoration.color, isNot(palette.textLight));
    expect(decoration.color, isNot(Colors.transparent));
    expect(decoration.border, isNotNull);
  });

  testWidgets('a rival-cast effect gets a debuff-tinted plate', (tester) async {
    final api = _EffectsApi(
      activeEffects: const [
        {
          'type': 'LEG_CRAMP',
          'targetUserId': 'u2',
          'sourceUserId': 'u1',
          'onSelf': true,
        },
      ],
    );
    await _pump(tester, api, night: false);

    final palette = AppColors.of(
      tester.element(
        find.byKey(const Key('participant-effect-plate-debuff')).first,
      ),
    );
    expect(_plateDecoration(tester).color, isNot(palette.textLight));
    expect(_plateDecoration(tester).color, isNot(Colors.transparent));
    expect(_plateDecoration(tester).border, isNotNull);
  });

  testWidgets('night mode uses a tinted plate, never near-white', (
    tester,
  ) async {
    final api = _EffectsApi(
      activeEffects: const [
        {
          'type': 'COIN_FLIP',
          'targetUserId': 'u2',
          'sourceUserId': 'u2',
          'onSelf': true,
        },
      ],
    );
    await _pump(tester, api, night: true);

    expect(_plateDecoration(tester).color, isNot(AppPalette.night.textLight));
    expect(_plateDecoration(tester).color, isNot(Colors.transparent));
  });
}
