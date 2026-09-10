/// Additive wardrobe v1 wire model. Missing authority disables writes.
const wardrobeContract = 'character-wardrobes-v1';
const wardrobeSlots = ['HEAD', 'FACE', 'NECK', 'BACK', 'FEET'];
Map<String, dynamic> wardrobeMap(Object? value) => value is Map
    ? {
        for (final entry in value.entries)
          if (entry.key is String) entry.key as String: entry.value,
      }
    : {};
String? wardrobeString(Object? value) =>
    value is String && value.isNotEmpty ? value : null;
int? wardrobeRevision(Object? value) =>
    value is int && value >= 0 && value <= 9007199254740991 ? value : null;
List<Map<String, dynamic>> wardrobeMaps(Object? value) =>
    value is List ? value.whereType<Map>().map(wardrobeMap).toList() : [];

int? wardrobeCoinPrice(Object? value) =>
    value is num &&
        value.isFinite &&
        value >= 0 &&
        value == value.roundToDouble()
    ? value.toInt()
    : null;

class CharacterOutfit {
  CharacterOutfit.fromJson(Object? raw) {
    final json = wardrobeMap(raw);
    revision = wardrobeRevision(json['revision']);
    final rawSlots = wardrobeMap(json['slots']);
    var valid =
        raw is Map &&
        rawSlots.length == wardrobeSlots.length &&
        wardrobeSlots.every(rawSlots.containsKey);
    slots = {
      for (final slot in wardrobeSlots) slot: wardrobeString(rawSlots[slot]),
    };
    for (final entry in rawSlots.entries) {
      if (!wardrobeSlots.contains(entry.key) ||
          (entry.value != null && wardrobeString(entry.value) == null)) {
        valid = false;
      }
    }
    final occupied = slots.values.whereType<String>().toList();
    if (occupied.toSet().length != occupied.length) valid = false;
    items = wardrobeMaps(json['items']);
    final ids = <String>{};
    for (final item in items) {
      final id = wardrobeString(item['id']);
      final slot = wardrobeString(item['slot']);
      if (id == null ||
          slot == null ||
          !wardrobeSlots.contains(slot) ||
          slots[slot] != id ||
          !ids.add(id)) {
        valid = false;
      }
    }
    for (final id in slots.values.whereType<String>()) {
      if (!ids.contains(id)) valid = false;
    }
    hasHiddenItems = json['hasHiddenItems'] == true;
    editable =
        valid &&
        revision != null &&
        json['editable'] == true &&
        !hasHiddenItems;
    unavailableItemIds = json['unavailableItemIds'] is List
        ? (json['unavailableItemIds'] as List).whereType<String>().toSet()
        : {};
  }
  late final int? revision;
  late final bool editable;
  late final bool hasHiddenItems;
  late final Map<String, String?> slots;
  late final List<Map<String, dynamic>> items;
  late final Set<String> unavailableItemIds;
}

class ShopCharacter {
  ShopCharacter.fromJson(Map<String, dynamic> json)
    : key = wardrobeString(json['characterKey']) ?? '',
      name =
          wardrobeString(json['name']) ??
          (json['characterKey'] == 'default' ? 'Capybara' : 'Character'),
      item = wardrobeMap(json['item']),
      owned = json['owned'] == true,
      active = json['owned'] == true && json['active'] == true,
      canPurchase = json['owned'] == false && json['canPurchase'] == true,
      canActivate = json['owned'] == true && json['canActivate'] == true,
      canEdit = json['owned'] == true && json['canEdit'] == true,
      availability = wardrobeString(json['availability']) ?? 'unavailable',
      outfit = json['outfit'] is Map
          ? CharacterOutfit.fromJson(json['outfit'])
          : null;
  final String key, name, availability;
  final Map<String, dynamic> item;
  final bool owned, active, canPurchase, canActivate, canEdit;
  final CharacterOutfit? outfit;
  bool get valid =>
      key == 'default' ||
      (key.isNotEmpty && item['id'] == key && item['slot'] == 'CHARACTER');
  String? get animal => wardrobeString(item['assetKey']);
}

class WardrobeAccessory {
  WardrobeAccessory.fromJson(Map<String, dynamic> json)
    : item = wardrobeMap(json['item']),
      owned = json['owned'] == true,
      canPurchase = json['owned'] == false && json['canPurchase'] == true,
      canSelect = json['canSelect'] == true,
      canPreview = json['canPreview'] == true,
      fit = wardrobeString(json['fit']) ?? 'preservation-only',
      unavailableReason = wardrobeString(json['unavailableReason']);
  final Map<String, dynamic> item;
  final bool owned, canPurchase, canSelect, canPreview;
  final String fit;
  final String? unavailableReason;
  String get id => wardrobeString(item['id']) ?? '';
  String get slot => wardrobeString(item['slot']) ?? '';
  bool get valid => id.isNotEmpty && wardrobeSlots.contains(slot);
}

class CharacterWardrobe {
  CharacterWardrobe.fromJson(Map<String, dynamic> json)
    : key = wardrobeString(json['characterKey']) ?? '',
      name = wardrobeString(json['name']) ?? 'Capybara',
      outfit = CharacterOutfit.fromJson(json['outfit']),
      appearanceRevision = wardrobeRevision(json['appearanceRevision']),
      active = json['active'] == true,
      canActivate = json['canActivate'] == true,
      accessories = wardrobeMaps(
        json['accessories'],
      ).map(WardrobeAccessory.fromJson).where((item) => item.valid).toList(),
      nextCursor = wardrobeString(json['nextCursor']);
  final String key, name;
  final CharacterOutfit outfit;
  final int? appearanceRevision;
  final bool active, canActivate;
  final List<WardrobeAccessory> accessories;
  final String? nextCursor;
}
