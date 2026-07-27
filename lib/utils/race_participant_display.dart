DateTime? _parseFinishedAt(dynamic value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

List<Map<String, dynamic>> sortRaceParticipantsForDisplay(
  List<Map<String, dynamic>> participants,
) {
  final indexed = participants.asMap().entries.map((entry) {
    return (index: entry.key, participant: entry.value);
  }).toList();

  int sortBucket(Map<String, dynamic> participant) {
    if (participant['stealthed'] == true) return 0;
    if (_parseFinishedAt(participant['finishedAt']) != null) return 1;
    return 2;
  }

  indexed.sort((a, b) {
    final bucketCompare = sortBucket(
      a.participant,
    ).compareTo(sortBucket(b.participant));
    if (bucketCompare != 0) return bucketCompare;

    final aFinishedAt = _parseFinishedAt(a.participant['finishedAt']);
    final bFinishedAt = _parseFinishedAt(b.participant['finishedAt']);
    if (aFinishedAt != null && bFinishedAt != null) {
      final finishedCompare = aFinishedAt.compareTo(bFinishedAt);
      if (finishedCompare != 0) return finishedCompare;
    }

    final aSteps = (a.participant['totalSteps'] as num?)?.toInt() ?? 0;
    final bSteps = (b.participant['totalSteps'] as num?)?.toInt() ?? 0;
    final stepCompare = bSteps.compareTo(aSteps);
    if (stepCompare != 0) return stepCompare;

    return a.index.compareTo(b.index);
  });

  return indexed.map((entry) => entry.participant).toList(growable: false);
}

/// Contract §5 C1 — the SERVER's placement for a participant row, 1-based.
///
/// Additive and nullable: absent on an older backend, and null when the backend
/// deliberately hides it (Detour Sign). Anything that isn't a number reads as
/// absent, so a future retype can never crash a frozen client.
int? serverPlacementOf(Map<String, dynamic> participant) {
  final raw = participant['placement'];
  return raw is num ? raw.toInt() : null;
}

/// The display order for a race's participants (items 12/16).
///
/// Prefers the server's placement — the ONE rank every surface agrees on —
/// but only when every row carries it. A partial payload (or none at all, i.e.
/// an older backend, or a race under Detour Sign where placements are masked)
/// falls back wholesale to [sortRaceParticipantsForDisplay], which is exactly
/// the behaviour that shipped. Mixing the two would produce a list ordered by
/// one rule and numbered by another.
List<Map<String, dynamic>> orderRaceParticipantsForDisplay(
  List<Map<String, dynamic>> participants,
) {
  final placed = participants.every((p) => serverPlacementOf(p) != null);
  if (!placed || participants.isEmpty) {
    return sortRaceParticipantsForDisplay(participants);
  }

  // Decorated sort — Dart's List.sort is not guaranteed stable, and equal
  // placements (the backend can emit ties) must keep their payload order.
  final indexed = participants
      .asMap()
      .entries
      .map((e) => (index: e.key, participant: e.value))
      .toList();
  indexed.sort((a, b) {
    final compare = serverPlacementOf(
      a.participant,
    )!.compareTo(serverPlacementOf(b.participant)!);
    if (compare != 0) return compare;
    return a.index.compareTo(b.index);
  });
  return indexed.map((e) => e.participant).toList(growable: false);
}

String formatOrdinal(int value) {
  final mod100 = value % 100;
  if (mod100 >= 11 && mod100 <= 13) {
    return '${value}TH';
  }

  switch (value % 10) {
    case 1:
      return '${value}ST';
    case 2:
      return '${value}ND';
    case 3:
      return '${value}RD';
    default:
      return '${value}TH';
  }
}
