/// Optional metadata attached to a page-scoped race-progress response.
///
/// The backend adds these fields without changing the existing progress
/// payload. Every field is optional so an older backend remains a valid
/// response. Invalid values are ignored individually rather than making the
/// race detail screen fail.
class RaceProjectionMetadata {
  const RaceProjectionMetadata({this.generation, this.asOf, this.source});

  final int? generation;
  final String? asOf;
  final String? source;

  static RaceProjectionMetadata? tryParse(Object? raw) {
    if (raw is! Map) return null;

    final rawGeneration = raw['projectionGeneration'];
    final generation = rawGeneration is num && rawGeneration.isFinite
        ? rawGeneration.toInt()
        : rawGeneration is String
        ? int.tryParse(rawGeneration)
        : null;
    final rawAsOf = raw['asOf'];
    final asOf = rawAsOf is String && rawAsOf.isNotEmpty ? rawAsOf : null;
    const sources = {'authoritative', 'stale-fallback', 'legacy'};
    final rawSource = raw['projectionSource'];
    final source = rawSource is String && sources.contains(rawSource)
        ? rawSource
        : null;

    if (generation == null && asOf == null && source == null) return null;
    return RaceProjectionMetadata(
      generation: generation,
      asOf: asOf,
      source: source,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RaceProjectionMetadata &&
      other.generation == generation &&
      other.asOf == asOf &&
      other.source == source;

  @override
  int get hashCode => Object.hash(generation, asOf, source);
}
