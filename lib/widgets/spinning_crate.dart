import 'dart:math';
import 'package:flutter/material.dart';

class SpinningCrate extends StatefulWidget {
  final double size;

  const SpinningCrate({super.key, this.size = 80});

  @override
  State<SpinningCrate> createState() => _SpinningCrateState();
}

class _SpinningCrateState extends State<SpinningCrate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        // Gentle float up and down
        final floatY = sin(t * 2 * pi) * 6;
        // Subtle rock side to side
        final rock = sin(t * 2 * pi) * 0.05;

        return SizedBox(
          width: s * 1.5,
          height: s * 1.8,
          child: Center(
            child: Transform.translate(
              offset: Offset(0, floatY),
              child: Transform.rotate(
                angle: rock,
                child: _CrateFace(size: s),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CrateFace extends StatelessWidget {
  final double size;
  const _CrateFace({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFC48C3C),
        border: Border.all(color: const Color(0xFF6B4420), width: 2.5),
        borderRadius: BorderRadius.circular(size * 0.06),
      ),
      child: Stack(
        children: [
          // Horizontal plank lines
          for (final y in [0.3, 0.7])
            Positioned(
              top: size * y - 1,
              left: 0,
              right: 0,
              child: Container(
                height: 2,
                color: const Color(0xFF6B4420).withValues(alpha: 0.3),
              ),
            ),
          // Corner brackets
          ..._buildBrackets(size),
          // Yellow question mark
          Center(
            child: Text(
              '?',
              style: TextStyle(
                fontSize: size * 0.45,
                fontWeight: FontWeight.w900,
                color: const Color(0xFFFFD740),
                shadows: const [
                  Shadow(
                    color: Color(0xFF6B4420),
                    offset: Offset(1.5, 1.5),
                    blurRadius: 0,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildBrackets(double s) {
    const color = Color(0xFF8B6914);
    final bSize = s * 0.14;
    const bWidth = 2.5;
    final inset = s * 0.05;
    const solid = BorderSide(color: color, width: bWidth);
    const none = BorderSide.none;

    return [
      Positioned(top: inset, left: inset, child: Container(width: bSize, height: bSize,
        decoration: const BoxDecoration(border: Border(top: solid, left: solid, bottom: none, right: none)))),
      Positioned(top: inset, right: inset, child: Container(width: bSize, height: bSize,
        decoration: const BoxDecoration(border: Border(top: solid, right: solid, bottom: none, left: none)))),
      Positioned(bottom: inset, left: inset, child: Container(width: bSize, height: bSize,
        decoration: const BoxDecoration(border: Border(bottom: solid, left: solid, top: none, right: none)))),
      Positioned(bottom: inset, right: inset, child: Container(width: bSize, height: bSize,
        decoration: const BoxDecoration(border: Border(bottom: solid, right: solid, top: none, left: none)))),
    ];
  }
}