import 'dart:async';

import 'package:flutter/material.dart';

import '../styles.dart';

/// The single active referral-contest promotion on Home.
///
/// Its solid, quiet game-piece treatment is intentional: the configured copy
/// is the headline, while prize and time are supporting facts.
class HomeGiveawayBanner extends StatelessWidget {
  const HomeGiveawayBanner({
    super.key,
    required this.message,
    required this.coinPrize,
    required this.endsAt,
    required this.onTap,
  });

  final String message;
  final int coinPrize;
  final DateTime endsAt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final remaining = endsAt.difference(DateTime.now());
    if (remaining <= Duration.zero) return const SizedBox.shrink();
    final colors = AppColors.of(context);
    final countdown = _remainingLabel(remaining);
    final formattedPrize = _commas(coinPrize);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: _ContestAttention(
        child: Semantics(
          button: true,
          excludeSemantics: true,
          onTap: onTap,
          label:
              '$message. $formattedPrize Bara coins. Contest ends in $countdown. View contest.',
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: const Key('home-giveaway-banner-tap'),
              borderRadius: BorderRadius.circular(10),
              onTap: onTap,
              excludeFromSemantics: true,
              child: Container(
                key: const Key('home-giveaway-banner'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: colors.parchmentLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: colors.woodDark.withValues(alpha: 0.28),
                    width: 1,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: colors.roofMid,
                        shape: BoxShape.circle,
                        border: Border.all(color: colors.woodDark, width: 1.5),
                      ),
                      child: Icon(
                        Icons.emoji_events_rounded,
                        color: colors.textLight,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: PixelText.title(
                              size: 15,
                              color: colors.textDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'WIN $formattedPrize COINS · ENDS IN $countdown',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PixelText.body(
                              size: 12.5,
                              color: colors.textMid,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: colors.woodDark,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'VIEW',
                            style: PixelText.title(
                              size: 11,
                              color: colors.textLight,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _remainingLabel(Duration remaining) {
    final seconds = remaining.inSeconds.clamp(0, 999999999);
    final days = seconds ~/ Duration.secondsPerDay;
    final hours = (seconds % Duration.secondsPerDay) ~/ Duration.secondsPerHour;
    final minutes =
        (seconds % Duration.secondsPerHour) ~/ Duration.secondsPerMinute;
    if (days > 0) return '${days}D ${hours.toString().padLeft(2, '0')}H';
    if (hours > 0) return '${hours}H ${minutes.toString().padLeft(2, '0')}M';
    return '${minutes.clamp(1, 59)}M';
  }

  static String _commas(int value) => value.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
}

/// One short seesaw beat followed by a long rest. The motion exists only to
/// re-surface a time-limited opportunity in the Home hierarchy, and stops
/// while the app is backgrounded or the user requests reduced motion.
class _ContestAttention extends StatefulWidget {
  const _ContestAttention({required this.child});

  final Widget child;

  @override
  State<_ContestAttention> createState() => _ContestAttentionState();
}

class _ContestAttentionState extends State<_ContestAttention>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 840),
  );
  Timer? _restTimer;
  late bool _foregrounded;

  @override
  void initState() {
    super.initState();
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _foregrounded =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    _controller.addStatusListener(_handleAnimationStatus);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() => _foregrounded = state == AppLifecycleState.resumed);
    _syncMotion();
  }

  void _syncMotion() {
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced || !_foregrounded) {
      _restTimer?.cancel();
      _restTimer = null;
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating && _restTimer == null) {
      _startBeat();
    }
  }

  void _startBeat() {
    _restTimer?.cancel();
    _restTimer = null;
    _controller.forward(from: 0);
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    if (!_foregrounded || MediaQuery.disableAnimationsOf(context)) return;
    _restTimer?.cancel();
    _restTimer = Timer(const Duration(milliseconds: 6160), () {
      if (!mounted || !_foregrounded) return;
      if (MediaQuery.disableAnimationsOf(context)) return;
      _startBeat();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _restTimer?.cancel();
    _controller.removeStatusListener(_handleAnimationStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        // The controller covers only the 840ms motion beat. A cancellable
        // timer owns the 6.16-second rest, so Home does no per-frame work while
        // the card is visually still.
        final t = _controller.value;
        final angle = switch (t) {
          < .17 => _segment(t, 0, .17, 0, -.012),
          < .38 => _segment(t, .17, .38, -.012, .012),
          < .59 => _segment(t, .38, .59, .012, -.007),
          < .80 => _segment(t, .59, .80, -.007, .005),
          _ => _segment(t, .80, 1, .005, 0),
        };
        return Transform.rotate(
          key: const Key('home-giveaway-banner-motion'),
          angle: angle,
          child: child,
        );
      },
    );
  }

  static double _segment(
    double value,
    double start,
    double end,
    double from,
    double to,
  ) {
    final progress = (value - start) / (end - start);
    return from + ((to - from) * progress);
  }
}
