/// Playable base characters ("animals").
///
/// The backend identifies a purchased character by its shop-item `assetKey`
/// (e.g. `corgi_puppy`), delivered as the `animal` field on social payloads
/// and as the CHARACTER entry of the catalog's `equipped` map. A null,
/// missing, or unrecognized value always resolves to the default capybara —
/// an older backend (or a newer one with animals we don't bundle) must never
/// break rendering.
class AnimalSprite {
  const AnimalSprite({required this.asset, required this.frameCount});

  /// Horizontal walk-cycle sheet, frames laid out left-to-right.
  final String asset;
  final int frameCount;
}

const String kDefaultAnimal = 'capybara';

const Map<String, AnimalSprite> kAnimalSprites = {
  kDefaultAnimal: AnimalSprite(
    asset: 'assets/images/capybara_walk_right.png',
    frameCount: 6,
  ),
  'corgi_puppy': AnimalSprite(
    asset: 'assets/images/corgi_puppy_walk_right_short_ears.png',
    frameCount: 6,
  ),
};

AnimalSprite animalSpriteFor(String? animal) {
  return kAnimalSprites[animal] ?? kAnimalSprites[kDefaultAnimal]!;
}

/// Parses the `animal` field from a backend payload map. Defensive: anything
/// that isn't a non-empty string reads as "default capybara" (null).
String? animalFromJson(dynamic value) {
  if (value is String && value.trim().isNotEmpty) return value;
  return null;
}

/// Applies an accessory's per-animal placement override on top of its base
/// (capybara) renderMetadata. Overrides live at
/// `renderMetadata.perAnimal.<animal>.{offsetX,offsetY,rotation,scale}` and
/// are authored via the admin accessory tuner. Missing/malformed blocks fall
/// back to the base metadata unchanged.
Map<String, dynamic> renderMetadataForAnimal(
  Map<String, dynamic> metadata,
  String? animal,
) {
  if (animal == null) return metadata;
  final perAnimal = metadata['perAnimal'];
  if (perAnimal is! Map) return metadata;
  final override = perAnimal[animal];
  if (override is! Map) return metadata;
  return {
    ...metadata,
    ...override.map((key, value) => MapEntry(key.toString(), value)),
  };
}
