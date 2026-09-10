import 'character_wardrobe.dart';
import '../widgets/home_course_track.dart' show normalizedAccessoriesForAnimal;

/// A server-authorized render context. It never grants ownership or edit rights.
class AccessoryPreview {
  const AccessoryPreview({
    required this.characterName,
    required this.characterItem,
    required this.animal,
    required this.accessories,
    required this.usedFallbackCharacter,
  });
  final String characterName;
  final Map<String, dynamic> characterItem;
  final String? animal;
  final List<Map<String, dynamic>> accessories;
  final bool usedFallbackCharacter;

  static AccessoryPreview? parse(Object? raw, String expectedItemId) {
    final json = wardrobeMap(raw);
    if (json['itemId'] != expectedItemId ||
        json['canPreview'] != true ||
        json['usedFallbackCharacter'] is! bool) {
      return null;
    }
    final character = wardrobeMap(json['character']);
    final key = wardrobeString(character['characterKey']);
    final name = wardrobeString(character['name']);
    if (key == null || name == null) return null;
    final item = wardrobeMap(character['item']);
    String? animal;
    if (key == 'default') {
      if (character['item'] != null) return null;
    } else {
      animal = wardrobeString(item['assetKey']);
      if (animal == null || item['id'] != key || item['slot'] != 'CHARACTER') {
        return null;
      }
    }
    final rawAccessories = json['accessories'];
    if (rawAccessories is! List || rawAccessories.isEmpty) return null;
    final accessories = wardrobeMaps(rawAccessories);
    if (accessories.length != rawAccessories.length) return null;
    final ids = <String>{}, slots = <String>{};
    for (final accessory in accessories) {
      final id = wardrobeString(accessory['id']);
      final slot = wardrobeString(accessory['slot']);
      if (id == null ||
          slot == null ||
          !wardrobeSlots.contains(slot) ||
          !ids.add(id) ||
          !slots.add(slot)) {
        return null;
      }
    }
    if (!ids.contains(expectedItemId) ||
        normalizedAccessoriesForAnimal(accessories, animal).length !=
            accessories.length) {
      return null;
    }
    return AccessoryPreview(
      characterName: name,
      characterItem: item,
      animal: animal,
      accessories: accessories,
      usedFallbackCharacter: json['usedFallbackCharacter'] == true,
    );
  }
}
