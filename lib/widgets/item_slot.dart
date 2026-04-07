import 'dart:math';
import 'package:flutter/material.dart';
import '../styles.dart';
import 'powerup_icon.dart';
import 'spinning_crate.dart';

const _powerupNames = {
  'LEG_CRAMP': 'Leg Cramp',
  'RED_CARD': 'Red Card',
  'SHORTCUT': 'Shortcut',
  'COMPRESSION_SOCKS': 'Socks',
  'PROTEIN_SHAKE': 'Protein',
  'RUNNERS_HIGH': "Runner's High",
  'SECOND_WIND': 'Wind',
  'STEALTH_MODE': 'Stealth',
  'WRONG_TURN': 'Wrong Turn',
  'FANNY_PACK': 'Fanny Pack',
  'TRAIL_MIX': 'Trail Mix',
  'DETOUR_SIGN': 'Detour',
};

enum ItemSlotState { empty, held, mysteryBox }

/// An animated powerup slot with three visual states.
class ItemSlot extends StatefulWidget {
  final ItemSlotState state;
  final String? powerupType;
  final String? rarity;
  final bool isExtraSlot;
  final VoidCallback? onTap;

  const ItemSlot({
    super.key,
    required this.state,
    this.powerupType,
    this.rarity,
    this.isExtraSlot = false,
    this.onTap,
  });

  @override
  State<ItemSlot> createState() => _ItemSlotState();
}

class _ItemSlotState extends State<ItemSlot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
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
    return Expanded(
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final t = _controller.value;
            switch (widget.state) {
              case ItemSlotState.empty:
                return _buildEmpty(t);
              case ItemSlotState.held:
                return _buildHeld();
              case ItemSlotState.mysteryBox:
                return _buildMysteryBox(t);
            }
          },
        ),
      ),
    );
  }

  Widget _buildEmpty(double t) {
    // 3D Y-axis rotation for the "?"
    final rotationY = t * 2 * pi;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFC48C3C),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF6B4420), width: 2),
          boxShadow: [
            BoxShadow(
              color: AppColors.woodShadow.withValues(alpha: 0.3),
              offset: const Offset(0, 3),
              blurRadius: 6,
            ),
          ],
        ),
        child: Column(
          children: [
            SizedBox(
              height: 32,
              child: Center(
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.003)
                    ..rotateY(rotationY),
                  child: Text(
                    '?',
                    style: TextStyle(
                      fontSize: 24,
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
              ),
            ),
            const SizedBox(height: 2),
            Text(
              widget.isExtraSlot ? 'Bonus' : 'Empty',
              style: PixelText.title(
                size: 9,
                color: AppColors.textMid.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeld() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.parchment,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppColors.parchmentBorder,
            width: widget.isExtraSlot ? 2.5 : 2,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.woodShadow.withValues(alpha: 0.25),
              offset: const Offset(0, 3),
              blurRadius: 6,
            ),
          ],
        ),
        child: Column(
          children: [
            SizedBox(
              height: 32,
              child: PowerupIcon(type: widget.powerupType ?? '', size: 24),
            ),
            const SizedBox(height: 2),
            Text(
              _powerupNames[widget.powerupType] ?? widget.powerupType ?? '',
              style: PixelText.title(size: 8, color: AppColors.textDark),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMysteryBox(double t) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.parchmentDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.coinMid, width: 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.coinMid.withValues(alpha: 0.35),
            spreadRadius: 1,
            blurRadius: 8,
          ),
          BoxShadow(
            color: AppColors.woodShadow.withValues(alpha: 0.25),
            offset: const Offset(0, 3),
            blurRadius: 6,
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 28, child: SpinningCrate(size: 22)),
          const SizedBox(height: 2),
          Text(
            'Open',
            style: PixelText.title(size: 9, color: AppColors.coinDark),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
