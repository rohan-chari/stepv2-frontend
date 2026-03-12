import 'dart:math';
import 'package:flutter/material.dart';
import '../styles.dart';

/// The shared sky + island ground background used across all screens.
class GameBackground extends StatelessWidget {
  final Widget child;

  const GameBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final groundHeight = screenHeight * 0.22;

    return Stack(
      children: [
        // Light blue sky
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: AppColors.skyGradient,
            ),
          ),
        ),

        // Island ground
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: groundHeight,
          child: RepaintBoundary(
            child: CustomPaint(
              size: Size(screenWidth, groundHeight),
              painter: _IslandPainter(),
            ),
          ),
        ),

        // Content on top
        Positioned.fill(child: child),
      ],
    );
  }
}

class _IslandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final earthPath = Path();
    earthPath.moveTo(0, size.height * 0.2);
    for (double x = 0; x <= size.width; x += 4) {
      final y = size.height * 0.2 + sin(x * 0.008) * 8 + cos(x * 0.015) * 5;
      earthPath.lineTo(x, y);
    }
    earthPath.lineTo(size.width, size.height);
    earthPath.lineTo(0, size.height);
    earthPath.close();

    canvas.drawPath(
      earthPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.earthLight, AppColors.earthMid, AppColors.earthDark],
        ).createShader(Offset.zero & size),
    );

    final grassPath = Path();
    grassPath.moveTo(0, size.height * 0.15);
    for (double x = 0; x <= size.width; x += 4) {
      final y = size.height * 0.15 + sin(x * 0.008) * 8 + cos(x * 0.015) * 5;
      grassPath.lineTo(x, y);
    }
    grassPath.lineTo(size.width, size.height * 0.25);
    for (double x = size.width; x >= 0; x -= 4) {
      final y = size.height * 0.25 + sin(x * 0.008) * 6 + cos(x * 0.015) * 4;
      grassPath.lineTo(x, y);
    }
    grassPath.close();

    canvas.drawPath(
      grassPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.grassLight, AppColors.grassMid, AppColors.grassDark],
        ).createShader(Offset.zero & size),
    );

    final highlightPath = Path();
    for (double x = 0; x <= size.width; x += 4) {
      final y = size.height * 0.15 + sin(x * 0.008) * 8 + cos(x * 0.015) * 5;
      if (x == 0) {
        highlightPath.moveTo(x, y);
      } else {
        highlightPath.lineTo(x, y);
      }
    }
    canvas.drawPath(
      highlightPath,
      Paint()
        ..color = AppColors.grassHighlight
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    final tuftPaint = Paint()
      ..color = AppColors.grassTuft
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final rng = Random(42);
    for (int i = 0; i < 20; i++) {
      final x = rng.nextDouble() * size.width;
      final baseY =
          size.height * 0.14 + sin(x * 0.008) * 8 + cos(x * 0.015) * 5;
      final h = 4.0 + rng.nextDouble() * 6;
      canvas.drawLine(
        Offset(x, baseY),
        Offset(x + rng.nextDouble() * 4 - 2, baseY - h),
        tuftPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
