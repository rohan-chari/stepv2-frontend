import 'package:flutter/material.dart';

import '../styles.dart';

/// Ranked tiers, shared across the Ranked tab and any surface that shows a
/// user's tier (profile, races, leaderboard). Keep this the single source of
/// truth for tier colors/labels so they never drift between surfaces.
enum RankedTier { bronze, silver, gold, diamond, unranked }

RankedTier rankedTierFromKey(String? key) {
  switch (key) {
    case 'BRONZE':
      return RankedTier.bronze;
    case 'SILVER':
      return RankedTier.silver;
    case 'GOLD':
      return RankedTier.gold;
    case 'DIAMOND':
      return RankedTier.diamond;
    default:
      return RankedTier.unranked;
  }
}

extension RankedTierStyle on RankedTier {
  String get label => switch (this) {
        RankedTier.bronze => 'Bronze',
        RankedTier.silver => 'Silver',
        RankedTier.gold => 'Gold',
        RankedTier.diamond => 'Diamond',
        RankedTier.unranked => 'Unranked',
      };

  Color get color => switch (this) {
        RankedTier.bronze => AppColors.medalBronze,
        RankedTier.silver => AppColors.medalSilver,
        RankedTier.gold => AppColors.medalGold,
        RankedTier.diamond => const Color(0xFF49B6E0),
        RankedTier.unranked => AppColors.textMid,
      };
}

String romanDivision(int? division) => switch (division) {
      1 => 'I',
      2 => 'II',
      3 => 'III',
      _ => '',
    };

/// A tier chip: shield icon + "Gold II". [large] is for hero/header use;
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
          TierShield(tier: tier, size: large ? 22 : 14),
          SizedBox(width: large ? 8 : 4),
          Text(
            large ? text.toUpperCase() : text,
            style: PixelText.title(
              size: large ? 18 : 10,
              color: AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pixel-art shield asset for a tier (bronze/silver/gold/diamond). Returns null
/// for [RankedTier.unranked], which has no shield art.
String? tierShieldAsset(RankedTier tier) => switch (tier) {
      RankedTier.bronze => 'assets/images/shield_bronze.png',
      RankedTier.silver => 'assets/images/shield_silver.png',
      RankedTier.gold => 'assets/images/shield_gold.png',
      RankedTier.diamond => 'assets/images/shield_diamond.png',
      RankedTier.unranked => null,
    };

/// Renders the tier's pixel-art shield at [size]. Falls back to an outline
/// shield icon for Unranked (no art). Nearest-neighbour so the pixels stay crisp.
class TierShield extends StatelessWidget {
  const TierShield({super.key, required this.tier, this.size = 24});

  final RankedTier tier;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = tierShieldAsset(tier);
    if (asset == null) {
      return Icon(Icons.shield_outlined, size: size, color: tier.color);
    }
    // shields.png is smooth, high-detail art (not blocky pixel art), so it must
    // be downscaled with averaging, not nearest-neighbour. Decode it at the
    // physical display size for a crisp result and low memory.
    final cache = (size * MediaQuery.of(context).devicePixelRatio).round();
    return Image.asset(
      asset,
      width: size,
      height: size,
      cacheWidth: cache,
      cacheHeight: cache,
      filterQuality: FilterQuality.medium,
      fit: BoxFit.contain,
    );
  }
}
