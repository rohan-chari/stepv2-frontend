import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Arcade-style UI effects shared by the home screen (and any tab that wants
/// the same energy): a periodic shine sweep across a card, a pulsing glow for
/// primary CTAs, and a gentle badge wobble. All three freeze to a static
/// frame when `MediaQuery.disableAnimations` is set.

/// A diagonal highlight that periodically sweeps across [child], like light
/// catching a game card. The caller is responsible for clipping (wrap in a
/// ClipRRect matching the card's radius).
class ShineSweep extends StatefulWidget {
  const ShineSweep({
    super.key,
    required this.child,
    this.period = const Duration(milliseconds: 3400),
    this.delay = Duration.zero,
    this.width = 42,
    this.opacity = 0.30,
  });

  final Widget child;

  /// Full loop length (sweep + idle).
  final Duration period;

  /// Initial offset so a row of cards doesn't sweep in unison.
  final Duration delay;

  final double width;
  final double opacity;

  @override
  State<ShineSweep> createState() => _ShineSweepState();
}

class _ShineSweepState extends State<ShineSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _disabled = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.period);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _disabled = MediaQuery.of(context).disableAnimations;
    if (_disabled) {
      _controller.stop();
      _controller.value = 0.9; // idle phase — no visible bar
    } else if (!_controller.isAnimating) {
      _controller.value =
          (widget.delay.inMilliseconds % widget.period.inMilliseconds) /
          widget.period.inMilliseconds;
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                // Sweep occupies the first 30% of the loop, then rests.
                final sweepT = _controller.value / 0.3;
                if (sweepT >= 1) return const SizedBox.shrink();
                final x = -1.6 + 3.2 * Curves.easeInOut.transform(sweepT);
                return Align(
                  alignment: Alignment(x, 0),
                  child: Transform.rotate(
                    angle: 0.42,
                    child: Container(
                      width: widget.width,
                      height: 500,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.white.withValues(alpha: 0),
                            Colors.white.withValues(alpha: widget.opacity),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// A soft glow that breathes behind [child]. Put it around the one thing on a
/// card that should scream "tap me".
class PulseGlow extends StatefulWidget {
  const PulseGlow({
    super.key,
    required this.child,
    this.color = const Color(0xFFECC86A),
    this.borderRadius = 8,
    this.minAlpha = 0.25,
    this.maxAlpha = 0.60,
    this.period = const Duration(milliseconds: 1600),
  });

  final Widget child;
  final Color color;
  final double borderRadius;
  final double minAlpha;
  final double maxAlpha;
  final Duration period;

  @override
  State<PulseGlow> createState() => _PulseGlowState();
}

class _PulseGlowState extends State<PulseGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.period);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _controller.stop();
      _controller.value = 0.25;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final wave = 0.5 + 0.5 * math.sin(_controller.value * 2 * math.pi);
        final alpha =
            widget.minAlpha + (widget.maxAlpha - widget.minAlpha) * wave;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: alpha),
                blurRadius: 10 + 6 * wave,
                spreadRadius: 1 + wave,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Gentle periodic rock for badges/pills — a couple of quick wiggles, then a
/// pause, like a Clash chest asking to be opened.
class WobbleBadge extends StatefulWidget {
  const WobbleBadge({
    super.key,
    required this.child,
    this.period = const Duration(milliseconds: 2600),
    this.maxAngle = 0.09,
  });

  final Widget child;
  final Duration period;
  final double maxAngle;

  @override
  State<WobbleBadge> createState() => _WobbleBadgeState();
}

class _WobbleBadgeState extends State<WobbleBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.period);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _controller.stop();
      _controller.value = 0.9;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Wiggle during the first 35% of the loop, rest after.
        final t = _controller.value / 0.35;
        final angle = t >= 1
            ? 0.0
            : math.sin(t * math.pi * 4) * widget.maxAngle * (1 - t);
        return Transform.rotate(angle: angle, child: child);
      },
      child: widget.child,
    );
  }
}

/// Slide-up + fade entrance with a slight overshoot, staggered by [index].
/// Plays once on first mount; renders instantly when animations are disabled.
class StaggerIn extends StatefulWidget {
  const StaggerIn({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<StaggerIn>
    with SingleTickerProviderStateMixin {
  // The per-index delay lives inside the controller as an Interval (rather
  // than a Future.delayed) so no real timer is ever pending — widget tests
  // fail on stray timers.
  static const _slideMs = 420;
  late final AnimationController _controller;
  late final Animation<double> _intro;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    final delayMs = 60 + widget.index * 70;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: delayMs + _slideMs),
    );
    _intro = CurvedAnimation(
      parent: _controller,
      curve: Interval(delayMs / (delayMs + _slideMs), 1),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1;
      return;
    }
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final bounce = Curves.easeOutBack.transform(_intro.value);
        final fade = Curves.easeOut.transform(_intro.value);
        return Opacity(
          opacity: fade.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - bounce) * 26),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
