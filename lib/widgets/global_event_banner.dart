import 'dart:async';

import 'package:flutter/material.dart';

import '../styles.dart';

/// On-brand "2x RACE STEPS — ends in mm:ss" banner for an active global
/// step-multiplier event (BeReal-style window; the boost applies to steps
/// counted toward races). Shared between the race detail page and the home
/// screen so both render the SAME look.
///
/// Self-ticking: owns a 1-second [Timer.periodic] to update the countdown and
/// collapses to [SizedBox.shrink] once [endsAt] passes. Callers just supply the
/// [multiplier] and [endsAt] (read defensively — an older backend simply omits
/// the field, in which case the caller renders nothing).
class GlobalEventBanner extends StatefulWidget {
  const GlobalEventBanner({
    super.key,
    required this.multiplier,
    required this.endsAt,
  });

  /// Step multiplier for the active window (e.g. 2 for "2x STEPS").
  final int multiplier;

  /// When the event window ends. Once this passes, the banner collapses.
  final DateTime endsAt;

  @override
  State<GlobalEventBanner> createState() => _GlobalEventBannerState();
}

class _GlobalEventBannerState extends State<GlobalEventBanner> {
  Timer? _countdownTimer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _startCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.endsAt.difference(_now);
    if (remaining.isNegative || remaining == Duration.zero) {
      return const SizedBox.shrink();
    }

    final multiplier = widget.multiplier;
    final totalSeconds = remaining.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final countdown =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    // Flat panel matching the home cards (parchment surface, 2px ink border,
    // hard offset shadow) — no gold bevel / gradients.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.parchmentLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.woodDark, width: 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.woodShadow.withValues(alpha: 0.22),
            offset: const Offset(4, 4),
            blurRadius: 0,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.roofMid,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.woodDark, width: 1.5),
            ),
            child: const Icon(
              Icons.bolt_rounded,
              size: 20,
              color: AppColors.parchment,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${multiplier}x RACE STEPS',
                  style: PixelText.title(size: 14, color: AppColors.woodDark),
                ),
                const SizedBox(height: 2),
                Text(
                  'STEPS COUNT ${multiplier}x IN ALL RACES — GO!',
                  style: PixelText.body(size: 12.5, color: AppColors.roofDark),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.woodDark,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'ends in $countdown',
              style: PixelText.title(size: 11, color: AppColors.parchment),
            ),
          ),
        ],
      ),
    );
  }
}
