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

/// The display order for a race's participants (items 12/16; stealth fix
/// batch 2026-08-08 item 18).
///
/// Prefers the server's placement — the ONE rank every surface agrees on.
/// There are three cases, and the difference between them is the whole of the
/// "1 2 1 2" bug:
///
///  * **Every row placed** — sort by placement. Unchanged.
///  * **No row placed** — an older backend, or a race under **Detour Sign**,
///    where the backend nulls `placement` on every `stealthed:false` row. The
///    scrambled, unranked standings ARE the illusion, so we keep the wholesale
///    [sortRaceParticipantsForDisplay] fallback and today's rendering. Deriving
///    per-row index ranks here would reproduce the bug in a different mask.
///  * **Some rows placed (stealth)** — the backend masks `placement` on
///    stealthed rows only. The old all-or-nothing rule made ONE stealthed row
///    knock every row back to index ranks, so stealthed rows rendered their
///    array index (1, 2) next to visible rows rendering server placement
///    (1, 2, 3). Now: stealthed rows pin to the top (where the server sorts
///    them), everyone else keeps their true server placement. Rows with no
///    placement that are not stealthed sort last, by payload order — they
///    carry no rank we can trust.
///
/// Callers must render a stealthed row's rank as "?" rather than deriving a
/// number from its position; see `LeaderboardPlank.rankHidden`.
List<Map<String, dynamic>> orderRaceParticipantsForDisplay(
  List<Map<String, dynamic>> participants,
) {
  if (participants.isEmpty) return sortRaceParticipantsForDisplay(participants);

  final placedCount = participants
      .where((p) => serverPlacementOf(p) != null)
      .length;

  // Detour Sign / older backend: nothing to trust, keep shipped behaviour.
  if (placedCount == 0) return sortRaceParticipantsForDisplay(participants);

  // Decorated sort — Dart's List.sort is not guaranteed stable, and equal
  // placements (the backend can emit ties) must keep their payload order.
  final indexed = participants
      .asMap()
      .entries
      .map((e) => (index: e.key, participant: e.value))
      .toList();

  // Bucket 0 pins stealthed rows to the top, matching the server's own sort.
  // Bucket 1 is everyone else. Within bucket 1, an absent placement sorts
  // last rather than pretending to be rank 0.
  int bucketOf(Map<String, dynamic> p) => p['stealthed'] == true ? 0 : 1;

  indexed.sort((a, b) {
    final bucketCompare = bucketOf(
      a.participant,
    ).compareTo(bucketOf(b.participant));
    if (bucketCompare != 0) return bucketCompare;

    final aPlacement = serverPlacementOf(a.participant);
    final bPlacement = serverPlacementOf(b.participant);
    if (aPlacement != null && bPlacement != null) {
      final compare = aPlacement.compareTo(bPlacement);
      if (compare != 0) return compare;
    } else if (aPlacement != null) {
      return -1;
    } else if (bPlacement != null) {
      return 1;
    }

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
