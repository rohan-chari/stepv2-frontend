// Display-only naming for the auto-seeded daily/weekly public challenges.
//
// The backend bakes a literal name into each seeded race row (e.g.
// "Daily 10K Sprint", "Weekly 50K Challenge"), and those names vary. The step
// count in them is misleading — the races aren't about hitting a fixed step
// total — so we present a clean, stable label keyed off the seed kind instead.
//
// The mapping keys on `seedKind` (the stable backend identifier), not the name
// string, so it never mis-renames a user-created race that happens to mention
// "10K". Any race without a known seed kind keeps its real name.

/// Returns the display name for a race, overriding the seeded daily/weekly
/// challenges with clean labels. Falls back to [fallbackName] for every other
/// race (including unknown/absent seed kinds, which is the safe default when
/// talking to a backend version that doesn't send `seedKind`).
String raceDisplayName(String? seedKind, String fallbackName) {
  switch (seedKind) {
    case 'DAILY_10K':
      return 'Daily Challenge';
    case 'WEEKLY_50K':
      return 'Weekly Challenge';
    default:
      return fallbackName;
  }
}
