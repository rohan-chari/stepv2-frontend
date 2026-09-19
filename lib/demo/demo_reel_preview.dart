/// Local-only reel preview used by the onboarding/demo race.
///
/// The demo never talks to the backend, so it must provide the same lightweight
/// preview contract the real race endpoint normally supplies. These are the
/// three scripted tutorial box outcomes, so every decorative reel tile is a
/// real powerup the tutorial can actually award.
const Map<String, dynamic> demoReelDropOdds = {
  'reelPreviewAvailable': true,
  'byType': {
    'PROTEIN_SHAKE': 1 / 3,
    'COMPRESSION_SOCKS': 1 / 3,
    'SHORTCUT': 1 / 3,
  },
};

const Map<String, String> demoReelRarityByType = {
  'PROTEIN_SHAKE': 'COMMON',
  'COMPRESSION_SOCKS': 'RARE',
  'SHORTCUT': 'RARE',
};
