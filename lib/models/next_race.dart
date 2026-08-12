class OpenRaceSummary {
  const OpenRaceSummary({
    required this.id,
    required this.name,
    required this.participantCount,
    this.maxParticipants,
    this.creatorName,
  });

  final String id;
  final String name;
  final int participantCount;
  final int? maxParticipants;
  final String? creatorName;

  static OpenRaceSummary? tryParse(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final name = value['name'];
    if (id is! String || id.trim().isEmpty || name is! String) return null;
    final creator = value['creator'];
    final creatorName = creator is Map && creator['displayName'] is String
        ? creator['displayName'] as String
        : null;
    return OpenRaceSummary(
      id: id.trim(),
      name: name.trim().isEmpty ? 'Open race' : name.trim(),
      participantCount: value['participantCount'] is num
          ? (value['participantCount'] as num).toInt().clamp(0, 1000000)
          : 0,
      maxParticipants: value['maxParticipants'] is num
          ? (value['maxParticipants'] as num).toInt()
          : null,
      creatorName: creatorName,
    );
  }
}

class NextRaceState {
  const NextRaceState({
    required this.resolved,
    required this.eligible,
    required this.discoveryEnabled,
    required this.createEnabled,
    required this.openRaces,
  });

  final bool resolved;
  final bool eligible;
  final bool discoveryEnabled;
  final bool createEnabled;
  final List<OpenRaceSummary> openRaces;

  bool get visible =>
      resolved && eligible && (createEnabled || openRaces.isNotEmpty);

  static NextRaceState? tryParse(Object? value) {
    if (value is! Map ||
        value['resolved'] is! bool ||
        value['eligible'] is! bool ||
        value['createEnabled'] is! bool) {
      return null;
    }
    final rawRows = value['openRaces'];
    final rows = rawRows is List
        ? rawRows
              .map(OpenRaceSummary.tryParse)
              .whereType<OpenRaceSummary>()
              .take(3)
              .toList(growable: false)
        : const <OpenRaceSummary>[];
    return NextRaceState(
      resolved: value['resolved'] == true,
      eligible: value['eligible'] == true,
      discoveryEnabled: value['discoveryEnabled'] == true,
      createEnabled: value['createEnabled'] == true,
      openRaces: rows,
    );
  }
}

bool isAutomaticStartRace(Map<String, dynamic> race) =>
    race['isPublic'] == true &&
    race['creationSource'] == 'QUICK_CREATE' &&
    race['startPolicy'] == 'ON_MINIMUM_PARTICIPANTS';
