import 'dart:math';

import 'package:flutter/material.dart';

class SpinningFace extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final double perspective;
  final bool mirrorBackface;

  const SpinningFace({
    super.key,
    required this.child,
    this.duration = const Duration(seconds: 2),
    this.perspective = 0.001,
    this.mirrorBackface = true,
  });

  @override
  State<SpinningFace> createState() => _SpinningFaceState();
}

class _SpinningFaceState extends State<SpinningFace>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: widget.duration, vsync: this)
      ..repeat();
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
      builder: (context, _) {
        final angle = _controller.value * 2 * pi;
        final isFrontFacing = cos(angle) >= 0;

        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, widget.perspective)
            ..rotateY(angle),
          child: isFrontFacing
              ? widget.child
              : widget.mirrorBackface
              ? Transform.flip(flipX: true, child: widget.child)
              : widget.child,
        );
      },
    );
  }
}
