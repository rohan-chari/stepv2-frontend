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
  bool _waitingForSwipe = false;

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
    'TRAIL_MIX': 'COMMON',
    'DETOUR_SIGN': 'COMMON',
  };

  // Weighted random: common 50%, uncommon 35%, rare 15%
  static const _commonTypes = ['PROTEIN_SHAKE', 'SHORTCUT', 'TRAIL_MIX', 'DETOUR_SIGN'];
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

    // Wait for swipe to start
    _waitingForSwipe = true;
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

  void _startSpin() {
    if (!_waitingForSwipe) return;
    setState(() => _waitingForSwipe = false);
    _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: _waitingForSwipe ? (_) => _startSpin() : null,
      child: LayoutBuilder(
          builder: (context, constraints) {
            final viewportWidth = constraints.maxWidth;
            final centerX = viewportWidth / 2;

            // The result item's left edge position in the full strip
            final resultItemCenter = _resultIndex * _totalItemWidth + _itemWidth / 2;

            // We want to scroll so the result ends up at centerX
            final totalScroll = resultItemCenter - centerX;

            return Column(
              mainAxisSize: MainAxisSize.min,
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
                  width: viewportWidth,
                  child: ClipRect(
                    child: OverflowBox(
                      maxWidth: double.infinity,
                      alignment: Alignment.centerLeft,
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
                ),
                // Swipe hint
                if (_waitingForSwipe) ...[
                  const SizedBox(height: 10),
                  Text(
                    '\u2190  SWIPE TO SPIN  \u2192',
                    style: PixelText.body(
                      size: 14,
                      color: AppColors.coinLight,
                    ),
                  ),
                ],
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
            _typeName(item.type),
            style: PixelText.body(
              size: 10,
              color: borderColor,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
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

  static const _powerupNames = {
    'LEG_CRAMP': 'Leg Cramp',
    'RED_CARD': 'Red Card',
    'SHORTCUT': 'Shortcut',
    'COMPRESSION_SOCKS': 'Compression\nSocks',
    'PROTEIN_SHAKE': 'Protein Shake',
    'RUNNERS_HIGH': "Runner's High",
    'SECOND_WIND': 'Second Wind',
    'STEALTH_MODE': 'Stealth Mode',
    'WRONG_TURN': 'Wrong Turn',
    'FANNY_PACK': 'Fanny Pack',
    'TRAIL_MIX': 'Trail Mix',
    'DETOUR_SIGN': 'Detour Sign',
  };

  static String _typeName(String type) {
    return _powerupNames[type] ?? type;
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
