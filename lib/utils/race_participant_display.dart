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

    final aSteps = a.participant['totalSteps'] as int? ?? 0;
    final bSteps = b.participant['totalSteps'] as int? ?? 0;
    final stepCompare = bSteps.compareTo(aSteps);
    if (stepCompare != 0) return stepCompare;

    return a.index.compareTo(b.index);
  });

  return indexed.map((entry) => entry.participant).toList(growable: false);
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
