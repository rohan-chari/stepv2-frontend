import 'dart:math';

/// Versioned, viewer-scoped current challenge state. Invalid projections never
/// manufacture an admission action or expose a guessed private race.
class SeededChallengeJoin {
  const SeededChallengeJoin({
    required this.state,
    required this.windowStart,
    required this.windowEnd,
    this.raceId,
    this.participantCount,
    this.scoringStartsAt,
    this.reason,
  });

  final String state;
  final DateTime windowStart;
  final DateTime windowEnd;
  final String? raceId;
  final int? participantCount;
  final DateTime? scoringStartsAt;
  final String? reason;
  String get windowKey =>
      '${windowStart.toUtc().toIso8601String()}/${windowEnd.toUtc().toIso8601String()}';

  static SeededChallengeJoin? parse(Object? value) {
    if (value is! Map || value['version'] != 1) return null;
    final state = text(value['state']);
    final start = date(value['windowStart']);
    final end = date(value['windowEnd']);
    if (!const [
          'JOINABLE',
          'JOINED',
          'FORFEITED',
          'UNAVAILABLE',
        ].contains(state) ||
        start == null ||
        end == null ||
        !end.isAfter(start)) {
      return null;
    }
    final race = text(value['raceId']);
    final scoring = date(value['scoringStartsAt']);
    final count = nonnegativeInt(value['participantCount']);
    if (state == 'JOINED' &&
        (race == null ||
            scoring == null ||
            count == null ||
            scoring.isBefore(start) ||
            !scoring.isBefore(end))) {
      return null;
    }
    return SeededChallengeJoin(
      state: state ?? 'UNAVAILABLE',
      windowStart: start,
      windowEnd: end,
      raceId: state == 'JOINED' || state == 'FORFEITED' ? race : null,
      participantCount: state == 'JOINED' ? count : null,
      scoringStartsAt: scoring,
      reason: text(value['reason']),
    );
  }

  static String? text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value : null;
  static DateTime? date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;
  static int? nonnegativeInt(Object? value) =>
      value is num &&
          value.isFinite &&
          value >= 0 &&
          value == value.truncateToDouble()
      ? value.toInt()
      : null;
}

class SeededChallengeJoinResult {
  const SeededChallengeJoinResult({
    required this.seedKind,
    required this.raceId,
    required this.participantId,
    required this.windowStart,
    required this.windowEnd,
    required this.joinedAt,
    required this.scoringStartsAt,
    required this.raceStatus,
    required this.alreadyJoined,
  });
  final String seedKind;
  final String raceId;
  final String participantId;
  final DateTime windowStart;
  final DateTime windowEnd;
  final DateTime joinedAt;
  final DateTime scoringStartsAt;
  final String raceStatus;
  final bool alreadyJoined;

  SeededChallengeJoin get projection => SeededChallengeJoin(
    state: 'JOINED',
    windowStart: windowStart,
    windowEnd: windowEnd,
    raceId: raceId,
    scoringStartsAt: scoringStartsAt,
  );

  static SeededChallengeJoinResult? parse(Object? value) {
    if (value is! Map ||
        value['joined'] != true ||
        value['alreadyJoined'] is! bool) {
      return null;
    }
    final seed = SeededChallengeJoin.text(value['seedKind']);
    final race = SeededChallengeJoin.text(value['raceId']);
    final participant = SeededChallengeJoin.text(value['participantId']);
    final start = SeededChallengeJoin.date(value['windowStart']);
    final end = SeededChallengeJoin.date(value['windowEnd']);
    final joined = SeededChallengeJoin.date(value['joinedAt']);
    final scoring = SeededChallengeJoin.date(value['scoringStartsAt']);
    final status = SeededChallengeJoin.text(value['raceStatus']);
    if (!const ['DAILY_10K', 'WEEKLY_50K'].contains(seed) ||
        race == null ||
        participant == null ||
        start == null ||
        end == null ||
        !end.isAfter(start) ||
        joined == null ||
        scoring == null ||
        scoring.isBefore(start) ||
        !scoring.isBefore(end) ||
        !const ['ACTIVE', 'COMPLETED', 'CANCELLED'].contains(status)) {
      return null;
    }
    return SeededChallengeJoinResult(
      seedKind: seed ?? '',
      raceId: race,
      participantId: participant,
      windowStart: start,
      windowEnd: end,
      joinedAt: joined,
      scoringStartsAt: scoring,
      raceStatus: status ?? '',
      alreadyJoined: value['alreadyJoined'] == true,
    );
  }
}

/// UUID v4 without adding a platform dependency. Kept for the screen lifetime
/// and reused for uncertain network outcomes in the same account/seed/window.
String newSeededChallengeRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
