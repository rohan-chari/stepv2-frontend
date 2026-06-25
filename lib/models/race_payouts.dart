/// Shared race payout-preset definitions and helpers.
///
/// A payout preset decides how a race's buy-in pot is split among finishers.
/// The backend owns the actual coin math; the app only needs the selectable
/// option list (for the create/edit pickers), a line of help text per preset,
/// and a way to read the projected/settled breakdown out of a race payload.
library;

/// (display label, backend enum value) for each selectable payout preset, in
/// picker order. The values must match the backend `RacePayoutPreset` enum
/// exactly. WINNER_TAKES_ALL is the default.
///
/// Note: TOP3_80_15_5 is intentionally not offered here anymore — the backend
/// still accepts it for races created by older app builds, but new races pick
/// from this list only.
const List<(String, String)> payoutPresetOptions = [
  ('WINNER TAKE ALL', 'WINNER_TAKES_ALL'),
  ('TOP 3', 'TOP3_70_20_10'),
  ('TOP HALF', 'TOP_HALF'),
  ('EVERYONE BUT LAST', 'ALL_BUT_LAST'),
];

/// One line explaining a preset, shown under the picker. Every preset except
/// winner-takes-all needs at least 4 accepted runners before the race can start
/// (enforced server-side), so each says so.
String payoutHelpText(String preset) {
  switch (preset) {
    case 'WINNER_TAKES_ALL':
      return 'Winner takes the whole pot.';
    case 'TOP3_70_20_10':
    case 'TOP3_80_15_5':
      return 'Top 3 finishers split the pot. Needs at least 4 accepted '
          'runners to start.';
    case 'TOP_HALF':
      return 'The top half of finishers get paid — the higher you place, the '
          'more you win. Needs at least 4 accepted runners to start.';
    case 'ALL_BUT_LAST':
      return 'Everyone but last place gets paid — the higher you place, the '
          'more you win. Needs at least 4 accepted runners to start.';
    default:
      return 'Needs at least 4 accepted runners to start.';
  }
}

/// Coins won by a single finishing place. `placement` is 1-based (1 = first).
typedef PayoutTier = ({int placement, int amount});

/// The per-place payout breakdown from a race payload, ascending by placement.
///
/// Prefers the variable-length `payoutTiers` list from newer backends. Falls
/// back to the legacy `payouts` {first, second, third} map so the app still
/// renders a breakdown against a backend that predates payoutTiers — and so an
/// older app build that only ever reads first/second/third keeps working. Zero
/// (and missing) amounts are dropped, so winner-takes-all yields a single tier.
/// Returns an empty list when there's nothing to pay (no buy-in / empty pot).
List<PayoutTier> parsePayoutTiers(Map<String, dynamic>? race) {
  if (race == null) return const [];

  final tiers = race['payoutTiers'];
  if (tiers is List) {
    final result = <PayoutTier>[];
    for (final entry in tiers) {
      if (entry is! Map) continue;
      final placement = _asInt(entry['placement']);
      final amount = _asInt(entry['amount']);
      if (placement == null || amount == null || amount <= 0) continue;
      result.add((placement: placement, amount: amount));
    }
    result.sort((a, b) => a.placement.compareTo(b.placement));
    return result;
  }

  final payouts = race['payouts'];
  if (payouts is Map) {
    const legacyKeys = ['first', 'second', 'third'];
    final result = <PayoutTier>[];
    for (var i = 0; i < legacyKeys.length; i++) {
      final amount = _asInt(payouts[legacyKeys[i]]);
      if (amount == null || amount <= 0) continue;
      result.add((placement: i + 1, amount: amount));
    }
    return result;
  }

  return const [];
}

/// Uppercase ordinal label for a placement, e.g. 1 -> "1ST", 12 -> "12TH".
String payoutPlacementLabel(int placement) {
  final mod100 = placement % 100;
  if (mod100 >= 11 && mod100 <= 13) return '${placement}TH';
  return switch (placement % 10) {
    1 => '${placement}ST',
    2 => '${placement}ND',
    3 => '${placement}RD',
    _ => '${placement}TH',
  };
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
