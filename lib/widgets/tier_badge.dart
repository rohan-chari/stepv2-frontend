import 'package:flutter/material.dart';

import '../styles.dart';

/// Ranked tiers, shared across the Ranked tab and any surface that shows a
/// user's tier (profile, races, leaderboard). Keep this the single source of
/// truth for tier colors/labels so they never drift between surfaces.
enum RankedTier { bronze, silver, gold, platinum, diamond, legend, unranked }

RankedTier rankedTierFromKey(String? key) {
  switch (key) {
    case 'BRONZE':
      return RankedTier.bronze;
    case 'SILVER':
      return RankedTier.silver;
    case 'GOLD':
      return RankedTier.gold;
    case 'PLATINUM':
      return RankedTier.platinum;
    case 'DIAMOND':
      return RankedTier.diamond;
    case 'LEGEND':
      return RankedTier.legend;
    default:
      return RankedTier.unranked;
  }
}

extension RankedTierStyle on RankedTier {
  String get label => switch (this) {
    RankedTier.bronze => 'Bronze',
    RankedTier.silver => 'Silver',
    RankedTier.gold => 'Gold',
    RankedTier.platinum => 'Platinum',
    RankedTier.diamond => 'Diamond',
    RankedTier.legend => 'Legend',
    RankedTier.unranked => 'Unranked',
  };

  Color get color => switch (this) {
    RankedTier.bronze => AppColors.medalBronze,
    RankedTier.silver => AppColors.medalSilver,
    RankedTier.gold => AppColors.medalGold,
    RankedTier.platinum => const Color(0xFF8FD8CE),
    RankedTier.diamond => const Color(0xFF49B6E0),
    RankedTier.legend => const Color(0xFFB05CE6),
    RankedTier.unranked => AppColors.textMid,
  };
}

String romanDivision(int? division) => switch (division) {
  1 => 'I',
  2 => 'II',
  3 => 'III',
  _ => '',
};

/// A tier chip: medal icon + "Gold II". [large] is for hero/header use;
/// the compact form suits inline rows and badges.
class TierBadge extends StatelessWidget {
  const TierBadge({
    super.key,
    required this.tier,
    this.division,
    this.large = false,
  });

  final RankedTier tier;
  final int? division;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final roman = romanDivision(division);
    final text = roman.isEmpty ? tier.label : '${tier.label} $roman';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 14 : 8,
        vertical: large ? 8 : 4,
      ),
      decoration: BoxDecoration(
        color: tier.color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(large ? 10 : 7),
        border: Border.all(color: tier.color, width: large ? 2 : 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TierMedal(tier: tier, size: large ? 22 : 14),
          SizedBox(width: large ? 8 : 4),
          Text(
            large ? text.toUpperCase() : text,
            style: PixelText.title(
              size: large ? 18 : 10,
              color: AppColors.of(context).textDark,
            ),
          ),
        ],
      ),
    );
  }
}

/// Ranked medal asset for a tier. Returns null for [RankedTier.unranked],
/// which has no tier art. Platinum and Legend reuse existing medals with a
/// modulate tint (see [tierMedalTint]) until dedicated art lands.
String? tierMedalAsset(RankedTier tier) => switch (tier) {
  RankedTier.bronze => 'assets/images/ranked_medal_bronze.png',
  RankedTier.silver => 'assets/images/ranked_medal_silver.png',
  RankedTier.gold => 'assets/images/ranked_medal_gold.png',
  RankedTier.platinum => 'assets/images/ranked_medal_silver.png',
  RankedTier.diamond => 'assets/images/ranked_medal_diamond.png',
  RankedTier.legend => 'assets/images/ranked_medal_diamond.png',
  RankedTier.unranked => null,
};

/// Placeholder tint for tiers without dedicated medal art yet. Multiplied
/// over the base asset (BlendMode.modulate), so highlights stay bright.
Color? tierMedalTint(RankedTier tier) => switch (tier) {
  RankedTier.platinum => const Color(0xFFB8F5E9),
  RankedTier.legend => const Color(0xFFD9A1FF),
  _ => null,
};

/// Renders the tier's medal art at [size]. Falls back to an outline medal icon
/// for Unranked (no art).
class TierMedal extends StatelessWidget {
  const TierMedal({super.key, required this.tier, this.size = 24});

  final RankedTier tier;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = tierMedalAsset(tier);
    if (asset == null) {
      return Icon(Icons.military_tech_outlined, size: size, color: tier.color);
    }
    // The medal art is smooth, high-detail art (not blocky pixel art), so it must
    // be downscaled with averaging, not nearest-neighbour. Decode it at the
    // physical display size for a crisp result and low memory.
    final cache = (size * MediaQuery.of(context).devicePixelRatio).round();
    final tint = tierMedalTint(tier);
    return Image.asset(
      asset,
      width: size,
      height: size,
      cacheWidth: cache,
      cacheHeight: cache,
      filterQuality: FilterQuality.medium,
      fit: BoxFit.contain,
      color: tint,
      colorBlendMode: tint != null ? BlendMode.modulate : null,
    );
  }
}
