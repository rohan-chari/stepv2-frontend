import 'package:flutter/material.dart';

import '../styles.dart';
import 'spinning_coin.dart';

/// Flashy pill button that calls attention to itself when the user hasn't
/// claimed their daily reward yet. When [unclaimed] is false, it renders
/// muted and non-pulsing.
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
        final glowAlpha = widget.unclaimed ? (0.25 + 0.5 * t) : 0.0;
        final scale = widget.unclaimed ? (1.0 + 0.04 * t) : 1.0;
        return Transform.scale(
          scale: scale,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              boxShadow: glowAlpha > 0
                  ? [
                      BoxShadow(
                        color: AppColors.coinDark.withValues(alpha: glowAlpha),
                        blurRadius: 14,
                        spreadRadius: 1.5,
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
          borderRadius: BorderRadius.circular(999),
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: widget.unclaimed
                    ? const [AppColors.coinLight, AppColors.coinDark]
                    : const [
                        AppColors.parchmentDark,
                        AppColors.parchmentBorder,
                      ],
              ),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: widget.unclaimed
                    ? AppColors.coinDark
                    : AppColors.parchmentBorder,
                width: 2,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SpinningCoin(size: 20),
                const SizedBox(width: 8),
                Text(
                  widget.unclaimed ? 'DAILY!' : 'DAILY',
                  style: PixelText.title(
                    size: 13,
                    color: widget.unclaimed
                        ? AppColors.textDark
                        : AppColors.textMid,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
