import 'package:flutter/material.dart';

import '../styles.dart';
import 'coin_glyph.dart';

/// Presentation copy only. Billing and benefit eligibility remain server-owned.
/// Both the shop teaser and membership details use this order and artwork.
enum BaraGoldBenefit {
  adFree('adfree', 'Ad-free experience', 'Play without interruptions.',
      'No banners or interruptions. Just Bara.'),
  exclusive('exclusive', 'Exclusive characters', 'Characters & shop power-ups.',
      'Unlock special characters, accessories and shop power-ups.'),
  coins('coins', 'Monthly coin bonus', 'Extra coins with your plan.',
      'Extra coins each month, based on your plan.'),
  rerolls('rerolls', 'Free rerolls', 'Daily Spins & boxes. No ads.',
      'Reroll Daily Spins and boxes without ads.');

  const BaraGoldBenefit(this.id, this.title, this.teaser, this.detail);

  final String id;
  final String title;
  final String teaser;
  final String detail;
}

TextStyle goldBenefitTitleStyle(BuildContext context) =>
    PixelText.title(size: 14, color: AppColors.of(context).textDark)
        .copyWith(height: 1.2);

TextStyle goldBenefitDetailStyle(BuildContext context) =>
    PixelText.body(size: 12, color: AppColors.of(context).textMid)
        .copyWith(height: 1.2);

class BaraGoldBenefitIcon extends StatelessWidget {
  const BaraGoldBenefitIcon({super.key, required this.benefit});

  final BaraGoldBenefit benefit;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final gold = colors.isDark ? colors.feedGold : colors.coinDark;
    final tint = switch (benefit) {
      BaraGoldBenefit.adFree => colors.error,
      BaraGoldBenefit.rerolls => colors.feedShield,
      _ => gold,
    };
    final icon = switch (benefit) {
      BaraGoldBenefit.adFree => Icons.block_rounded,
      BaraGoldBenefit.exclusive => Icons.workspace_premium_rounded,
      BaraGoldBenefit.rerolls => Icons.autorenew_rounded,
      BaraGoldBenefit.coins => null,
    };
    return ExcludeSemantics(
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: icon == null
            ? const CoinGlyph(size: 26)
            : Icon(icon, color: tint, size: 23),
      ),
    );
  }
}

class BaraGoldBenefitText extends StatelessWidget {
  const BaraGoldBenefitText({
    super.key,
    required this.benefit,
    this.short = false,
  });

  final BaraGoldBenefit benefit;
  final bool short;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(benefit.title, style: goldBenefitTitleStyle(context)),
      const SizedBox(height: 2),
      Text(
        short ? benefit.teaser : benefit.detail,
        style: goldBenefitDetailStyle(context),
      ),
    ],
  );
}
