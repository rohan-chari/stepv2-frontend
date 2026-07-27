import 'package:flutter/material.dart';

import '../styles.dart';

/// The degraded "steps not connected" strip (spec §5.2).
///
/// Reached three ways — the Android escape hatch, an inconclusive iOS probe,
/// and later revocation — and deliberately implemented once, because all three
/// leave the user in the same place: inside the app, fully navigable, scoring
/// zero.
///
/// Design notes. This is chrome that may sit on screen for hours, so it is the
/// one surface in the app that gets no ambient motion: a single entrance slide,
/// then it holds still. It reads as a warning rail bolted under the cabinet —
/// the terracotta pill palette, a hard-offset shadow with no blur to match the
/// game-piece cards, and a hazard-stripe cap on the leading edge so it is
/// legible as "something is wrong" before a word is read.
///
/// There is no dismiss affordance, on purpose. The user is scoring 0; hiding
/// that would be the bug, not the fix. It clears itself the moment steps
/// appear.
class StepsDisconnectedBanner extends StatefulWidget {
  const StepsDisconnectedBanner({super.key, required this.onFix});

  /// Re-runs the permission request, or deep-links to OS settings once that has
  /// already failed. The banner stays dumb about which.
  final VoidCallback onFix;

  @override
  State<StepsDisconnectedBanner> createState() =>
      _StepsDisconnectedBannerState();
}

class _StepsDisconnectedBannerState extends State<StepsDisconnectedBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
  )..forward();

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final slide = CurvedAnimation(
      parent: _entrance,
      curve: Curves.easeOutCubic,
    );

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.6),
        end: Offset.zero,
      ).animate(slide),
      child: FadeTransition(
        opacity: slide,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.pillTerra,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.pillTerraDark, width: 2),
              boxShadow: [
                BoxShadow(
                  color: colors.pillTerraShadow,
                  offset: const Offset(0, 4),
                  blurRadius: 0,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Row(
                children: [
                  // Hazard cap: reads as "attention" at a glance, and gives the
                  // icon a field of its own so the copy starts on a clean edge.
                  Container(
                    width: 40,
                    height: 52,
                    color: colors.pillTerraDark,
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.directions_walk_rounded,
                      size: 22,
                      color: colors.textLight,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Text(
                        'Steps aren’t connected — you’re scoring 0.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: PixelText.body(
                          size: 13,
                          color: colors.textLight,
                        ).copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: widget.onFix,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 14, 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Fix this',
                              style: PixelText.title(
                                size: 13,
                                color: colors.textLight,
                              ).copyWith(
                                decoration: TextDecoration.underline,
                                decorationColor: colors.textLight,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: colors.textLight,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
