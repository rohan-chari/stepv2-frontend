import 'package:flutter/material.dart';

import '../models/billing.dart';
import '../services/billing_controller.dart';
import '../styles.dart';
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
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final tall = textScale > 1.35;
        final cardHeight = tall ? 250.0 : 220.0;

        return Semantics(
          button: true,
          label: 'Bara Gold membership. Ad-free. Exclusive perks.',
          child: Material(
            color: Colors.transparent,
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
              child: SizedBox(
                height: cardHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // The accessory-editor world is the card, not a side panel.
                    HomeHeroScene(
                      key: const Key('bara-gold-hero-scene'),
                      groundHeight: tall ? 58 : 52,
                      groundScrollSpeed: 24,
                      excludeBackgroundSemantics: true,
                      child: const SizedBox.expand(),
                    ),

                    // Real in-game animated capybara + the existing cape asset,
                    // centered in the card like the accessory-editor preview.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom:
                          (tall ? 58 : 52) -
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

                    // Centered headline/copy over the live scene.
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

                    // Full-width CTA over the bottom of the scene.
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: tall ? 5 : 4,
                      child: Container(
                        key: const Key('bara-gold-upgrade-cta'),
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: tall ? 9 : 8,
                        ),
                        decoration: BoxDecoration(
                          color: colors.pillGold,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colors.pillGoldDark,
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: colors.pillGoldShadow.withValues(
                                alpha: 0.65,
                              ),
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'Upgrade to Bara Gold',
                                  textAlign: TextAlign.center,
                                  style: PixelText.title(
                                    size: tall ? 12.5 : 13.5,
                                    color: colors.textDark,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 19,
                              color: colors.textDark,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
