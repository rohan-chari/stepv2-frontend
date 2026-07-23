/// Shared boost/debuff classification for effects currently on ME, used by both
/// the race-detail ACTIVE EFFECTS groups and the races-tab badge cluster so the
/// two surfaces can never disagree.
///
/// Boost = self-cast (`sourceUserId == myUserId`), unattributed (null/empty
/// source, which we can't blame on anyone so we don't call it an attack), or a
/// group rally that lands on you as a buff even when a rival/teammate cast it.
/// Everything else from another racer is a debuff.
///
/// The progress payload's `onSelf` flag is deliberately NOT an input: the
/// backend sets `onSelf: e.targetUserId === userId`, so it is true for EVERY
/// row targeting the viewer — rival attacks included — and consulting it once
/// put a rival-cast Rainstorm under BOOSTS. Classification is source-based only.
bool effectIsBoost({
  required String? type,
  required String? sourceUserId,
  required String? myUserId,
}) {
  const groupBoosts = {'UPRISING', 'RALLY_FLAG'};
  if (type != null && groupBoosts.contains(type)) return true;
  return sourceUserId == null ||
      sourceUserId.isEmpty ||
      sourceUserId == myUserId;
}
