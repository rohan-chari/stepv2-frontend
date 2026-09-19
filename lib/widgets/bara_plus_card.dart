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
      'renderMetadata': <String, dynamic>{'renderLayer': 'behind'},
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

        return Semantics(
          button: true,
          label: 'Bara Gold membership. Ad-free. Exclusive perks.',
          child: Material(
            color: colors.parchment,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: colors.medalGold.withValues(alpha: 0.85),
                width: 1.5,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const Key('bara-plus-card'),
              borderRadius: BorderRadius.circular(18),
              onTap: onTap,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final sceneWidth = tall
                      ? constraints.maxWidth * 0.38
                      : constraints.maxWidth * 0.42;
                  final cardHeight = tall ? 238.0 : 205.0;
                  final contentRightPadding = sceneWidth + 8;

                  return SizedBox(
                    height: cardHeight,
                    child: Stack(
                      children: [
                        Positioned(
                          top: 0,
                          right: 0,
                          bottom: 0,
                          width: sceneWidth,
                          child: ClipRRect(
                            borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(17),
                              bottomRight: Radius.circular(17),
                            ),
                            child: HomeHeroScene(
                              groundHeight: tall ? 47 : 43,
                              groundScrollSpeed: 22,
                              excludeBackgroundSemantics: true,
                              child: Stack(
                                children: [
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom:
                                        (tall ? 47 : 43) -
                                        4 -
                                        (tall ? 104 : 96) * .22,
                                    child: Center(
                                      child: KeyedSubtree(
                                        key: const Key(
                                          'bara-gold-cape-avatar',
                                        ),
                                        child:
                                            AnimatedCapybaraWithAccessories(
                                              accessories: _capeAccessory,
                                              size: tall ? 104 : 96,
                                              stepDuration: const Duration(
                                                milliseconds: 720,
                                              ),
                                              animate:
                                                  !MediaQuery.disableAnimationsOf(
                                                    context,
                                                  ),
                                            ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          right: contentRightPadding,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              tall ? 14 : 16,
                              tall ? 15 : 17,
                              8,
                              tall ? 14 : 15,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Bara Gold',
                                    style: PixelText.title(
                                      size: tall ? 24 : 27,
                                      color: colors.textDark,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  'Ad-free. Exclusive perks.',
                                  maxLines: tall ? 2 : 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: PixelText.body(
                                    size: tall ? 12.5 : 13,
                                    color: colors.textMid,
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  key: const Key('bara-gold-upgrade-cta'),
                                  width: double.infinity,
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: tall ? 11 : 10,
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
                                          alpha: 0.55,
                                        ),
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            'Upgrade to Bara Gold',
                                            style: PixelText.title(
                                              size: tall ? 13 : 14,
                                              color: colors.textDark,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 19,
                                        color: colors.textDark,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
