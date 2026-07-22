/// Parsed result of `GET /races/discovery-summary` (spec §6.2).
///
/// Every committable field is nullable: a field is non-null ONLY when the
/// backend's matching `resolved` bit is `true` AND the value has the correct
/// type. A `null` field means "retain the last known value" — a partial backend
/// failure must never turn a previously nonzero public count into zero or erase
/// previously loaded featured content.
class RaceDiscoverySummary {
  const RaceDiscoverySummary({
    this.unsupported = false,
    this.publicRaceCount,
    this.featuredRaces,
    this.featuredTournaments,
  });

  /// True only after a definite 404 (endpoint absent). The caller then runs the
  /// legacy featured/public/tournament discovery calls in parallel.
  final bool unsupported;

  final int? publicRaceCount;
  final List<Map<String, dynamic>>? featuredRaces;
  final List<Map<String, dynamic>>? featuredTournaments;

  /// A summary carrying no committable fields (malformed/transient failure);
  /// the caller keeps its last known values and does NOT fall back to legacy.
  static const RaceDiscoverySummary empty = RaceDiscoverySummary();

  static const RaceDiscoverySummary unsupportedResult = RaceDiscoverySummary(
    unsupported: true,
  );

  /// Parses a decoded `200` body, honoring the `resolved` bits. Absent/invalid
  /// `resolved` maps default every bit to `false` (retain last known).
  factory RaceDiscoverySummary.fromJson(Map<String, dynamic> json) {
    final resolved = json['resolved'];
    final resolvedMap = resolved is Map<String, dynamic>
        ? resolved
        : const <String, dynamic>{};

    bool isResolved(String key) => resolvedMap[key] == true;

    int? count;
    final rawCount = json['publicRaceCount'];
    if (isResolved('publicRaceCount') && rawCount is int && rawCount >= 0) {
      count = rawCount;
    }

    List<Map<String, dynamic>>? races;
    final rawRaces = json['featuredRaces'];
    if (isResolved('featuredRaces') && rawRaces is List) {
      races = rawRaces.whereType<Map<String, dynamic>>().toList(
        growable: false,
      );
    }

    List<Map<String, dynamic>>? tournaments;
    final rawTournaments = json['featuredTournaments'];
    if (isResolved('featuredTournaments') && rawTournaments is List) {
      tournaments = rawTournaments.whereType<Map<String, dynamic>>().toList(
        growable: false,
      );
    }

    return RaceDiscoverySummary(
      publicRaceCount: count,
      featuredRaces: races,
      featuredTournaments: tournaments,
    );
  }
}
