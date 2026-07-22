import 'dart:async';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../styles.dart';

/// A one-shot confetti burst overlaid on a celebratory moment (e.g. placing
/// top 3 in a race, or getting promoted in ranked). Drop it into a [Stack]
/// *behind* the modal card — it self-manages its [ConfettiController]s, firing
/// once on first build and never repeating.
///
/// Both emitters sit at screen centre and blast omnidirectionally
/// ([BlastDirectionality.explosive]), so the burst erupts from behind the card
/// and the particles you see spray out *around* its edges — framing the modal
/// rather than raining up from the screen bottom. A second emitter fires a beat
/// later for a fuller, more intense double-pop. Colours come from the app's
/// gold/sky/leaf palette so it matches the game chrome.
class CelebrationConfetti extends StatefulWidget {
  const CelebrationConfetti({super.key});

  @override
  State<CelebrationConfetti> createState() => _CelebrationConfettiState();
}

class _CelebrationConfettiState extends State<CelebrationConfetti> {
  late final ConfettiController _burst1;
  late final ConfettiController _burst2;
  Timer? _secondBurstTimer;
  Timer? _hapticTimer;

  // Roughly how long the confetti is airborne: the second burst starts ~220ms
  // in and runs for 900ms. The haptic rumble runs for this whole window.
  static const _animDuration = Duration(milliseconds: 1150);
  // Cadence of the sustained rumble. iOS has no true continuous haptic, so we
  // fire rapid light impacts to approximate one for the duration.
  static const _hapticTick = Duration(milliseconds: 65);

  static const _colors = <Color>[
    AppColors.medalGold,
    AppColors.sunYellow,
    AppColors.sunOrange,
    AppColors.coinLight,
    AppColors.coinMid,
    AppColors.skyBand3,
    AppColors.accentLight,
  ];

  @override
  void initState() {
    super.initState();
    _burst1 = ConfettiController(duration: const Duration(milliseconds: 900));
    _burst2 = ConfettiController(duration: const Duration(milliseconds: 900));
    // Fire as the modal's fade-in begins, then a second pop ~220ms later so the
    // celebration builds instead of going off all at once. A heavy thump kicks
    // it off and a sustained light-impact rumble runs for the whole animation
    // so it feels physical the entire time the confetti is in the air.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _burst1.play();
      _startHapticRumble();
      _secondBurstTimer = Timer(const Duration(milliseconds: 220), () {
        if (mounted) _burst2.play();
      });
    });
  }

  /// A heavy opening thump followed by rapid light impacts for [_animDuration],
  /// approximating a continuous rumble under the confetti.
  void _startHapticRumble() {
    HapticFeedback.heavyImpact();
    var elapsed = Duration.zero;
    _hapticTimer = Timer.periodic(_hapticTick, (timer) {
      elapsed += _hapticTick;
      if (!mounted || elapsed >= _animDuration) {
        timer.cancel();
        return;
      }
      HapticFeedback.lightImpact();
    });
  }

  @override
  void dispose() {
    _secondBurstTimer?.cancel();
    _hapticTimer?.cancel();
    _burst1.dispose();
    _burst2.dispose();
    super.dispose();
  }

  Widget _emitter(ConfettiController controller) {
    return ConfettiWidget(
      confettiController: controller,
      blastDirectionality: BlastDirectionality.explosive,
      emissionFrequency: 0.06,
      numberOfParticles: 28,
      maxBlastForce: 60,
      minBlastForce: 24,
      gravity: 0.32,
      particleDrag: 0.04,
      minimumSize: const Size(8, 8),
      maximumSize: const Size(15, 15),
      colors: _colors,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Non-interactive: the burst must never intercept taps on the card/buttons.
    // Both emitters at centre so the explosion radiates out around the modal.
    return IgnorePointer(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(alignment: Alignment.center, child: _emitter(_burst1)),
          Align(alignment: Alignment.center, child: _emitter(_burst2)),
        ],
      ),
    );
  }
}
