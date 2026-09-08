import '../demo/demo_race_api_service.dart';
import '../demo/demo_race_engine.dart';
import '../services/backend_api_service.dart';
import '../tutorial/tutorial_preview_data.dart';
import 'preview_billing_controller.dart';

/// Offline wire fixtures for the real preview screens. DemoRaceApiService
/// shadows the remaining race/social/chat paths; the source guard tests both.
class PreviewBillingApi extends DemoRaceApiService {
  PreviewBillingApi(this.controller)
    : super(
        DemoRaceEngine(myUserId: controller.userId, myDisplayName: 'Rohan'),
      ) {
    seedRaceInventory();
  }

  final PreviewBillingController controller;
  final TutorialPreviewBackendApiService _profile =
      TutorialPreviewBackendApiService();
  final Map<String, String> _equipment = {};
  final Map<String, Map<String, dynamic>> _purchases = {};
  static const raceId = 'billing-preview-race';

  void seedRaceInventory() {
    controller.raceItems.clear();
    controller.createBoxes(2, held: true);
    for (final id in controller.createBoxes(2)) {
      controller.raceItems[id] = {
        'id': id,
        'powerupId': id,
        'type': null,
        'rarity': null,
        'status': 'MYSTERY_BOX',
        'upgradeLevel': 0,
        'rerolledAt': null,
      };
    }
  }

  int _price(int base) =>
      controller.snapshot.isMember ? (base * 85 / 100).ceil() : base;
  Map<String, dynamic> _pricing(int base) => {
    'priceCoins': _price(base),
    'basePriceCoins': base,
    'discountPercent': controller.snapshot.isMember ? 15 : 0,
  };

  List<Map<String, dynamic>> get _cosmetics => [
    for (final entry in const [
      ('wizard_hat', 'Wizard Hat', 'HEAD', 400),
      ('baseball_cap', 'Baseball Cap', 'HEAD', 200),
      ('sunglasses', 'Sunglasses', 'FACE', 250),
      ('gold_chain', 'Gold Chain', 'NECK', 300),
    ])
      {
        'id': entry.$1,
        'sku': entry.$1,
        'assetKey': entry.$1,
        'name': entry.$2,
        'slot': entry.$3,
        'description': 'A little personality for your capybara.',
        ..._pricing(entry.$4),
        'owned': controller.ownedCosmetics.contains(entry.$1),
        'equipped':
            _equipment[entry.$3] == entry.$1 &&
            controller.ownedCosmetics.contains(entry.$1),
      },
  ];
  Map<String, dynamic> get _equipped => {
    for (final row in _cosmetics)
      if (row['equipped'] == true) row['slot'] as String: row,
  };
  List<Map<String, dynamic>> get _powerups => [
    for (final entry in const [
      ('GHOST_PEPPER', 'Ghost Pepper', 200),
      ('PROTEIN_SHAKE', 'Protein Shake', 100),
      ('POCKET_WATCH', 'Pocket Watch', 300),
    ])
      {
        'sku': entry.$1,
        'powerupType': entry.$1,
        'name': entry.$2,
        'description': 'Add one to your stash for your next race.',
        'category': 'POWERUP',
        ..._pricing(entry.$3),
        'ownedQuantity': controller.powerupInventory[entry.$1] ?? 0,
      },
  ];

  @override
  bool get shopAdUnlockSupported => false;
  @override
  Future<ShopBootstrapResult> fetchShopBootstrap({
    required String identityToken,
    required String localDate,
  }) async => ShopBootstrapResult(
    supported: true,
    cosmetics: await fetchShopCatalog(identityToken: identityToken),
    powerups: await fetchPowerupShopCatalog(identityToken: identityToken),
    inventory: await fetchPowerupInventory(identityToken: identityToken),
  );
  @override
  Future<Map<String, dynamic>> fetchShopCatalog({
    required String identityToken,
  }) async => {
    'coins': controller.auth.coins,
    'items': _cosmetics,
    'ownedItemIds': controller.ownedCosmetics.toList(),
    'equipped': _equipped,
  };
  @override
  Future<Map<String, dynamic>> fetchPowerupShopCatalog({
    required String identityToken,
  }) async => {'coins': controller.auth.coins, 'items': _powerups};
  @override
  Future<Map<String, dynamic>> fetchPowerupInventory({
    required String identityToken,
  }) async => {
    'items': [
      for (final row in controller.powerupInventory.entries)
        {'powerupType': row.key, 'quantity': row.value},
    ],
  };

  Future<void> _spend(int coins) async {
    if (controller.auth.coins < coins) {
      throw const ApiException('Not enough preview coins.');
    }
    await controller.auth.updateCoins(controller.auth.coins - coins);
  }

  @override
  Future<Map<String, dynamic>> purchaseShopItem({
    required String identityToken,
    required String itemId,
    required String idempotencyKey,
    int? expectedPriceCoins,
  }) async {
    final previous = _purchases[idempotencyKey];
    if (previous != null) return {...previous, 'idempotent': true};
    final item = _cosmetics.where((row) => row['id'] == itemId).firstOrNull;
    if (item == null) throw const ApiException('Preview item unavailable.');
    if (!controller.ownedCosmetics.contains(itemId)) {
      await _spend(item['priceCoins'] as int);
      controller.ownedCosmetics.add(itemId);
    }
    return _purchases[idempotencyKey] = {
      'coins': controller.auth.coins,
      'item': {...item, 'owned': true},
    };
  }

  @override
  Future<Map<String, dynamic>> purchasePowerupItem({
    required String identityToken,
    String? sku,
    String? powerupType,
    required String idempotencyKey,
    int? expectedPriceCoins,
  }) async {
    final previous = _purchases[idempotencyKey];
    if (previous != null) return {...previous, 'idempotent': true};
    final item = _powerups
        .where((row) => row['sku'] == sku || row['powerupType'] == powerupType)
        .firstOrNull;
    if (item == null) throw const ApiException('Preview powerup unavailable.');
    await _spend(item['priceCoins'] as int);
    final type = item['powerupType'] as String;
    final quantity = (controller.powerupInventory[type] ?? 0) + 1;
    controller.powerupInventory[type] = quantity;
    return _purchases[idempotencyKey] = {
      'coins': controller.auth.coins,
      'inventory': {'powerupType': type, 'quantity': quantity},
    };
  }

  @override
  Future<Map<String, dynamic>> equipAccessory({
    required String identityToken,
    required String slot,
    required String? itemId,
  }) async {
    if (itemId != null && !controller.ownedCosmetics.contains(itemId)) {
      throw const ApiException('Unlock this preview accessory first.');
    }
    if (itemId == null) {
      _equipment.remove(slot);
    } else {
      _equipment[slot] = itemId;
    }
    return {'equipped': _equipped};
  }

  @override
  Future<Map<String, dynamic>> completeShopTutorial({
    required String identityToken,
  }) async => {'shopTutorialCompletedAt': '2026-09-01T00:00:00Z'};
  @override
  Future<Map<String, dynamic>> unlockPowerupWithAds({
    required String identityToken,
    required String sku,
    required String idempotencyKey,
    String? localDate,
  }) async =>
      throw const ApiException('Ads are unavailable in this offline preview.');
  @override
  Future<Map<String, dynamic>> unlockShopItemWithAds({
    required String identityToken,
    required String sku,
    required String idempotencyKey,
    String? localDate,
  }) async =>
      throw const ApiException('Ads are unavailable in this offline preview.');

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async =>
      {
        'id': controller.userId,
        'displayName': 'Rohan',
        'coins': controller.auth.coins,
        'heldCoins': 0,
      };
  @override
  Future<Map<String, dynamic>> fetchStats({required String identityToken}) =>
      _profile.fetchStats(identityToken: identityToken);
  @override
  Future<Map<String, dynamic>> fetchStepCalendar({
    required String identityToken,
    required String month,
  }) => _profile.fetchStepCalendar(identityToken: identityToken, month: month);
  @override
  Future<Map<String, dynamic>> fetchReferralStatus({
    required String identityToken,
  }) async => const {};
  @override
  Future<Map<String, dynamic>> fetchGetCoinsStatus({
    required String identityToken,
    required String localDate,
  }) async => const {'claimedToday': false};
  @override
  Future<Map<String, dynamic>> claimAdCoinReward({
    required String identityToken,
    required String localDate,
  }) async =>
      throw const ApiException('Ads are unavailable in this offline preview.');

  Map<String, dynamic> get _race => {
    ...engine.raceDetails(engine.now(), wallNow: DateTime.now()),
    'id': raceId,
    'name': 'Bara+ Box Preview',
    'endsAt': DateTime.now().add(const Duration(days: 2)).toIso8601String(),
  };
  Map<String, dynamic> get _progress {
    final progress = engine.raceProgress(engine.now());
    final raw = progress['powerupData'];
    return {
      ...progress,
      'powerupData': {
        if (raw is Map<String, dynamic>) ...raw,
        'boxReroll': true,
        'boxRerollBatch': true,
        'powerupSlots': 4,
        'inventory': [
          for (final row in controller.raceItems.values)
            Map<String, dynamic>.from(row),
        ],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async => _race;
  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async => _progress;
  @override
  Future<RaceBootstrapResult> fetchRaceBootstrap({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async => RaceBootstrapResult(
    supported: true,
    race: _race,
    progress: _progress,
    globalPowerupInventory: await fetchPowerupInventory(
      identityToken: identityToken,
    ),
  );
  @override
  Future<RaceProgressResult> fetchRaceProgressCompact({
    required String identityToken,
    required String raceId,
  }) async => RaceProgressResult(
    progress: _progress,
    globalPowerupInventory: await fetchPowerupInventory(
      identityToken: identityToken,
    ),
    hasCompactInventory: true,
  );
  @override
  Future<RaceProgressResult> fetchRaceProgressParticipants({
    required String identityToken,
    required String raceId,
    int offset = 0,
    int limit = 10,
  }) async => RaceProgressResult(
    progress: _progress,
    globalPowerupInventory: await fetchPowerupInventory(
      identityToken: identityToken,
    ),
    hasCompactInventory: true,
  );
  @override
  Future<Map<String, dynamic>> fetchRacePowerupUseContext({
    required String identityToken,
    required String raceId,
  }) async => {
    'participants': _progress['participants'],
    'powerupData': _progress['powerupData'],
  };

  @override
  Future<Map<String, dynamic>> openMysteryBox({
    required String identityToken,
    required String raceId,
    required String powerupId,
  }) async {
    final row = controller.raceItems[powerupId];
    if (row == null || row['status'] != 'MYSTERY_BOX') {
      throw const ApiException('Preview box unavailable.');
    }
    final opened = {
      ...row,
      'type': 'PROTEIN_SHAKE',
      'status': 'HELD',
      'rarity': 'COMMON',
      'autoActivated': false,
      'coinsSpent': 0,
    };
    controller.raceItems[powerupId] = opened;
    return {'result': opened};
  }

  @override
  Future<Map<String, dynamic>> openMysteryBoxBatch({
    required String identityToken,
    required String raceId,
    required List<String> powerupIds,
    bool includeQueued = true,
    int maxCount = 20,
  }) async => {
    'results': [
      for (final id in powerupIds.take(maxCount))
        (await openMysteryBox(
          identityToken: identityToken,
          raceId: raceId,
          powerupId: id,
        ))['result'],
    ],
  };
  @override
  Future<Map<String, dynamic>> discardPowerup({
    required String identityToken,
    required String raceId,
    required String powerupId,
  }) async {
    controller.raceItems.remove(powerupId);
    return {};
  }

  @override
  Future<Map<String, dynamic>> usePowerup({
    required String identityToken,
    required String raceId,
    required String powerupId,
    String? targetUserId,
    String? targetDirection,
    String? targetEffectId,
    int upgradeLevel = 0,
  }) async => throw const ApiException(
    'Powerup activation is outside this billing preview. Try the reroll action.',
  );
  @override
  Future<Map<String, dynamic>> useQuicksand({
    required String identityToken,
    required String raceId,
    required String powerupId,
    required List<String> targetUserIds,
  }) async => throw const ApiException(
    'Powerup activation is outside this billing preview.',
  );
  @override
  Future<Map<String, dynamic>> redeemPowerupToRace({
    required String identityToken,
    required String raceId,
    required String powerupType,
  }) async => throw const ApiException(
    'Adding shop powerups to races is outside this billing preview.',
  );
  @override
  Future<Map<String, dynamic>> rematchRace({
    required String identityToken,
    required String raceId,
    required String idempotencyKey,
  }) async =>
      throw const ApiException('Rematches are outside this billing preview.');
  @override
  Future<Map<String, dynamic>> updateRaceSeriesSubscription({
    required String identityToken,
    required String seriesId,
    required bool active,
  }) async => throw const ApiException(
    'Recurring races are outside this billing preview.',
  );
  @override
  Future<Map<String, dynamic>> updateRaceSeries({
    required String identityToken,
    required String seriesId,
    required bool enabled,
  }) async => throw const ApiException(
    'Recurring races are outside this billing preview.',
  );
}
