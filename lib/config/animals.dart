/// Playable base characters ("animals").
///
/// The backend identifies a purchased character by its shop-item `assetKey`
/// (e.g. `corgi_puppy`), delivered as the `animal` field on social payloads
/// and as the CHARACTER entry of the catalog's `equipped` map. A null,
/// missing, or unrecognized value always resolves to the default capybara —
/// an older backend (or a newer one with animals we don't bundle) must never
/// break rendering.
class AnimalSprite {
  const AnimalSprite({
    required this.asset,
    required this.frameCount,
    this.baselineOffset = 0,
  });

  /// Horizontal walk-cycle sheet, frames laid out left-to-right.
  final String asset;
  final int frameCount;

  /// Vertical nudge applied to the WHOLE character (body + accessories) so
  /// every animal's feet land on the same ground line, expressed as a fraction
  /// of the rendered frame size. Negative = move up.
  ///
  /// Each sheet pads its subject differently inside the frame box: the capybara
  /// stands with its feet 14/64 of the frame above the bottom edge, the corgi
  /// only 8/64 — so, drawn in identically sized boxes, the corgi visibly sinks
  /// below the capybara. This offset is applied at render time rather than by
  /// re-padding the PNG on purpose: accessory placement is measured against the
  /// frame box, so shifting the pixels inside the sheet would silently
  /// invalidate every tuned `perAnimal` override.
  final double baselineOffset;
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
    // Feet at 56/64 down the frame vs the capybara's 50/64 — lift the corgi by
    // the 6/64 difference so both stand on the same line.
    baselineOffset: -6 / 64,
  ),
  // 704x88 sheet: EIGHT 88x88 frames, not the capybara's six. Frame count is
  // per-animal config, so nothing downstream needs a special case — every
  // consumer reads `frameCount` off the sprite it resolved.
  'turtle': AnimalSprite(
    asset: 'assets/images/turtle_walk_right.png',
    frameCount: 8,
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
