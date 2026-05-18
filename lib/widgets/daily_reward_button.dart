import 'package:flutter/material.dart';

import 'home_chrome.dart';
import 'spinning_coin.dart';

/// Home-style entry point for the daily reward flow.
class DailyRewardButton extends StatefulWidget {
  const DailyRewardButton({
    super.key,
    required this.unclaimed,
    required this.onPressed,
  });

  final bool unclaimed;
  final VoidCallback onPressed;

  @override
  State<DailyRewardButton> createState() => _DailyRewardButtonState();
}

class _DailyRewardButtonState extends State<DailyRewardButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (widget.unclaimed) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant DailyRewardButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.unclaimed && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.unclaimed && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_pulse.value);
        final glowAlpha = widget.unclaimed ? (0.08 + 0.12 * t) : 0.0;
        return Transform.scale(
          scale: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: glowAlpha > 0
                  ? [
                      BoxShadow(
                        color: HomeColors.gold.withValues(alpha: glowAlpha),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : const [],
            ),
            child: child,
          ),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Ink(
            decoration: BoxDecoration(
              color: widget.unclaimed
                  ? HomeColors.cream
                  : HomeColors.surfaceMuted,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.unclaimed ? HomeColors.gold : HomeColors.lineSoft,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: (widget.unclaimed ? HomeColors.gold : HomeColors.line)
                      .withValues(alpha: widget.unclaimed ? 0.18 : 0.10),
                  offset: const Offset(0, 3),
                  blurRadius: 0,
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                const SpinningCoin(size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Daily reward',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: HomeText.body(
                          size: 14,
                          color: HomeColors.ink,
                          weight: FontWeight.w800,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.unclaimed
                            ? 'Ready to open'
                            : 'Today is already claimed',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: HomeText.body(
                          size: 12,
                          color: HomeColors.muted,
                          weight: FontWeight.w700,
                          height: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _RewardStatusBadge(unclaimed: widget.unclaimed),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RewardStatusBadge extends StatelessWidget {
  const _RewardStatusBadge({required this.unclaimed});

  final bool unclaimed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: unclaimed ? HomeColors.ink : HomeColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: unclaimed ? HomeColors.ink : HomeColors.lineSoft,
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Text(
          unclaimed ? 'CLAIM' : 'VIEW',
          maxLines: 1,
          style: HomeText.label(
            size: 10,
            color: unclaimed ? Colors.white : HomeColors.ink,
          ),
        ),
      ),
    );
  }
}
