import 'package:flutter/material.dart';

import '../models/billing.dart';
import '../services/billing_controller.dart';
import '../styles.dart';
import 'billing_scope.dart';
import 'coin_glyph.dart';
import 'home_course_track.dart';
import 'home_hero_scene.dart';

class BaraPlusCard extends StatelessWidget {
  final BillingController? controller;
  final VoidCallback? onTap;

  const BaraPlusCard({super.key, this.controller, this.onTap});

  static const _capeAccessory = <Map<String, dynamic>>[
    <String, dynamic>{
      'slot': 'BACK',
      'assetKey': 'cape',
      'renderMetadata': <String, dynamic>{
        'scale': 2.1499999999999995,
        'offsetX': -0.1,
        'offsetY': -0.00423728813559332,
        'rotation': 0.24915254237288265,
        'renderLayer': 'front',
        'animationFrames': 6,
      },
    },
  ];

  @override
  Widget build(BuildContext context) {
    final billing = controller ?? BillingScope.maybeOf(context);
    if (billing == null) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: billing,
      builder: (context, _) {
        if (!billing.canShowMembership &&
            billing.snapshot.status == BillingStatus.free) {
          return const SizedBox.shrink();
        }

        final colors = AppColors.of(context);
        final tall = MediaQuery.textScalerOf(context).scale(1) > 1.35;

        return Semantics(
          button: onTap != null,
          label: 'Bara Gold membership. Ad-free. Exclusive perks.',
          child: Material(
            color: colors.dirtMid,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: colors.medalGold.withValues(alpha: 0.92),
                width: 1.5,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const Key('bara-plus-card'),
              borderRadius: BorderRadius.circular(18),
              onTap: onTap,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _hero(context, tall: tall),
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [colors.dirtMid, colors.dirtDark],
                      ),
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _GoldBenefitsPanel(),
                        SizedBox(height: 12),
                        _GoldUpgradeCta(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _hero(BuildContext context, {required bool tall}) {
    final colors = AppColors.of(context);
    final sceneHeight = tall ? 266.0 : 236.0;
    final groundHeight = tall ? 70.0 : 64.0;

    // Preserve the original sky, terrain scale and avatar anchoring. Only
    // crop the soil where the old CTA sat; the new footer sizes to its text.
    // Increasing HomeHeroScene.groundHeight would stretch the pixel artwork.
    final visibleHeight = sceneHeight - groundHeight + 18;
    return ClipRect(
      key: const Key('bara-gold-hero-viewport'),
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: visibleHeight / sceneHeight,
        child: SizedBox(
          height: sceneHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              HomeHeroScene(
                key: const Key('bara-gold-hero-scene'),
                groundHeight: groundHeight,
                groundScrollSpeed: 24,
                excludeBackgroundSemantics: true,
                child: const SizedBox.expand(),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom:
                    groundHeight -
                    4 -
                    (tall ? 128 : 116) * .22 -
                    (tall ? 3 : 2),
                child: Center(
                  child: KeyedSubtree(
                    key: const Key('bara-gold-cape-avatar'),
                    child: AnimatedCapybaraWithAccessories(
                      accessories: _capeAccessory,
                      size: tall ? 128 : 116,
                      stepDuration: const Duration(milliseconds: 720),
                      animate: !MediaQuery.disableAnimationsOf(context),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                top: tall ? 13 : 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Bara Gold',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PixelText.title(
                        size: tall ? 24 : 27,
                        color: colors.textLight,
                      ).copyWith(
                        shadows: const [
                          Shadow(
                            color: Color(0x66000000),
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Ad-free. Exclusive perks.',
                      textAlign: TextAlign.center,
                      maxLines: tall ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: PixelText.body(
                        size: tall ? 12.5 : 13,
                        color: colors.textLight.withValues(alpha: 0.84),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoldBenefitsPanel extends StatelessWidget {
  const _GoldBenefitsPanel();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final gold = colors.isDark ? colors.feedGold : colors.coinDark;
    final divider = Divider(
      height: 1,
      thickness: 1,
      indent: 52,
      color: colors.parchmentBorder.withValues(alpha: 0.5),
    );

    return Container(
      key: const Key('bara-gold-benefits'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: colors.parchment,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colors.parchmentBorder.withValues(alpha: 0.65),
        ),
        boxShadow: [
          BoxShadow(
            color: colors.dirtDark.withValues(alpha: 0.28),
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _GoldBenefitRow(
            icon: Icon(Icons.block_rounded, color: colors.error, size: 26),
            tint: colors.error,
            title: 'Ad-free experience',
            detail: 'No banners or interruptions. Just Bara.',
          ),
          divider,
          _GoldBenefitRow(
            icon: Icon(Icons.workspace_premium_rounded, color: gold, size: 28),
            tint: gold,
            title: 'Exclusive characters',
            detail: 'Unlock special characters and shop power-ups.',
          ),
          divider,
          _GoldBenefitRow(
            icon: const CoinGlyph(size: 30),
            tint: gold,
            title: 'Monthly coin bonus',
            detail: 'Extra coins each month, based on your plan.',
          ),
          divider,
          _GoldBenefitRow(
            icon: Icon(
              Icons.autorenew_rounded,
              color: colors.feedShield,
              size: 28,
            ),
            tint: colors.feedShield,
            title: 'Free rerolls',
            detail: 'Reroll Daily Spins and boxes without ads.',
          ),
        ],
      ),
    );
  }
}

class _GoldBenefitRow extends StatelessWidget {
  const _GoldBenefitRow({
    required this.icon,
    required this.tint,
    required this.title,
    required this.detail,
  });

  final Widget icon;
  final Color tint;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: icon,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: PixelText.title(size: 14, color: colors.textDark),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: PixelText.body(size: 12, color: colors.textMid),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Visual CTA for the card's existing InkWell. Tapping anywhere still opens
/// membership details; this widget never invokes a billing operation itself.
class _GoldUpgradeCta extends StatelessWidget {
  const _GoldUpgradeCta();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      key: const Key('bara-gold-upgrade-cta'),
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colors.pillGold, colors.medalGold, colors.pillGoldDark],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.pillGoldDark, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: colors.pillGoldShadow.withValues(alpha: 0.8),
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Decorative elements yield space to the label on small screens
          // and at large text sizes. Text wraps instead of being scaled down.
          final showSparkles =
              constraints.maxWidth >= 280 &&
              MediaQuery.textScalerOf(context).scale(1) <= 1.35;
          final sparkle = ExcludeSemantics(
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 20,
              color: colors.textLight.withValues(alpha: 0.85),
            ),
          );
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (showSparkles) ...[sparkle, const SizedBox(width: 8)],
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        'Upgrade to Bara Gold',
                        textAlign: TextAlign.center,
                        style: PixelText.title(size: 15, color: colors.textDark),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ExcludeSemantics(
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 22,
                        color: colors.textDark,
                      ),
                    ),
                  ],
                ),
              ),
              if (showSparkles) ...[const SizedBox(width: 8), sparkle],
            ],
          );
        },
      ),
    );
  }
}
