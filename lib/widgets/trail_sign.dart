import 'package:flutter/material.dart';

import '../styles.dart';
import 'content_board.dart';

/// Compact modal/sign surface that now matches the homepage arcade chrome.
class TrailSign extends StatelessWidget {
  const TrailSign({
    super.key,
    required this.child,
    this.width = 300,
  });

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: AppColors.parchment,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.textDark, width: 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.textDark.withValues(alpha: 0.20),
            offset: const Offset(4, 4),
            blurRadius: 0,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          children: [
            const Positioned.fill(
              child: CustomPaint(painter: PixelSurfacePainter()),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: SizedBox(width: double.infinity, child: child),
            ),
          ],
        ),
      ),
    );
  }
}
