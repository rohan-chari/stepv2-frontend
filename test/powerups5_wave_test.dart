import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/constants/powerup_copy.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/utils/team_race.dart';
import 'package:step_tracker/widgets/powerup_icon.dart';

/// §7/§9 powerups5 wave — the 11 new store-only powerups: shop render, copy +
/// icon wiring, targeting classification, and the Bounty ahead-of-me filter.

const _wave5 = <String, String>{
  'UPRISING': 'Uprising',
  'GHOST_PEPPER': 'Ghost Pepper',
  'COIN_FLIP': 'Coin Flip',
  'MYSTERY_POTION': 'Mystery Potion',
  'DECOY': 'Decoy',
  'POWER_OUTAGE': 'Power Outage',
  'UMBRELLA': 'Umbrella',
  'RALLY_FLAG': 'Rally Flag',
  'DRILL_SERGEANT': 'Drill Sergeant',
  'PIGGY_BANK': 'Piggy Bank',
  'BOUNTY': 'Bounty',
};

const _wave5Assets = <String, String>{
  'UPRISING': 'uprising',
  'GHOST_PEPPER': 'ghost_pepper',
  'COIN_FLIP': 'coin_flip',
  'MYSTERY_POTION': 'mystery_potion',
  'DECOY': 'decoy',
  'POWER_OUTAGE': 'power_outage',
  'UMBRELLA': 'umbrella',
  'RALLY_FLAG': 'rally_flag',
  'DRILL_SERGEANT': 'drill_sergeant',
  'PIGGY_BANK': 'piggy_bank',
  'BOUNTY': 'bounty',
};

const _wave5Prices = <String, int>{
  'UPRISING': 300,
  'GHOST_PEPPER': 75,
  'COIN_FLIP': 40,
  'MYSTERY_POTION': 40,
  'DECOY': 150,
  'POWER_OUTAGE': 150,
  'UMBRELLA': 75,
  'RALLY_FLAG': 150,
  'DRILL_SERGEANT': 150,
  'PIGGY_BANK': 40,
  'BOUNTY': 75,
};

class _FakeShopApi extends BackendApiService {
  _FakeShopApi({required this.powerupCatalog});

  final Map<String, dynamic> powerupCatalog;

  @override
  Future<Map<String, dynamic>> fetchShopCatalog({
    required String identityToken,
  }) async {
    return {
      'coins': 5000,
      'ownedItemIds': <String>[],
      'equipped': <String, dynamic>{},
      'items': <Map<String, dynamic>>[],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchPowerupShopCatalog({
    required String identityToken,
  }) async {
    return powerupCatalog;
  }

  @override
  Future<Map<String, dynamic>> fetchPowerupInventory({
    required String identityToken,
  }) async {
    return {'items': <Map<String, dynamic>>[]};
  }
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Walker',
    'auth_coins': 5000,
    'auth_held_coins': 0,
  });
  final service = AuthService();
  await service.restoreSession();
  return service;
}

Map<String, dynamic> _catalogWithWave5() => {
      'coins': 5000,
      'items': [
        for (final entry in _wave5.entries)
          {
            'sku': 'POWERUP_${entry.key}',
            'name': entry.value,
            'description': PowerupCopy.descriptionFor(entry.key),
            'priceCoins': _wave5Prices[entry.key],
            'powerupType': entry.key,
            'ownedQuantity': 0,
          },
      ],
    };

Future<void> _pumpShop(
  WidgetTester tester,
  AuthService auth,
  BackendApiService api,
) async {
  await tester.pumpWidget(
    MaterialApp(home: ShopTab(authService: auth, backendApiService: api)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => PowerupCopy.resetForTest());

  group('shop render', () {
    testWidgets('all 11 wave-5 powerups render with real names (no raw enums)',
        (tester) async {
      final auth = await _auth();
      await _pumpShop(
        tester,
        auth,
        _FakeShopApi(powerupCatalog: _catalogWithWave5()),
      );

      for (final entry in _wave5.entries) {
        expect(find.text(entry.value), findsWidgets, reason: entry.value);
        // The failure mode this batch guards: a raw enum string in the UI.
        expect(find.text(entry.key), findsNothing, reason: entry.key);
      }
    });
  });

  group('copy wiring', () {
    test('every wave-5 type resolves a real name and description', () {
      for (final entry in _wave5.entries) {
        expect(PowerupCopy.nameFor(entry.key), entry.value, reason: entry.key);
        expect(PowerupCopy.nameFor(entry.key), isNot(entry.key));
        expect(
          PowerupCopy.descriptionFor(entry.key),
          isNotEmpty,
          reason: entry.key,
        );
      }
    });

    test('effect-rail subtitle is non-empty for every wave-5 type', () {
      // Effect chips render name + effectRailSubtitle + icon; a blank subtitle
      // would strand a chip with no copy.
      for (final type in _wave5.keys) {
        expect(
          PowerupCopy.effectRailSubtitleFor(type),
          isNotEmpty,
          reason: type,
        );
      }
    });

    test('lowercase input still resolves (defensive casing)', () {
      expect(PowerupCopy.nameFor('bounty'), 'Bounty');
      expect(PowerupCopy.nameFor('power_outage'), 'Power Outage');
    });
  });

  group('icon wiring', () {
    test('every wave-5 type resolves its bundled asset path', () {
      for (final entry in _wave5Assets.entries) {
        expect(
          PowerupIcon.assetPathFor(entry.key),
          'assets/images/powerups/${entry.value}.png',
          reason: entry.key,
        );
      }
    });

    testWidgets('every wave-5 icon builds without throwing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                for (final type in _wave5.keys) PowerupIcon(type: type),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(PowerupIcon), findsNWidgets(_wave5.length));
    });
  });

  group('targeting classification', () {
    test('Drill Sergeant and Bounty open the target picker', () {
      expect(kTargetedPowerupTypes, contains('DRILL_SERGEANT'));
      expect(kTargetedPowerupTypes, contains('BOUNTY'));
    });

    test('the self/AoE wave-5 types never open the target picker', () {
      for (final type in [
        'UPRISING',
        'GHOST_PEPPER',
        'COIN_FLIP',
        'MYSTERY_POTION',
        'DECOY',
        'POWER_OUTAGE',
        'UMBRELLA',
        'RALLY_FLAG',
        'PIGGY_BANK',
      ]) {
        expect(kTargetedPowerupTypes, isNot(contains(type)), reason: type);
      }
    });

    test('existing targeted types are unchanged', () {
      for (final type in ['LEG_CRAMP', 'SHORTCUT', 'LEECH', 'HITCHHIKE']) {
        expect(kTargetedPowerupTypes, contains(type), reason: type);
      }
    });
  });

  group('Bounty ahead-of-me filter', () {
    final targets = <Map<String, dynamic>>[
      {'userId': 'a', 'totalSteps': 5000},
      {'userId': 'b', 'totalSteps': 12000},
      {'userId': 'c', 'totalSteps': 9000},
      {'userId': 'd'}, // no steps -> treated as 0, behind
    ];

    test('keeps only rivals strictly ahead of me', () {
      final ahead =
          TeamRace.targetsAheadOf(targets: targets, myTotalSteps: 9000);
      final ids = ahead.map((t) => t['userId']).toList();
      // b (12000) is ahead; c is tied (not ahead); a and d are behind.
      expect(ids, ['b']);
    });

    test('empty when nobody is ahead', () {
      final ahead =
          TeamRace.targetsAheadOf(targets: targets, myTotalSteps: 99999);
      expect(ahead, isEmpty);
    });
  });
}
