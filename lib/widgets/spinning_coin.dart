import 'dart:math';

import 'package:flutter/material.dart';

import '../styles.dart';

class SpinningCoin extends StatefulWidget {
  final double size;

  const SpinningCoin({super.key, this.size = 20});

  @override
  State<SpinningCoin> createState() => _SpinningCoinState();
}

class _SpinningCoinState extends State<SpinningCoin>
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final angle = _controller.value * 2 * pi;
        final scaleX = cos(angle);

        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(angle),
          child: scaleX >= 0
              ? _CoinFace(size: widget.size)
              : Transform.flip(
                  flipX: true,
                  child: _CoinFace(size: widget.size),
                ),
        );
      },
    );
  }
}

class _CoinFace extends StatelessWidget {
  final double size;

  const _CoinFace({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.coinLight,
            AppColors.coinMid,
            AppColors.coinDark,
          ],
        ),
        border: Border.all(color: AppColors.coinEdge, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.coinMid.withValues(alpha: 0.4),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Text(
          '\$',
          style: TextStyle(
            fontSize: size * 0.5,
            fontWeight: FontWeight.w900,
            color: AppColors.coinEdge,
            height: 1,
          ),
        ),
      ),
    );
  }
}
