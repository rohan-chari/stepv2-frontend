class ChallengeSyncDay {
  const ChallengeSyncDay({
    required this.date,
    required this.startsAt,
    required this.endsAt,
  });

  final DateTime date;
  final DateTime startsAt;
  final DateTime endsAt;

  factory ChallengeSyncDay.fromJson(Map<String, dynamic> json) {
    final date = _parseDate(json['date'] as String?);
    final startsAt = _parseInstant(json['startsAt'] as String?);
    final endsAt = _parseInstant(json['endsAt'] as String?);

    if (date == null ||
        startsAt == null ||
        endsAt == null ||
        !endsAt.isAfter(startsAt)) {
      throw const FormatException('Invalid challenge sync day');
    }

    return ChallengeSyncDay(date: date, startsAt: startsAt, endsAt: endsAt);
  }

  factory ChallengeSyncDay.localToday(DateTime now) {
    final localDayStart = DateTime(now.year, now.month, now.day);

    return ChallengeSyncDay(
      date: DateTime.utc(now.year, now.month, now.day),
      startsAt: localDayStart,
      endsAt: now,
    );
  }

  static DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) return null;

    final parts = value.split('-');
    if (parts.length != 3) return null;

    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;

    return DateTime.utc(year, month, day);
  }

  static DateTime? _parseInstant(String? value) {
    if (value == null || value.isEmpty) return null;

    return DateTime.tryParse(value);
  }
}
