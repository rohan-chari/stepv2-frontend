import 'package:flutter/material.dart';

import '../models/billing.dart';
import '../services/billing_controller.dart';
import '../styles.dart';
import 'bara_gold_benefits_carousel.dart';
import 'billing_scope.dart';
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
          label: 'Bara Gold membership.',
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
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [colors.dirtMid, colors.dirtDark],
                      ),
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final rowHeight = BaraGoldBenefitsCarousel.rowHeight(
                          context,
                          constraints.maxWidth,
                        );
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              height: rowHeight,
                              child: const BaraGoldBenefitsCarousel(),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(height: rowHeight, child: const _GoldUpgradeCta()),
                          ],
                        );
                      },
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
    final sceneHeight = tall ? 236.0 : 206.0;
    final groundHeight = tall ? 70.0 : 64.0;

    // Keep the compact scenery and real cape animation unchanged. Crop unused
    // soil rather than stretching the shared ground artwork.
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
                bottom: groundHeight - 4 - (tall ? 128 : 116) * .22 - (tall ? 3 : 2),
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
                child: Text(
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The existing card InkWell owns navigation; this never starts a purchase.
class _GoldUpgradeCta extends StatelessWidget {
  const _GoldUpgradeCta();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      key: const Key('bara-gold-upgrade-cta'),
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
          final showSparkles = constraints.maxWidth >= 280 &&
              MediaQuery.textScalerOf(context).scale(1) <= 1.35;
          final sparkle = ExcludeSemantics(
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 18,
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
                      child: Icon(Icons.arrow_forward_rounded, size: 22, color: colors.textDark),
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
