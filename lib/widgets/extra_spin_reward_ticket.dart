import 'dart:math' show pi, sin;

import 'package:flutter/material.dart';

import 'pill_button.dart';

/// The existing Home quick-action pill with a short attention beat every six
/// seconds. Its layout is deliberately the same [PillButton] footprint as
/// CLAIM/CLAIMED and SHOP beside it.
class ExtraSpinRewardTicket extends StatefulWidget {
  const ExtraSpinRewardTicket({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<ExtraSpinRewardTicket> createState() => _ExtraSpinRewardTicketState();
}

class _ExtraSpinRewardTicketState extends State<ExtraSpinRewardTicket>
    with SingleTickerProviderStateMixin {
  late final AnimationController _attention = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );
  bool _motionConfigured = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _attention.stop();
      _attention.value = 1;
      return;
    }
    if (!_motionConfigured) {
      _motionConfigured = true;
      _attention.repeat();
    }
  }

  @override
  void dispose() {
    _attention.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: 'Extra spin. Watch a short ad for one extra spin.',
      onTap: widget.onPressed,
      child: AnimatedBuilder(
        animation: _attention,
        builder: (context, child) {
          // The first 900ms of each six-second cycle is the attention beat;
          // the remaining 5.1 seconds are visually still.
          final beat = (_attention.value / 0.15).clamp(0.0, 1.0);
          final popProgress = Curves.easeOut.transform(
            const Interval(0, 0.62).transform(beat),
          );
          final pop = sin(popProgress * pi);
          final shimmer = Curves.easeInOut.transform(
            const Interval(0.14, 0.88).transform(beat),
          );
          return Transform.scale(
            // A brief 2.5% pop draws the eye but never changes row layout.
            scale: 1 + (0.025 * pop),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                child!,
                Positioned.fill(
                  child: IgnorePointer(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Align(
                        alignment: Alignment(-2.2 + (4.4 * shimmer), 0),
                        child: Transform.rotate(
                          angle: -0.24,
                          child: Container(
                            width: 22,
                            color: Colors.white.withValues(
                              alpha: 0.32 * (1 - (shimmer - 0.5).abs() * 2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        child: PillButton(
          label: 'EXTRA SPIN',
          icon: Icons.replay_rounded,
          variant: PillButtonVariant.secondary,
          fullWidth: true,
          onPressed: widget.onPressed,
        ),
      ),
    );
  }
}
