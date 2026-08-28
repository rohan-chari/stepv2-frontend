DateTime? _parseFinishedAt(dynamic value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

/// Converts the truncated Home podium into a viewer-safe projection.
///
/// A legacy payload cannot prove that an omitted racer is not hidden just
/// outside `top3`. In that case the whole rank-bearing podium is suppressed;
/// preserving canonical #1–#3 would reveal the hidden racer's relative place
/// when compared with a privacy-aware surface.
List<Map<String, dynamic>> privacySafeHomeTopThree(Map<String, dynamic> race) {
  final raw =
      (race['top3'] as List?)
          ?.whereType<Map>()
          .map(
            (row) => <String, dynamic>{
              for (final entry in row.entries)
                if (entry.key is String) entry.key as String: entry.value,
            },
          )
          .toList(growable: false) ??
      const <Map<String, dynamic>>[];
  final privacy = race['placementPrivacyActive'];
  if (privacy is! bool) return const <Map<String, dynamic>>[];
  if (!privacy) return raw;

  return [
    for (final entry in raw)
      <String, dynamic>{
        ...entry,
        'rank': entry['isStealthed'] == true || entry['stealthed'] == true
            ? null
            : entry['displayPlacement'],
      },
  ];
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

    final rawASteps = a.participant['totalSteps'];
    final rawBSteps = b.participant['totalSteps'];
    final aSteps = rawASteps is num && rawASteps.isFinite
        ? rawASteps.toInt()
        : 0;
    final bSteps = rawBSteps is num && rawBSteps.isFinite
        ? rawBSteps.toInt()
        : 0;
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
  if (raw is! num || !raw.isFinite || raw != raw.roundToDouble()) return null;
  final value = raw.toInt();
  return value > 0 ? value : null;
}

const _derivedDisplayPlacementKey = '__viewerDisplayPlacement';

/// The privacy-safe rank to paint. A locally derived value wins, followed by
/// the capable backend's additive field, and finally canonical placement when
/// privacy projection was unnecessary.
int? displayPlacementOf(Map<String, dynamic> participant) {
  for (final key in [_derivedDisplayPlacementKey]) {
    final raw = participant[key];
    if (raw is num && raw.isFinite && raw == raw.roundToDouble() && raw > 0) {
      return raw.toInt();
    }
  }
  return serverPlacementOf(participant);
}

/// The display order for a race's participants (items 12/16; stealth fix
/// batch 2026-08-08 item 18).
///
/// Preserves canonical server placement for non-private standings, while a
/// Stealth projection paints a separate viewer-safe rank.
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
///    them). Visible rows receive contiguous display ranks without overwriting
///    their canonical placement. Rows with no trusted placement sort last.
///
/// Callers must render a stealthed row's rank as "?" rather than deriving a
/// number from its position; see `LeaderboardPlank.rankHidden`.
List<Map<String, dynamic>> orderRaceParticipantsForDisplay(
  List<Map<String, dynamic>> participants, {
  bool placementPrivacyActive = false,
}) {
  if (participants.isEmpty) return sortRaceParticipantsForDisplay(participants);

  final placedCount = participants
      .where((p) => serverPlacementOf(p) != null)
      .length;

  // Detour Sign / older backend: nothing to trust, keep shipped behaviour.
  if (placedCount == 0 && !placementPrivacyActive) {
    return sortRaceParticipantsForDisplay(participants);
  }

  final hasMaskedRow = participants.any(
    (participant) =>
        participant['stealthed'] == true &&
        _parseFinishedAt(participant['finishedAt']) == null,
  );

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

    final aPlacement = placementPrivacyActive
        ? _wireDisplayPlacementOf(a.participant)
        : serverPlacementOf(a.participant);
    final bPlacement = placementPrivacyActive
        ? _wireDisplayPlacementOf(b.participant)
        : serverPlacementOf(b.participant);
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
  if (!hasMaskedRow && !placementPrivacyActive) {
    return indexed.map((e) => e.participant).toList(growable: false);
  }

  // A current backend's explicit displayPlacement is retained (important when
  // paging means the hidden row is outside this page). A frozen backend has no
  // privacy flag, so `?, #1, #3` is repaired locally without ever overwriting
  // canonical placement, which remains payout/settlement-only.
  var nextVisiblePlacement = 1;
  return indexed
      .map((entry) {
        final participant = entry.participant;
        final masked =
            participant['stealthed'] == true &&
            _parseFinishedAt(participant['finishedAt']) == null;
        return <String, dynamic>{
          ...participant,
          _derivedDisplayPlacementKey: masked
              ? null
              : placementPrivacyActive
              ? _wireDisplayPlacementOf(participant)
              : nextVisiblePlacement++,
        };
      })
      .toList(growable: false);
}

int? _wireDisplayPlacementOf(Map<String, dynamic> participant) {
  final raw = participant['displayPlacement'];
  if (raw is! num || !raw.isFinite || raw != raw.roundToDouble() || raw <= 0) {
    return null;
  }
  return raw.toInt();
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
