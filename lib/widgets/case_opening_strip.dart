import 'dart:math';
import 'package:flutter/material.dart';
import '../styles.dart';
import 'powerup_icon.dart';

/// CSGO-style horizontal scrolling strip of powerup icons.
/// Rapidly scrolls left, decelerates, and stops with the result under the pointer.
class CaseOpeningStrip extends StatefulWidget {
  final String resultType;
  final String resultRarity;
  final VoidCallback onComplete;
  final double height;

  const CaseOpeningStrip({
    super.key,
    required this.resultType,
    required this.resultRarity,
    required this.onComplete,
    this.height = 90,
  });

  @override
  State<CaseOpeningStrip> createState() => _CaseOpeningStripState();
}

class _CaseOpeningStripState extends State<CaseOpeningStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  late final List<_StripItem> _items;
  late final int _resultIndex;

  static const _itemWidth = 80.0;
  static const _itemSpacing = 6.0;
  static const _totalItemWidth = _itemWidth + _itemSpacing;
  static const _itemCount = 45;
  // Place result near the end so there's a long scroll
  static const _resultPosition = 38;

  static const _rarityByType = {
    'PROTEIN_SHAKE': 'COMMON',
    'SHORTCUT': 'COMMON',
    'RUNNERS_HIGH': 'UNCOMMON',
    'LEG_CRAMP': 'UNCOMMON',
    'STEALTH_MODE': 'UNCOMMON',
    'WRONG_TURN': 'UNCOMMON',
    'RED_CARD': 'RARE',
    'SECOND_WIND': 'RARE',
    'COMPRESSION_SOCKS': 'RARE',
    'FANNY_PACK': 'RARE',
  };

  // Weighted random: common 50%, uncommon 35%, rare 15%
  static const _commonTypes = ['PROTEIN_SHAKE', 'SHORTCUT'];
  static const _uncommonTypes = ['RUNNERS_HIGH', 'LEG_CRAMP', 'STEALTH_MODE', 'WRONG_TURN'];
  static const _rareTypes = ['RED_CARD', 'SECOND_WIND', 'COMPRESSION_SOCKS', 'FANNY_PACK'];

  @override
  void initState() {
    super.initState();
    _items = _generateStrip();
    _resultIndex = _resultPosition;

    _controller = AnimationController(
      duration: const Duration(milliseconds: 4000),
      vsync: this,
    );

    // Total scroll distance: move the result item to the center of the viewport.
    // We'll calculate the target offset in the build method relative to viewport width.
    // For now, animate from 0.0 to 1.0 with a deceleration curve.
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutQuart,
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // Small delay before calling onComplete for dramatic effect
        Future.delayed(const Duration(milliseconds: 600), widget.onComplete);
      }
    });

    // Start after a brief pause
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _controller.forward();
    });
  }

  List<_StripItem> _generateStrip() {
    final rng = Random();
    final items = <_StripItem>[];

    for (int i = 0; i < _itemCount; i++) {
      if (i == _resultPosition) {
        items.add(_StripItem(widget.resultType, widget.resultRarity));
      } else {
        final type = _randomType(rng);
        items.add(_StripItem(type, _rarityByType[type] ?? 'COMMON'));
      }
    }
    return items;
  }

  String _randomType(Random rng) {
    final roll = rng.nextDouble();
    if (roll < 0.50) {
      return _commonTypes[rng.nextInt(_commonTypes.length)];
    } else if (roll < 0.85) {
      return _uncommonTypes[rng.nextInt(_uncommonTypes.length)];
    } else {
      return _rareTypes[rng.nextInt(_rareTypes.length)];
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height + 20, // extra for pointer
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportWidth = constraints.maxWidth;
          final centerX = viewportWidth / 2;

          // The result item's left edge position in the full strip
          final resultItemCenter = _resultIndex * _totalItemWidth + _itemWidth / 2;

          // We want to scroll so the result ends up at centerX
          final totalScroll = resultItemCenter - centerX;

          return Column(
            children: [
              // Pointer triangle
              CustomPaint(
                size: const Size(20, 12),
                painter: _PointerPainter(),
              ),
              const SizedBox(height: 2),
              // Strip viewport
              SizedBox(
                height: widget.height,
                child: ClipRect(
                  child: AnimatedBuilder(
                    animation: _animation,
                    builder: (context, child) {
                      final scrollOffset = _animation.value * totalScroll;
                      return Transform.translate(
                        offset: Offset(-scrollOffset, 0),
                        child: child,
                      );
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (int i = 0; i < _items.length; i++) ...[
                          if (i > 0) SizedBox(width: _itemSpacing),
                          _buildItem(_items[i], i == _resultIndex),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildItem(_StripItem item, bool isResult) {
    final borderColor = _rarityColor(item.rarity);

    return Container(
      width: _itemWidth,
      height: widget.height,
      decoration: BoxDecoration(
        color: AppColors.parchment,
        border: Border.all(color: borderColor, width: 2.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PowerupIcon(type: item.type, size: 36),
          const SizedBox(height: 4),
          Text(
            _rarityLabel(item.rarity),
            style: PixelText.body(
              size: 10,
              color: borderColor,
            ),
          ),
        ],
      ),
    );
  }

  static Color _rarityColor(String rarity) {
    switch (rarity.toUpperCase()) {
      case 'RARE':
        return AppColors.coinDark;
      case 'UNCOMMON':
        return const Color(0xFF4A90D9);
      default:
        return AppColors.woodMid;
    }
  }

  static String _rarityLabel(String rarity) {
    switch (rarity.toUpperCase()) {
      case 'RARE':
        return 'RARE';
      case 'UNCOMMON':
        return 'UNCOMMON';
      default:
        return 'COMMON';
    }
  }
}

class _StripItem {
  final String type;
  final String rarity;
  const _StripItem(this.type, this.rarity);
}

class _PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.coinDark
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
