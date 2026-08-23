import 'dart:collection';

/// Server-owned snapshot for one combined race-results rewarded-ad offer.
///
/// This parser is deliberately fail-closed. Every field is additive and may be
/// absent, null, or malformed when the app and backend are on different
/// versions; an invalid object simply means the existing results popup renders
/// without the reward panel.
class RacePayoutDoubleOffer {
  RacePayoutDoubleOffer._({
    required this.offerId,
    required List<String> raceIds,
    required this.baseCoins,
    required this.bonusCoins,
    required this.maxBonusCoins,
    required this.rolling24hRemainingBeforeClaim,
    required this.rewardMode,
  }) : raceIds = UnmodifiableListView<String>(raceIds);

  final String? offerId;
  final List<String> raceIds;
  final int baseCoins;
  final int bonusCoins;
  final int? maxBonusCoins;
  final int? rolling24hRemainingBeforeClaim;
  final String rewardMode;

  bool get isFlat50 => rewardMode == 'flat_50';

  /// v1 is an exact second copy of its server-owned rounded base.
  ///
  /// Older capped offers retain their truthful legacy presentation while a
  /// staged backend rolls forward.
  bool get isFullDouble => bonusCoins == baseCoins;
  bool get isMaximumPartial =>
      maxBonusCoins != null &&
      bonusCoins == maxBonusCoins &&
      bonusCoins < baseCoins;

  static final RegExp _canonicalUuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  static RacePayoutDoubleOffer? tryParse(
    Object? raw, {
    required Iterable<String> popupRaceIds,
    bool requirePendingStatus = false,
  }) {
    final map = _stringMap(raw);
    if (map == null) return null;
    if (requirePendingStatus && map['status'] != 'PENDING') return null;

    final offerIdRaw = map['offerId'];
    final String? offerId;
    if (offerIdRaw == null) {
      offerId = null;
    } else if (offerIdRaw is String && _canonicalUuid.hasMatch(offerIdRaw)) {
      offerId = offerIdRaw;
    } else {
      return null;
    }

    final values = _tryParseSnapshot(map, popupRaceIds: popupRaceIds);
    if (values == null) return null;
    return RacePayoutDoubleOffer._(
      offerId: offerId,
      raceIds: values.raceIds,
      baseCoins: values.baseCoins,
      bonusCoins: values.bonusCoins,
      maxBonusCoins: values.maxBonusCoins,
      rolling24hRemainingBeforeClaim: values.remaining,
      rewardMode: values.rewardMode,
    );
  }
}

class RacePayoutDoubleClaimResult {
  RacePayoutDoubleClaimResult._({
    required this.awarded,
    required this.alreadyClaimed,
    required List<String> raceIds,
    required this.baseCoins,
    required this.bonusCoins,
    required this.maxBonusCoins,
    required this.rolling24hRemainingBeforeClaim,
    required this.coins,
    required this.rewardMode,
  }) : raceIds = UnmodifiableListView<String>(raceIds);

  final bool awarded;
  final bool alreadyClaimed;
  final List<String> raceIds;
  final int baseCoins;
  final int bonusCoins;
  final int? maxBonusCoins;
  final int? rolling24hRemainingBeforeClaim;
  final String rewardMode;

  bool get isFlat50 => rewardMode == 'flat_50';

  /// Null means the claim response was otherwise valid but omitted/malformed
  /// the authoritative balance. The caller must refresh `/auth/me` before
  /// updating the balance badge.
  final int? coins;

  static RacePayoutDoubleClaimResult? tryParse(
    Object? raw, {
    required Iterable<String> popupRaceIds,
  }) {
    final map = _stringMap(raw);
    if (map == null) return null;
    final awarded = map['awarded'];
    final alreadyClaimed = map['alreadyClaimed'];
    if (awarded is! bool || alreadyClaimed is! bool) return null;
    if (awarded == alreadyClaimed) return null;

    final values = _tryParseSnapshot(map, popupRaceIds: popupRaceIds);
    if (values == null) return null;
    final rawCoins = map['coins'];
    final coins = rawCoins is int && rawCoins >= 0 ? rawCoins : null;
    return RacePayoutDoubleClaimResult._(
      awarded: awarded,
      alreadyClaimed: alreadyClaimed,
      raceIds: values.raceIds,
      baseCoins: values.baseCoins,
      bonusCoins: values.bonusCoins,
      maxBonusCoins: values.maxBonusCoins,
      rolling24hRemainingBeforeClaim: values.remaining,
      coins: coins,
      rewardMode: values.rewardMode,
    );
  }
}

({
  List<String> raceIds,
  int baseCoins,
  int bonusCoins,
  int? maxBonusCoins,
  int? remaining,
  String rewardMode,
})?
_tryParseSnapshot(
  Map<String, dynamic> map, {
  required Iterable<String> popupRaceIds,
}) {
  final rawRaceIds = map['raceIds'];
  if (rawRaceIds is! List || rawRaceIds.isEmpty) return null;
  final raceIds = <String>[];
  final unique = <String>{};
  for (final rawId in rawRaceIds) {
    if (rawId is! String || rawId.isEmpty || rawId.trim() != rawId) {
      return null;
    }
    if (!unique.add(rawId)) return null;
    raceIds.add(rawId);
  }

  final popupCounts = <String, int>{};
  for (final id in popupRaceIds) {
    popupCounts[id] = (popupCounts[id] ?? 0) + 1;
  }
  if (raceIds.any((id) => popupCounts[id] != 1)) return null;

  final rewardModeRaw = map['rewardMode'];
  final rewardMode = switch (rewardModeRaw) {
    null when !map.containsKey('rewardMode') => 'legacy_double',
    'flat_50' => 'flat_50',
    'legacy_double' => 'legacy_double',
    _ => null,
  };
  if (rewardMode == null) return null;

  final baseCoins = map['baseCoins'];
  final bonusCoins = map['bonusCoins'];
  if (baseCoins is! int || bonusCoins is! int) {
    return null;
  }
  if (rewardMode == 'flat_50') {
    // Flat offers are additive to the race payout. A zero-prize race and a
    // batch whose fixed reward is larger than its combined payout are both
    // valid; only the server-owned 50 coins per race total is accepted.
    if (baseCoins < 0 || bonusCoins != 50 * raceIds.length) return null;
    return (
      raceIds: raceIds,
      baseCoins: baseCoins,
      bonusCoins: bonusCoins,
      maxBonusCoins: null,
      remaining: null,
      rewardMode: rewardMode,
    );
  }

  if (baseCoins <= 0 || bonusCoins <= 0 || bonusCoins > baseCoins) {
    return null;
  }

  // Cap-less exact offers are the v1 contract. Ignore optional stale metadata
  // here: a deployed backend may keep emitting it while the exact base/bonus
  // values are already authoritative.
  if (bonusCoins == baseCoins) {
    return (
      raceIds: raceIds,
      baseCoins: baseCoins,
      bonusCoins: bonusCoins,
      maxBonusCoins: null,
      remaining: null,
      rewardMode: rewardMode,
    );
  }

  // A non-exact amount is only valid for the legacy capped contract, whose
  // fields prove the actual amount is within the old server allowance.
  final maxBonusCoins = map['maxBonusCoins'];
  final remaining = map['rolling24hRemainingBeforeClaim'];
  if (maxBonusCoins is! int || remaining is! int) return null;
  if (maxBonusCoins <= 0 ||
      maxBonusCoins > 500 ||
      remaining <= 0 ||
      bonusCoins > maxBonusCoins ||
      bonusCoins > remaining) {
    return null;
  }

  return (
    raceIds: raceIds,
    baseCoins: baseCoins,
    bonusCoins: bonusCoins,
    maxBonusCoins: maxBonusCoins,
    remaining: remaining,
    rewardMode: rewardMode,
  );
}

Map<String, dynamic>? _stringMap(Object? raw) {
  if (raw is! Map) return null;
  final result = <String, dynamic>{};
  for (final entry in raw.entries) {
    if (entry.key is! String) return null;
    result[entry.key as String] = entry.value;
  }
  return result;
}
