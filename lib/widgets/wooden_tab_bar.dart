import 'package:flutter/material.dart';
import '../styles.dart';

class WoodenTabItem {
  final IconData icon;
  final String label;
  final int badgeCount;

  const WoodenTabItem({
    required this.icon,
    required this.label,
    this.badgeCount = 0,
  });
}

class WoodenTabBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<WoodenTabItem> items;

  const WoodenTabBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.woodDark,
        border: Border(
          top: BorderSide(color: AppColors.woodShadow, width: 2),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Wood highlight bevel
          Container(
            height: 1.5,
            color: AppColors.woodHighlight.withValues(alpha: 0.4),
          ),
          // Wood grain texture row
          CustomPaint(
            size: const Size(double.infinity, 2),
            painter: _TabBarGrainPainter(),
          ),
          // Tab items with sliding board indicator
          Padding(
            padding: EdgeInsets.only(
              top: 8,
              bottom: bottomPadding + 10,
              left: 12,
              right: 12,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tabWidth = constraints.maxWidth / items.length;
                const boardWidth = 72.0;
                const boardHeight = 54.0;

                return Stack(
                  children: [
                    // Sliding mini bulletin board
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      left: tabWidth * currentIndex +
                          (tabWidth - boardWidth) / 2,
                      top: 0,
                      child: SizedBox(
                        width: boardWidth,
                        height: boardHeight,
                        child: const _MiniBulletinBoard(),
                      ),
                    ),
                    // Tab items on top
                    Row(
                      children: List.generate(items.length, (index) {
                        final item = items[index];
                        final selected = index == currentIndex;

                        return Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => onTap(index),
                            child: SizedBox(
                              height: boardHeight,
                              child: _TabItemWidget(
                                item: item,
                                selected: selected,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A tiny wooden-framed parchment board that slides behind the active tab.
class _MiniBulletinBoard extends StatelessWidget {
  const _MiniBulletinBoard();

  @override
  Widget build(BuildContext context) {
    const px = 2.0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.woodMid,
        border: Border.all(color: AppColors.woodShadow, width: px),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        children: [
          // Wood grain
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: CustomPaint(
                painter: _MiniGrainPainter(px: px),
              ),
            ),
          ),
          // Inner parchment
          Padding(
            padding: const EdgeInsets.all(px * 2),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.parchment,
                border: Border.all(
                  color: AppColors.parchmentBorder,
                  width: px * 0.75,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabItemWidget extends StatelessWidget {
  final WoodenTabItem item;
  final bool selected;

  const _TabItemWidget({
    required this.item,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accent : AppColors.parchmentDark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(item.icon, size: 22, color: color),
            // Badge
            if (item.badgeCount > 0)
              Positioned(
                top: -6,
                right: -10,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Color(0xFFE05040),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xFF8B2020),
                        offset: Offset(0, 1),
                        blurRadius: 0,
                      ),
                    ],
                  ),
                  child: Text(
                    '${item.badgeCount}',
                    style: PixelText.button(size: 9, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          item.label,
          style: PixelText.body(
            size: 10,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _TabBarGrainPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final grainPaint = Paint()
      ..color = AppColors.woodGrain.withValues(alpha: 0.3);
    for (double x = 0; x < size.width; x += 12) {
      canvas.drawRect(
        Rect.fromLTWH(x, 0, 6, size.height),
        grainPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MiniGrainPainter extends CustomPainter {
  final double px;
  _MiniGrainPainter({required this.px});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.woodGrain.withValues(alpha: 0.3);
    for (double y = px; y < size.height; y += px * 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, px * 0.5), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

