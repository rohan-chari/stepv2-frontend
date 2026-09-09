import 'package:step_tracker/models/character_wardrobe.dart';
import 'package:step_tracker/services/backend_api_service.dart';

/// Adapts existing catalog fixtures to the additive wire contract, so historical
/// purchase/ad assertions run through the real new routes. No live fallback.
/// Tests for frozen-backend degradation deliberately do not use this mixin.
mixin LegacyShopWardrobeFixture on BackendApiService {
  Future<Map<String, dynamic>> wardrobeFixtureCatalog(String token) =>
      fetchShopCatalog(identityToken: token);
  Map<String, dynamic>? fixtureEquipment;
  final Map<String, Map<String, String?>> fixtureOutfits = {};
  final Map<String, int> fixtureRevisions = {};
  int fixtureAppearanceRevision = 0;
  int fixtureCollectionReads = 0;
  int fixtureWardrobeReads = 0;
  int fixtureSaves = 0;
  int fixtureActivations = 0;
  String _active(Map<String, dynamic> catalog) =>
      wardrobeString(
        wardrobeMap(
          (fixtureEquipment ?? wardrobeMap(catalog['equipped']))['CHARACTER'],
        )['id'],
      ) ??
      'default';
  Map<String, String?> _slots(Map<String, dynamic> catalog, String key) =>
      fixtureOutfits[key] ??
      (key == _active(catalog)
          ? {
              for (final slot in wardrobeSlots)
                slot: wardrobeString(
                  wardrobeMap(
                    (fixtureEquipment ??
                        wardrobeMap(catalog['equipped']))[slot],
                  )['id'],
                ),
            }
          : {for (final slot in wardrobeSlots) slot: null});
  Map<String, dynamic> _outfit(Map<String, dynamic> catalog, String key) {
    final slots = _slots(catalog, key);
    final items = <String, Map<String, dynamic>>{
      for (final item in wardrobeMaps(catalog['items']))
        ?wardrobeString(item['id']): item,
      for (final item
          in (fixtureEquipment ?? wardrobeMap(catalog['equipped'])).values)
        ?wardrobeString(wardrobeMap(item)['id']): wardrobeMap(item),
    };
    return {
      'revision': fixtureRevisions[key] ?? 0,
      'editable': true,
      'hasHiddenItems': false,
      'slots': slots,
      'items': [for (final id in slots.values.whereType<String>()) ?items[id]],
      'unavailableItemIds': [],
    };
  }

  bool _owned(Map<String, dynamic> catalog, Map<String, dynamic> item) =>
      item['owned'] == true ||
      (catalog['ownedItemIds'] is List &&
          (catalog['ownedItemIds'] as List).contains(item['id'])) ||
      (fixtureEquipment ?? wardrobeMap(catalog['equipped'])).values.any(
        (value) => wardrobeMap(value)['id'] == item['id'],
      );
  Map<String, dynamic> _envelope(Map<String, dynamic> catalog) => {
    'contract': wardrobeContract,
    'appearanceRevision': fixtureAppearanceRevision,
    'activeCharacterKey': _active(catalog),
    'activeCharacterVisible': true,
    'coins': catalog['coins'],
    'adUnlock': catalog['adUnlock'],
  };
  @override
  Future<Map<String, dynamic>> fetchShopCharacters({
    required String identityToken,
    int limit = 24,
    String? cursor,
    String? localDate,
  }) async {
    fixtureCollectionReads++;
    final catalog = await wardrobeFixtureCatalog(identityToken);
    final characters = wardrobeMaps(
      catalog['items'],
    ).where((item) => item['slot'] == 'CHARACTER').toList();
    return {
      ..._envelope(catalog),
      'characters': [
        {
          'characterKey': 'default',
          'name': 'Capybara',
          'item': null,
          'owned': true,
          'active': _active(catalog) == 'default',
          'canPurchase': false,
          'canActivate': true,
          'canEdit': true,
          'availability': 'available',
          'outfit': _outfit(catalog, 'default'),
        },
        for (final item in characters)
          {
            'characterKey': item['id'],
            'name': item['name'],
            'item': item,
            'owned': _owned(catalog, item),
            'active': _active(catalog) == item['id'],
            'canPurchase': !_owned(catalog, item),
            'canActivate': _owned(catalog, item),
            'canEdit': _owned(catalog, item),
            'availability': 'available',
            'outfit': _owned(catalog, item)
                ? _outfit(catalog, item['id'] as String)
                : null,
          },
      ],
      'nextCursor': null,
    };
  }

  @override
  Future<Map<String, dynamic>> fetchCharacterWardrobe({
    required String identityToken,
    required String characterKey,
    int limit = 24,
    String? cursor,
    String? localDate,
  }) async {
    fixtureWardrobeReads++;
    final catalog = await wardrobeFixtureCatalog(identityToken);
    final items = wardrobeMaps(
      catalog['items'],
    ).where((item) => item['slot'] != 'CHARACTER').toList();
    final start = int.tryParse(cursor ?? '') ?? 0;
    final page = items.skip(start).take(limit).toList();
    return {
      ..._envelope(catalog),
      'characterKey': characterKey,
      'name': characterKey == 'default' ? 'Capybara' : 'Character',
      'active': characterKey == _active(catalog),
      'canActivate': true,
      'outfit': _outfit(catalog, characterKey),
      'accessories': [
        for (final item in page)
          {
            'item': item,
            'owned': _owned(catalog, item),
            'canPurchase': !_owned(catalog, item),
            'canSelect': _owned(catalog, item),
            'canPreview': true,
            'fit': 'approved',
            'unavailableReason': null,
          },
      ],
      'nextCursor': start + page.length < items.length
          ? '${start + page.length}'
          : null,
    };
  }

  @override
  Future<Map<String, dynamic>> saveCharacterOutfit({
    required String identityToken,
    required String characterKey,
    required int expectedOutfitRevision,
    required Map<String, String?> slots,
  }) async {
    fixtureSaves++;
    final catalog = await wardrobeFixtureCatalog(identityToken);
    final previous = _slots(catalog, characterKey);
    final changed = wardrobeSlots
        .where((slot) => slots[slot] != previous[slot])
        .toList();
    Map<String, dynamic> response = {};
    for (final slot in changed) {
      response = await equipAccessory(
        identityToken: identityToken,
        slot: slot,
        itemId: slots[slot],
      );
    }
    fixtureEquipment = wardrobeMap(response['equipped']);
    fixtureOutfits[characterKey] = {
      for (final slot in wardrobeSlots)
        slot: wardrobeString(wardrobeMap(fixtureEquipment?[slot])['id']),
    };
    fixtureRevisions[characterKey] = expectedOutfitRevision + 1;
    fixtureAppearanceRevision++;
    return {
      ..._envelope(catalog),
      'characterKey': characterKey,
      'outfit': _outfit(catalog, characterKey),
      'equipped': fixtureEquipment,
      'appearanceChanged': true,
    };
  }

  @override
  Future<Map<String, dynamic>> activateShopCharacter({
    required String identityToken,
    required String characterKey,
    required int expectedAppearanceRevision,
    required int expectedOutfitRevision,
  }) async {
    fixtureActivations++;
    final catalog = await wardrobeFixtureCatalog(identityToken);
    final response = await equipAccessory(
      identityToken: identityToken,
      slot: 'CHARACTER',
      itemId: characterKey == 'default' ? null : characterKey,
    );
    fixtureEquipment = wardrobeMap(response['equipped']);
    fixtureAppearanceRevision++;
    return {
      ..._envelope(catalog),
      'characterKey': characterKey,
      'outfit': _outfit(catalog, characterKey),
      'equipped': fixtureEquipment,
      'appearanceChanged': true,
    };
  }
}
