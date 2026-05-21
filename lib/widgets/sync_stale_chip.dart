import 'package:flutter/material.dart';

import '../styles.dart';

class SyncStaleChip extends StatelessWidget {
  const SyncStaleChip({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Steps not synced',
      button: onTap != null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.parchmentLight,
              border: Border.all(color: AppColors.error, width: 1.5),
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33213128),
                  offset: Offset(0, 1),
                  blurRadius: 0,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _PixelWarningIcon(size: 14),
                const SizedBox(width: 6),
                Text(
                  'Not synced',
                  style: TextStyle(
                    color: AppColors.error,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PixelWarningIcon extends StatelessWidget {
  const _PixelWarningIcon({this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _PixelWarningPainter()),
    );
  }
}

class _PixelWarningPainter extends CustomPainter {
  static const _grid = 9;
  // 9x9 pixel warning triangle. 0=empty, 1=fill, 2=border, 3=highlight, 4=dot.
  static const List<List<int>> _pixels = [
    [0, 0, 0, 0, 2, 0, 0, 0, 0],
    [0, 0, 0, 2, 3, 2, 0, 0, 0],
    [0, 0, 2, 1, 1, 1, 2, 0, 0],
    [0, 0, 2, 1, 4, 1, 2, 0, 0],
    [0, 2, 1, 1, 4, 1, 1, 2, 0],
    [0, 2, 1, 1, 4, 1, 1, 2, 0],
    [2, 1, 1, 1, 4, 1, 1, 1, 2],
    [2, 1, 1, 1, 1, 1, 1, 1, 2],
    [2, 2, 2, 2, 2, 2, 2, 2, 2],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final px = size.width / _grid;
    final fill = Paint()..color = AppColors.error;
    final border = Paint()..color = AppColors.woodDark;
    final highlight = Paint()..color = AppColors.errorLight;
    final dot = Paint()..color = AppColors.parchment;

    for (var y = 0; y < _grid; y++) {
      for (var x = 0; x < _grid; x++) {
        final cell = _pixels[y][x];
        if (cell == 0) continue;
        final paint = switch (cell) {
          1 => fill,
          2 => border,
          3 => highlight,
          4 => dot,
          _ => fill,
        };
        canvas.drawRect(
          Rect.fromLTWH(x * px, y * px, px + 0.5, px + 0.5),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
