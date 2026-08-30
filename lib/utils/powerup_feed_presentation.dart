import '../constants/powerup_copy.dart';

/// Semantic meaning of a named powerup in a race feed sentence.
///
/// This is deliberately independent of the event outcome: a harmful powerup
/// remains harmful when reflected or blocked, while the defense that stopped
/// it remains beneficial.
enum PowerupFeedValence { harmful, beneficial, neutral }

class PowerupFeedMention {
  const PowerupFeedMention({
    required this.start,
    required this.end,
    required this.text,
    required this.type,
    required this.valence,
  });

  final int start;
  final int end;
  final String text;
  final String type;
  final PowerupFeedValence valence;
}

abstract final class PowerupFeedPresentation {
  static const harmfulTypes = <String>{
    'WRONG_TURN',
    'LEG_CRAMP',
    'RED_CARD',
    'BANANA_PEEL',
    'DETOUR_SIGN',
    'TRAIL_MINE',
    'PINECONE_TOSS',
    'SNEAKY_SWAP',
    'IMPOSTER',
    'RAINSTORM',
    'SIGNAL_JAMMER',
    'LEECH',
    'QUICKSAND',
    'POWER_OUTAGE',
    'DRILL_SERGEANT',
    'BOUNTY',
    'SHORTCUT',
  };

  static const beneficialTypes = <String>{
    'PROTEIN_SHAKE',
    'RUNNERS_HIGH',
    'SECOND_WIND',
    'TRAIL_MIX',
    'FANNY_PACK',
    'LUCKY_HORSESHOE',
    'CAMPFIRE_REST',
    'TRAIL_MAGNET',
    'POCKET_WATCH',
    'STEALTH_MODE',
    'MIRROR',
    'COMPRESSION_SOCKS',
    'CLEANSE',
    'DEFENSE_SCAN',
    'HITCHHIKE',
    'QUICK_RINSE',
    'UPRISING',
    'GHOST_PEPPER',
    'COIN_FLIP',
    'DECOY',
    'UMBRELLA',
    'RALLY_FLAG',
    'PIGGY_BANK',
    'SHELL',
  };

  static const _neutralTypes = <String>{'MYSTERY_POTION'};

  // Old server-authored rows stay highlightable after catalog-name updates.
  static const _shippedNames = <String, List<String>>{
    'WRONG_TURN': ['Wrong Turn'],
    'LEG_CRAMP': ['Leg Cramp'],
    'RED_CARD': ['Red Card'],
    'BANANA_PEEL': ['Banana Peel'],
    'DETOUR_SIGN': ['Detour Sign'],
    'TRAIL_MINE': ['Trail Mine'],
    'PINECONE_TOSS': ['Pinecone Toss'],
    'SNEAKY_SWAP': ['Pickpocket', 'Sneaky Swap'],
    'IMPOSTER': ['Imposter'],
    'RAINSTORM': ['Rainstorm'],
    'SIGNAL_JAMMER': ['Signal Jammer'],
    'LEECH': ['Leech'],
    'QUICKSAND': ['Quicksand'],
    'POWER_OUTAGE': ['Power Outage'],
    'DRILL_SERGEANT': ['Drill Sergeant'],
    'BOUNTY': ['Bounty'],
    'SHORTCUT': ['Shortcut'],
    'PROTEIN_SHAKE': ['Protein Shake'],
    'RUNNERS_HIGH': ["Runner's High", 'Runner’s High'],
    'SECOND_WIND': ['Second Wind'],
    'TRAIL_MIX': ['Trail Mix'],
    'FANNY_PACK': ['Fanny Pack'],
    'LUCKY_HORSESHOE': ['Lucky Horseshoe'],
    'CAMPFIRE_REST': ['Campfire Rest'],
    'TRAIL_MAGNET': ['Trail Magnet'],
    'POCKET_WATCH': ['Pocket Watch'],
    'STEALTH_MODE': ['Stealth Mode'],
    'MIRROR': ['Mirror'],
    'COMPRESSION_SOCKS': ['Compression Socks'],
    'CLEANSE': ['Cleanse'],
    'DEFENSE_SCAN': ['X-Ray', 'Defense Scan'],
    'HITCHHIKE': ['Hitchhike'],
    'QUICK_RINSE': ['Quick Rinse'],
    'UPRISING': ['Uprising'],
    'GHOST_PEPPER': ['Ghost Pepper'],
    'COIN_FLIP': ['Coin Flip'],
    'DECOY': ['Decoy'],
    'UMBRELLA': ['Umbrella'],
    'RALLY_FLAG': ['Rally Flag'],
    'PIGGY_BANK': ['Piggy Bank'],
    'SHELL': ['Shell'],
    'MYSTERY_POTION': ['Mystery Potion'],
  };

  static PowerupFeedValence valenceForType(String? rawType) {
    final type = rawType?.trim().toUpperCase();
    if (type == null || type.isEmpty) return PowerupFeedValence.neutral;
    if (harmfulTypes.contains(type)) return PowerupFeedValence.harmful;
    if (beneficialTypes.contains(type)) return PowerupFeedValence.beneficial;
    return PowerupFeedValence.neutral;
  }

  /// Finds every known name, not just the one hinted by `powerupType`.
  /// Longer names win and returned spans never overlap.
  static List<PowerupFeedMention> mentionsIn(
    String description, {
    String? hintedType,
  }) {
    if (description.isEmpty) return const [];
    final types = <String>{
      ...harmfulTypes,
      ...beneficialTypes,
      ..._neutralTypes,
      if (hintedType != null && hintedType.trim().isNotEmpty)
        hintedType.trim().toUpperCase(),
    };
    final candidateByName = <String, String>{};
    for (final type in types) {
      final catalogName = PowerupCopy.nameFor(type).trim();
      if (catalogName.isNotEmpty && catalogName != type) {
        candidateByName.putIfAbsent(catalogName, () => type);
      }
      for (final name in _shippedNames[type] ?? const <String>[]) {
        candidateByName.putIfAbsent(name, () => type);
      }
    }

    final candidates = candidateByName.entries.toList()
      ..sort((a, b) {
        final length = b.key.length.compareTo(a.key.length);
        return length != 0 ? length : a.key.compareTo(b.key);
      });
    final occupied = List<bool>.filled(description.length, false);
    final matches = <PowerupFeedMention>[];
    for (final candidate in candidates) {
      var searchFrom = 0;
      while (searchFrom < description.length) {
        final start = description.indexOf(candidate.key, searchFrom);
        if (start < 0) break;
        final end = start + candidate.key.length;
        searchFrom = end;
        if (!_hasWordBoundaries(description, start, end)) continue;
        var overlaps = false;
        for (var index = start; index < end; index++) {
          if (occupied[index]) {
            overlaps = true;
            break;
          }
        }
        if (overlaps) continue;
        for (var index = start; index < end; index++) {
          occupied[index] = true;
        }
        matches.add(
          PowerupFeedMention(
            start: start,
            end: end,
            text: candidate.key,
            type: candidate.value,
            valence: valenceForType(candidate.value),
          ),
        );
      }
    }
    matches.sort((a, b) => a.start.compareTo(b.start));
    return matches;
  }

  static bool _hasWordBoundaries(String text, int start, int end) {
    final before = start == 0
        ? null
        : String.fromCharCode(text.substring(0, start).runes.last);
    final after = end == text.length
        ? null
        : String.fromCharCode(text.substring(end).runes.first);
    return (before == null || !_isUnicodeLetterOrNumber(before)) &&
        (after == null || !_isUnicodeLetterOrNumber(after));
  }

  static final RegExp _unicodeLetterOrNumber = RegExp(
    r'^[\p{L}\p{N}]$',
    unicode: true,
  );

  static bool _isUnicodeLetterOrNumber(String character) =>
      _unicodeLetterOrNumber.hasMatch(character);
}
