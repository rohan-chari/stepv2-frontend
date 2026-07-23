/// §9.5 — the SINGLE source of powerup copy for the whole app.
///
/// Powerup names/descriptions used to be duplicated across seven Dart files
/// with nothing keeping them in sync, so a backend behaviour change (the Leech
/// duration is the canonical example) silently made the client lie. This file
/// consolidates all seven maps and layers the backend-served catalog on top.
///
/// Resolution order for EVERY string (§9.5.4):
///   1. the current in-memory backend snapshot, when present and non-empty
///   2. the persisted last-known-good backend snapshot
///   3. the bundled emergency value below
///   4. the raw enum string (existing final fallback)
///
/// The bundled maps are deliberately NOT deleted — they are demoted to
/// emergency bootstrap so a brand-new offline install, a first paint before any
/// fetch resolves, and a new client talking to an old backend all still render
/// real copy instead of `LEG_CRAMP`.
///
/// This mirrors the backend-authoritative-with-bundled-fallback shape already
/// used for upgrade costs in `race_detail_screen.dart`.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Powerup types that require picking a rival before use, routing through the
/// race screen's target picker.
///
/// Lives here rather than inside `race_detail_screen.dart` so the
/// targeted/self-only classification is directly testable — shipping a
/// self-only powerup in this list would strand the user on a target picker the
/// server will reject, and omitting a targeted one sends a use request with no
/// target.
///
/// QUICK_RINSE is deliberately ABSENT: it is self-only and instantaneous.
const List<String> kTargetedPowerupTypes = [
  'LEG_CRAMP',
  'SHORTCUT',
  'WRONG_TURN',
  'DETOUR_SIGN',
  'SNEAKY_SWAP',
  // IMPOSTER picks a rival to swap leaderboard display with.
  'IMPOSTER',
  // SIGNAL_JAMMER picks a rival to jam.
  'SIGNAL_JAMMER',
  // LEECH picks a rival to drain.
  'LEECH',
  // HITCHHIKE picks a rival whose effective steps get copied into your score,
  // including boosts and reversals. They keep theirs — nothing is taken.
  'HITCHHIKE',
  // QUICKSAND selects up to three rivals in its dedicated multi-target flow.
  'QUICKSAND',
  // §7 powerups5 — DRILL_SERGEANT dares one rival to hit a step goal.
  'DRILL_SERGEANT',
  // BOUNTY wagers on out-placing one rival ahead of you; the race screen
  // pre-filters the picker to enemies currently ahead (server still validates).
  'BOUNTY',
];

/// Thrown by a fetcher when `/powerups/catalog` answered but not usefully
/// (404 on an older backend, or a 5xx). Always TRANSIENT: the endpoint is never
/// marked permanently unsupported, because the backend deploys independently of
/// an installed app and a session-long lockout would strand the client on stale
/// copy for no reason (§9.5.4).
class PowerupCopyUnavailable implements Exception {
  const PowerupCopyUnavailable(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'PowerupCopyUnavailable($statusCode)';
}

/// One validated catalog row.
class PowerupCopyEntry {
  const PowerupCopyEntry({
    required this.type,
    required this.name,
    required this.description,
    this.shortDescription,
    this.upgradeTierLabels = const [],
  });

  final String type;
  final String name;
  final String description;

  /// Nullable by contract: only 15 of the 26 pre-existing types had one. When
  /// null the caller OMITS the effect-rail subtitle line entirely — it must
  /// never fall back to truncating [description], which would introduce copy
  /// that never previously existed (§9.5.2).
  final String? shortDescription;

  /// 4 entries for upgradeable types, empty otherwise.
  final List<String> upgradeTierLabels;

  Map<String, dynamic> toJson() => {
    'type': type,
    'name': name,
    'description': description,
    'shortDescription': shortDescription,
    'upgradeTierLabels': upgradeTierLabels,
  };
}

/// A fully validated catalog snapshot. Constructed only through
/// [PowerupCopySnapshot.parse], which rejects anything partial or malformed.
class PowerupCopySnapshot {
  const PowerupCopySnapshot({required this.version, required this.entries});

  final String version;
  final Map<String, PowerupCopyEntry> entries;

  /// Validates a `/powerups/catalog` response.
  ///
  /// Returns null — meaning "keep the previous good snapshot" — for anything
  /// partial, empty, duplicate-typed, or malformed. Unknown extra fields are
  /// ignored so a NEWER backend never breaks this build, and a missing
  /// `version` is tolerated because the response is additive-only.
  static PowerupCopySnapshot? parse(dynamic raw) {
    if (raw is! Map) return null;
    final list = raw['powerups'];
    if (list is! List || list.isEmpty) return null;

    final entries = <String, PowerupCopyEntry>{};
    for (final item in list) {
      if (item is! Map) return null;

      final type = _trimmedOrNull(item['type']);
      final name = _trimmedOrNull(item['name']);
      final description = _trimmedOrNull(item['description']);
      // type/name/description are all required; a row missing any of them
      // means the payload is not trustworthy as a whole.
      if (type == null || name == null || description == null) return null;
      // A duplicate type makes the snapshot ambiguous — reject wholesale
      // rather than silently letting last-write-win.
      if (entries.containsKey(type)) return null;

      final tiers = <String>[];
      final rawTiers = item['upgradeTierLabels'];
      if (rawTiers is List) {
        for (final t in rawTiers) {
          final label = _trimmedOrNull(t);
          if (label != null) tiers.add(label);
        }
      }

      entries[type] = PowerupCopyEntry(
        type: type,
        name: name,
        description: description,
        shortDescription: _trimmedOrNull(item['shortDescription']),
        // Only a complete 4-tier ladder is usable; anything else defers to the
        // bundled labels rather than rendering a half-built tier list.
        upgradeTierLabels: tiers.length == 4 ? tiers : const [],
      );
    }

    if (entries.isEmpty) return null;

    return PowerupCopySnapshot(
      version: _trimmedOrNull(raw['version']) ?? '',
      entries: entries,
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'powerups': [for (final e in entries.values) e.toJson()],
  };
}

String? _trimmedOrNull(dynamic value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// The app-wide powerup copy store.
abstract final class PowerupCopy {
  /// Global (NOT user-scoped) persistence key. Copy is the same for everyone,
  /// so a logout or session-capability reset must never delete it (§9.5.4).
  static const _prefsKey = 'powerup_copy_snapshot_v1';

  static PowerupCopySnapshot? _memory;
  static PowerupCopySnapshot? _persisted;
  static Future<bool>? _inFlight;

  /// Always false: a 404/timeout/5xx is transient by contract. Exposed so tests
  /// can assert we never introduce a session-permanent lockout for this
  /// endpoint (unlike the `EndpointSupport` caches used elsewhere).
  static bool get isPermanentlyUnsupported => false;

  /// The user-renderable powerup types this build knows about (28 through the
  /// powerups3 wave, plus the 11 powerups5 store-only additions).
  /// `MYSTERY_BOX` is intentionally excluded — it is an unopened-container
  /// inventory state, not a usable powerup with use-sheet or effect copy.
  static Iterable<String> get bundledTypes => _bundledNames.keys;

  // -- Reads ---------------------------------------------------------------

  /// Display name, e.g. `Leg Cramp`. Never empty: falls back to [type] itself.
  static String nameFor(String? type) {
    if (type == null || type.isEmpty) return '';
    final key = type.toUpperCase();
    return _resolve(key, (e) => e.name) ??
        _bundledNames[key] ??
        _extraDisplayNames[key] ??
        type;
  }

  /// Long use-sheet description. Falls back to an empty string for an unknown
  /// type (callers already render nothing in that case).
  static String descriptionFor(String? type) {
    if (type == null || type.isEmpty) return '';
    final key = type.toUpperCase();
    return _resolve(key, (e) => e.description) ??
        _bundledDescriptions[key] ??
        '';
  }

  /// Short effect-rail label, or null when this type has none.
  ///
  /// Returning null is meaningful: the caller OMITS the subtitle line. It must
  /// never be substituted with a truncated [descriptionFor] (§9.5.2).
  static String? shortDescriptionFor(String? type) {
    if (type == null || type.isEmpty) return null;
    final key = type.toUpperCase();
    final fromSnapshot = _resolve(key, (e) => e.shortDescription);
    if (fromSnapshot != null) return fromSnapshot;
    return _bundledShortDescriptions[key];
  }

  /// The effect-rail subtitle, reproducing the SHIPPED fallback chain exactly:
  /// short description, then the full description, then an empty string.
  ///
  /// 11 of the 26 pre-existing types have no short description and have always
  /// rendered their full description here. Omitting the line for those would
  /// blank a subtitle users see today, so the chain is preserved verbatim
  /// rather than "cleaned up".
  static String effectRailSubtitleFor(String? type) {
    final short = shortDescriptionFor(type);
    if (short != null && short.isNotEmpty) return short;
    return descriptionFor(type);
  }

  /// The 4 upgrade-tier labels, or null when the type is not upgradeable.
  static List<String>? upgradeTierLabelsFor(String? type) {
    if (type == null || type.isEmpty) return null;
    final key = type.toUpperCase();
    for (final snapshot in [_memory, _persisted]) {
      final tiers = snapshot?.entries[key]?.upgradeTierLabels;
      if (tiers != null && tiers.length == 4) return tiers;
    }
    return _bundledUpgradeTierLabels[key];
  }

  /// Whether this type shows the tiered use-modal.
  static bool isUpgradeable(String? type) => upgradeTierLabelsFor(type) != null;

  /// Levels 1 then 2 of the resolution order, for a single string field.
  /// Only a present, non-empty value wins; otherwise we fall through so a
  /// snapshot that simply omits a type can't blank out bundled copy.
  static String? _resolve(String key, String? Function(PowerupCopyEntry) pick) {
    for (final snapshot in [_memory, _persisted]) {
      final entry = snapshot?.entries[key];
      if (entry == null) continue;
      final value = pick(entry);
      if (value != null && value.trim().isNotEmpty) return value;
    }
    return null;
  }

  // -- Refresh / persistence ----------------------------------------------

  /// Loads the persisted last-known-good snapshot. Call once at startup before
  /// the first paint that renders powerup copy; it is cheap and never throws.
  static Future<void> loadPersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      _persisted = PowerupCopySnapshot.parse(jsonDecode(raw));
    } catch (_) {
      // A corrupt or unreadable blob simply means "no persisted copy" — the
      // bundled emergency values take over.
    }
  }

  /// Fetches and installs a new snapshot.
  ///
  /// Returns true only when a fully valid snapshot was installed. Concurrent
  /// calls are COALESCED onto one request so several rebuilding screens can't
  /// stampede the endpoint. Never throws: every failure mode degrades to the
  /// previous snapshot and is retried on the next launch/foreground.
  static Future<bool> refresh({
    required Future<Map<String, dynamic>> Function() fetch,
  }) {
    final existing = _inFlight;
    if (existing != null) return existing;

    final future = _doRefresh(fetch);
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }

  static Future<bool> _doRefresh(
    Future<Map<String, dynamic>> Function() fetch,
  ) async {
    Map<String, dynamic> raw;
    try {
      raw = await fetch();
    } catch (_) {
      // 404 (older backend), timeout, 5xx, socket error — all transient. Keep
      // the previous snapshot and try again next launch/foreground.
      return false;
    }

    final snapshot = PowerupCopySnapshot.parse(raw);
    // Partial/empty/duplicate/malformed: never replace a good snapshot.
    if (snapshot == null) return false;

    _memory = snapshot;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(snapshot.toJson()));
      _persisted = snapshot;
    } catch (_) {
      // Persistence is best-effort; the in-memory snapshot still serves this
      // session even if the write failed.
    }
    return true;
  }

  /// Logout hook. Deliberately a NO-OP for the snapshot: powerup copy is global
  /// rather than user-specific, so signing out must not throw away the
  /// last-known-good catalog (§9.5.4). Present as an explicit seam so a future
  /// "clear everything on logout" sweep can't silently delete it.
  static Future<void> onLogout() async {}

  /// Test-only reset. [keepPersisted] simulates a relaunch: in-memory state is
  /// dropped but SharedPreferences survives.
  static void resetForTest({bool keepPersisted = false}) {
    _memory = null;
    _inFlight = null;
    if (!keepPersisted) _persisted = null;
  }

  // -- Bundled emergency copy ---------------------------------------------
  // Consolidated verbatim from the seven former duplicated maps. Treat these as
  // BOOTSTRAP ONLY: the backend catalog is authoritative. Do not encode a
  // backend-driven number (duration, ratio, price, count) here — that is the
  // exact drift this migration exists to end.

  static const _bundledNames = {
    'LEG_CRAMP': 'Leg Cramp',
    'RED_CARD': 'Red Card',
    'SHORTCUT': 'Shortcut',
    'COMPRESSION_SOCKS': 'Compression Socks',
    'PROTEIN_SHAKE': 'Protein Shake',
    'RUNNERS_HIGH': "Runner's High",
    'SECOND_WIND': 'Second Wind',
    'STEALTH_MODE': 'Stealth Mode',
    'WRONG_TURN': 'Wrong Turn',
    'FANNY_PACK': 'Fanny Pack',
    'TRAIL_MIX': 'Trail Mix',
    'DETOUR_SIGN': 'Detour Sign',
    'LUCKY_HORSESHOE': 'Lucky Horseshoe',
    'CAMPFIRE_REST': 'Campfire Rest',
    'TRAIL_MAGNET': 'Trail Magnet',
    'POCKET_WATCH': 'Pocket Watch',
    'TRAIL_MINE': 'Trail Mine',
    'PINECONE_TOSS': 'Pinecone Toss',
    'SNEAKY_SWAP': 'Sneaky Swap',
    'MIRROR': 'Mirror',
    'CLEANSE': 'Cleanse',
    'IMPOSTER': 'Imposter',
    'RAINSTORM': 'Rainstorm',
    'SIGNAL_JAMMER': 'Signal Jammer',
    'LEECH': 'Leech',
    'DEFENSE_SCAN': 'X-Ray',
    'HITCHHIKE': 'Hitchhike',
    'QUICK_RINSE': 'Quick Rinse',
    'QUICKSAND': 'Quicksand',
    // §7 powerups5 store-only additions.
    'UPRISING': 'Uprising',
    'GHOST_PEPPER': 'Ghost Pepper',
    'COIN_FLIP': 'Coin Flip',
    'MYSTERY_POTION': 'Mystery Potion',
    'DECOY': 'Decoy',
    'POWER_OUTAGE': 'Power Outage',
    'UMBRELLA': 'Umbrella',
    'RALLY_FLAG': 'Rally Flag',
    'DRILL_SERGEANT': 'Drill Sergeant',
    'PIGGY_BANK': 'Piggy Bank',
    'BOUNTY': 'Bounty',
  };

  /// Labels that are NOT user-renderable powerup types but which former call
  /// sites still name: a retired powerup kept so old feed entries keep their
  /// highlight, and the daily-reward coin tile. Kept out of [bundledTypes].
  static const _extraDisplayNames = {
    'BANANA_PEEL': 'Banana Peel',
    'COINS': 'Coins',
  };

  static const _bundledDescriptions = {
    'LEG_CRAMP': "Freeze a rival's steps for 2 hours",
    'RED_CARD': "Remove 5% of the leader's steps",
    'SHORTCUT': 'Steal 1,000 steps from a rival',
    'COMPRESSION_SOCKS': 'Shield against the next attack',
    'PROTEIN_SHAKE': '+1,500 bonus steps instantly',
    'RUNNERS_HIGH': '2x steps for 3 hours',
    'SECOND_WIND': 'Bonus steps based on how far behind you are',
    'STEALTH_MODE':
        'Hide your name, steps, and track position while Stealth is active',
    'WRONG_TURN': "Reverse a rival's steps for 1 hour",
    'FANNY_PACK': 'Unlock an extra powerup slot',
    'TRAIL_MIX': '+100 steps per unique powerup type used',
    'DETOUR_SIGN': 'Hide the entire leaderboard from a rival for 3 hours',
    'LUCKY_HORSESHOE': 'Guarantee a better next mystery box',
    'CAMPFIRE_REST': 'Freeze for 30 min, then multiply steps for up to 90 min',
    'TRAIL_MAGNET': 'Pull your next mystery box 1,000 steps closer',
    'POCKET_WATCH': 'Extend all active timed buffs',
    'TRAIL_MINE': 'Drop a hidden trap at your current step position',
    'PINECONE_TOSS': 'Hit the runner directly ahead or behind you',
    'SNEAKY_SWAP': 'Steal a random powerup from a rival',
    'MIRROR': 'Reflect the next attack back at the attacker',
    'CLEANSE': 'Remove all debuffs an opponent placed on you',
    'IMPOSTER':
        "Swap leaderboard positions with a rival for 1 hour (cosmetic). Mirrors can't reflect it; Compression Socks block it",
    'RAINSTORM':
        "Everyone else's steps count for half for 1 hour. Mirrors can't reflect it; Compression Socks keep a racer dry",
    'SIGNAL_JAMMER':
        "Jam a rival's signal — they can't use any powerups for 1 hour. Mirrors can't reflect it; Compression Socks block it",
    // DURATION-NEUTRAL by contract (§7.5.1). A new binary can talk to an OLD
    // backend (30 min) or the new one (60 min for `powerups3`), so naming
    // either number here makes the fallback lie in one of those pairings. The
    // authoritative 60-minute wording arrives from the copy catalog.
    'LEECH':
        "Every 2 steps you take steals 1 step from a chosen rival and adds it to your score. Compression Socks block it; Mirrors can't reflect it",
    'DEFENSE_SCAN':
        "Instantly reveal every opponent's active defenses (shields and mirrors)",
    // Also duration-neutral: the window is a backend-tuned value.
    'HITCHHIKE':
        "Copy a rival's effective steps into your score while Hitchhike is active — boosts and reversals carry over",
    'QUICK_RINSE':
        'Cut the remaining time on every opponent effect currently on you in half',
    'QUICKSAND':
        "Freeze up to three rivals' steps for 2 hours. Compression Socks resolve separately for each target",
    // §7 powerups5 store-only additions.
    'UPRISING':
        'Rally the underdogs: everyone in the bottom half, you included, gets 2x steps for 2 hours',
    'GHOST_PEPPER':
        'Blaze with 3x steps for 30 min, then burn out — frozen for the next 30 min',
    'COIN_FLIP':
        'Flip a coin: heads doubles your steps for an hour, tails cuts them in half',
    'MYSTERY_POTION':
        'Drink up for a random effect — a boost, an attack on a rival, or a nasty surprise',
    'DECOY':
        'Set a decoy that redirects the next single-target attack aimed at you to another racer',
    'POWER_OUTAGE':
        "Cut the power on every rival — no one else can use powerups for 30 minutes. Compression Socks keep a racer online",
    'UMBRELLA':
        'Stay dry for 12 hours — immune to Rainstorm and Power Outage',
    'RALLY_FLAG':
        'Raise the flag: 1.25x steps for your whole team for 1 hour',
    'DRILL_SERGEANT':
        'Dare a rival to hit a step goal within 2 hours — if they fall short they lose steps',
    'PIGGY_BANK':
        'Bank your steps for 24 hours and cash them out as coins',
    'BOUNTY':
        'Place a bounty on a rival ahead of you — out-place them by race end to collect the payout',
  };

  // Short-form copy for the active-effects rail, where the countdown badge on
  // the right already conveys remaining duration. Only the types that had one
  // before this migration — a missing entry omits the subtitle line.
  static const _bundledShortDescriptions = {
    'LEG_CRAMP': 'Steps frozen',
    'COMPRESSION_SOCKS': 'Shielded from next attack',
    'RUNNERS_HIGH': '2x steps',
    'STEALTH_MODE': 'Progress hidden',
    'WRONG_TURN': 'Steps reversed',
    'FANNY_PACK': 'Extra powerup slot',
    'DETOUR_SIGN': 'Leaderboard hidden',
    'LUCKY_HORSESHOE': 'Next box boosted',
    'CAMPFIRE_REST': 'Frozen, then boosted',
    'POCKET_WATCH': 'Buffs extended',
    'TRAIL_MINE': 'Mine planted',
    'MIRROR': 'Reflects next attack',
    'RAINSTORM': 'Steps halved by rain',
    'SIGNAL_JAMMER': 'Powerups jammed',
    'LEECH': 'Steps being stolen',
    'HITCHHIKE': 'Steps being copied',
    'QUICKSAND': 'Steps frozen',
    // §7 powerups5 store-only additions.
    'UPRISING': 'Underdog rally: 2x steps',
    'GHOST_PEPPER': 'Blazing, then frozen',
    'COIN_FLIP': 'Coin flip in play',
    'DECOY': 'Decoy set',
    'POWER_OUTAGE': 'Powerups jammed',
    'UMBRELLA': 'Shielded from storms',
    'RALLY_FLAG': 'Team rally: 1.25x steps',
    'DRILL_SERGEANT': 'On the clock',
    'PIGGY_BANK': 'Banking steps for coins',
    'BOUNTY': 'Bounty placed',
  };

  static const _bundledUpgradeTierLabels = {
    'PROTEIN_SHAKE': [
      '+1,500 steps',
      '+2,250 steps',
      '+3,000 steps',
      '+4,500 steps',
    ],
    'SHORTCUT': [
      'Steal up to 1,000 steps',
      'Steal up to 1,500 steps',
      'Steal up to 2,000 steps',
      'Steal up to 3,000 steps',
    ],
    'DETOUR_SIGN': [
      'Hide leaderboard 3h',
      'Hide leaderboard 4h',
      'Hide leaderboard 5h',
      'Hide leaderboard 7h',
    ],
    'TRAIL_MIX': [
      '+100 steps per unique type',
      '+150 steps per unique type',
      '+200 steps per unique type',
      '+300 steps per unique type',
    ],
    'RUNNERS_HIGH': ['2x for 3h', '2x for 4h', '2x for 5h', '2x for 7h'],
    'LEG_CRAMP': ['Freeze 2h', 'Freeze 3h', 'Freeze 4h', 'Freeze 6h'],
    'STEALTH_MODE': ['Hide 4h', 'Hide 5h', 'Hide 6.5h', 'Hide 8h'],
    'WRONG_TURN': ['Reverse 1h', 'Reverse 1.5h', 'Reverse 2h', 'Reverse 3h'],
    'COMPRESSION_SOCKS': [
      'Shield 24h',
      'Shield 30h',
      'Shield 36h',
      'Shield 48h',
    ],
    'LUCKY_HORSESHOE': [
      'Next box uncommon+',
      'Better rare odds',
      'Strong rare odds',
      'Next box rare',
    ],
    'CAMPFIRE_REST': ['2.25x boost', '2.5x boost', '2.75x boost', '3x boost'],
    'TRAIL_MAGNET': [
      'Box 1,000 steps closer',
      'Box 1,500 steps closer',
      'Box 2,000 steps closer',
      'Box 3,000 steps closer',
    ],
    'POCKET_WATCH': ['Extend 1h', 'Extend 1.5h', 'Extend 2h', 'Extend 3h'],
    'TRAIL_MINE': ['3% penalty', '5% penalty', '8% penalty', '12% penalty'],
    'PINECONE_TOSS': [
      '-750 steps',
      '-1,000 steps',
      '-1,500 steps',
      '-2,250 steps',
    ],
  };
}
