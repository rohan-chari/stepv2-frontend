/// App-funded prize pools (spec `docs/app-funded-prize-pools-requirements.md`).
///
/// Buy-ins are gone: every funded race and bracket is paid for by the app, and
/// the pool is `players × durationPoints(days) × 20`, clamped to a ceiling.
///
/// Two things live here:
///
/// 1. **A mirror of the backend duration table.** The create screen previews a
///    pool for a race that does not exist yet, so there is nothing to read from
///    the server — the bands have to be computed locally. `race_prize_pool_test`
///    guards the mirror against the spec's fixtures; if the backend retunes the
///    bands, that test is the tripwire.
/// 2. **A defensive reader for the `prizePool` payload object** (contract §5.1).
///    The backend may be OLDER than this build, in which case `prizePool` is
///    absent and the caller must fall back to today's buy-in / pot UI. `null`
///    always means "not a funded competition — render the legacy money UI".
library;

/// Coins per player per duration point. Server-tunable via `PRIZE_COIN_UNIT`;
/// this mirror is only used for the client-side create preview.
const int kPrizeCoinUnit = 20;

/// Per-race ceiling (`PRIZE_POOL_MAX_COINS`).
const int kPrizePoolMaxCoins = 3200;

/// Per-bracket ceiling — tournaments keep their tighter existing cap
/// (`MAX_CHAMPION_PRIZE`), not the race cap (spec §4.4 / D9).
const int kTournamentPrizePoolMaxCoins = 1000;

/// Duration bands, doubling per band: 1 day = 1, 3 = 2, 7 = 4, 8..30 = 8.
///
/// Monotonic non-decreasing over the whole legal 1..30 range so a shorter race
/// can never out-pay a longer one. Off-band durations from frozen clients
/// (5 days) fall to the lower band.
int prizePoolDurationPoints(int days) {
  if (days <= 1) return 1;
  if (days <= 3) return 2;
  if (days <= 7) return 4;
  return 8;
}

/// `players × durationPoints × unit`, clamped to [max]. A field of fewer than
/// two players mints nothing.
int computePrizePool({
  required int playerCount,
  required int durationDays,
  int max = kPrizePoolMaxCoins,
  int unit = kPrizeCoinUnit,
}) {
  final players = playerCount < 0 ? 0 : playerCount;
  if (players < 2) return 0;
  final raw = players * prizePoolDurationPoints(durationDays) * unit;
  return raw > max ? max : raw;
}

/// `1,600` — thousands-grouped coins for display.
String formatPrizeCoins(int coins) {
  final digits = coins.abs().toString();
  final buffer = StringBuffer(coins < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// The `prizePool` object from a race or tournament payload (contract §5.1/§5.2).
class RacePrizePool {
  const RacePrizePool({
    required this.coins,
    required this.projected,
    required this.atMax,
    required this.playerCount,
    required this.durationDays,
    required this.durationPoints,
    required this.coinUnit,
    required this.maxCoins,
    required this.funded,
  });

  /// The projected pool while pending/active, the settled pool once completed.
  final int coins;

  /// True until the competition completes — every pre-settlement figure is a
  /// projection ("up to"), never a promise.
  final bool projected;

  /// True when the raw formula exceeded [maxCoins], so the UI must stop
  /// implying the pool keeps growing.
  final bool atMax;

  final int playerCount;
  final int durationDays;
  final int durationPoints;
  final int coinUnit;
  final int maxCoins;
  final bool funded;

  /// Reads `race['prizePool']`. Returns null when the field is absent (older
  /// backend), explicitly null (legacy buy-in competition), or malformed.
  static RacePrizePool? fromRace(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    return fromJson(payload['prizePool']);
  }

  static RacePrizePool? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return RacePrizePool(
      coins: _int(raw['coins']) ?? 0,
      // Absent `projected` is treated as "still projected": the safe reading,
      // since it only ever softens the copy ("up to") rather than promising.
      projected: raw['projected'] is bool ? raw['projected'] as bool : true,
      atMax: raw['atMax'] == true,
      playerCount: _int(raw['playerCount']) ?? 0,
      durationDays: _int(raw['durationDays']) ?? 0,
      durationPoints: _int(raw['durationPoints']) ?? 0,
      coinUnit: _int(raw['coinUnit']) ?? kPrizeCoinUnit,
      maxCoins: _int(raw['maxCoins']) ?? kPrizePoolMaxCoins,
      // The object's presence already means "funded"; only an explicit false
      // opts out.
      funded: raw['funded'] != false,
    );
  }

  /// `4 PLAYERS × 3 DAYS` — the derivation shown under a pool figure.
  String get derivation {
    final players = playerCount == 1 ? '1 PLAYER' : '$playerCount PLAYERS';
    final days = durationDays == 1 ? '1 DAY' : '$durationDays DAYS';
    return '$players × $days';
  }

  String get formattedCoins => formatPrizeCoins(coins);

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
