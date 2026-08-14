import 'dart:math';

import 'package:flutter/material.dart';

import '../styles.dart';
import 'arcade_fx.dart';
import 'powerup_icon.dart';
import 'spinning_crate.dart';
import '../constants/powerup_copy.dart';

/// Large, card-free mystery-box action used as the focal point of POWERUPS.
/// The generous transparent tap target preserves accessibility while the crate
/// itself stays visually standalone. Shared arcade motion primitives provide a
/// synchronized shimmer/jiggle and automatically honor reduced motion.
class MysteryBoxButton extends StatelessWidget {
  const MysteryBoxButton({
    super.key,
    required this.onTap,
    this.crateSize = 68,
    this.expandTapTarget = false,
  });

  final VoidCallback? onTap;
  final double crateSize;
  final bool expandTapTarget;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final visualSize = crateSize + 18;

    return Semantics(
      button: true,
      enabled: onTap != null,
      label: 'Open mystery box',
      onTap: onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          excludeFromSemantics: true,
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: crateSize + 34),
            child: SizedBox(
              width: expandTapTarget ? double.infinity : crateSize + 34,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRect(
                    child: ShineSweep(
                      period: const Duration(milliseconds: 3200),
                      width: 34,
                      opacity: 0.34,
                      child: SizedBox.square(
                        dimension: visualSize,
                        child: Center(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: palette.coinMid.withValues(
                                    alpha: 0.34,
                                  ),
                                  blurRadius: 16,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: WobbleBadge(
                              period: const Duration(milliseconds: 3200),
                              maxAngle: 0.10,
                              child: CrateIcon(size: crateSize),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'OPEN',
                    style: PixelText.title(size: 11, color: palette.coinDark),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum ItemSlotState { empty, held }

/// An animated powerup slot for empty capacity and held powerups.
class ItemSlot extends StatefulWidget {
  final ItemSlotState state;
  final String? powerupType;
  final String? rarity;
  final bool isExtraSlot;
  final VoidCallback? onTap;
  final Key? shellKey;

  const ItemSlot({
    super.key,
    required this.state,
    this.powerupType,
    this.rarity,
    this.isExtraSlot = false,
    this.onTap,
    this.shellKey,
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
    );
    if (widget.state == ItemSlotState.empty) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant ItemSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state == widget.state) return;
    if (widget.state == ItemSlotState.empty) {
      _controller
        ..value = 0
        ..repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: GestureDetector(
          onTap: widget.onTap,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final slotHeight = min(constraints.maxWidth, 82.0);
              return SizedBox(
                height: slotHeight,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final t = _controller.value;
                    switch (widget.state) {
                      case ItemSlotState.empty:
                        return _buildEmpty(t);
                      case ItemSlotState.held:
                        return _buildHeld();
                    }
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSlotShell({
    required Widget child,
    required Color color,
    required Color borderColor,
    required double borderWidth,
    required List<BoxShadow> boxShadow,
  }) {
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
      child: child,
    );

    return Container(
      key: widget.shellKey,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: boxShadow,
      ),
      child: content,
    );
  }

  Widget _buildEmpty(double t) {
    final rotationY = t * 2 * pi;
    final colors = AppColors.of(context);

    return _buildSlotShell(
      color: colors.emptySlotFace,
      borderColor: colors.emptySlotBorder,
      borderWidth: 2,
      boxShadow: [
        BoxShadow(
          color: AppColors.of(context).woodShadow.withValues(alpha: 0.3),
          offset: const Offset(0, 3),
          blurRadius: 6,
        ),
      ],
      child: Column(
        children: [
          Expanded(
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
                    color: colors.emptySlotMark,
                    shadows: [
                      Shadow(
                        color: colors.emptySlotBorder,
                        offset: const Offset(1.5, 1.5),
                        blurRadius: 0,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.isExtraSlot ? 'Bonus' : 'Empty',
            style: PixelText.title(size: 9, color: colors.emptySlotLabel),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildHeld() {
    return _buildSlotShell(
      color: AppColors.of(context).parchmentLight,
      borderColor: AppColors.of(context).parchmentBorder,
      borderWidth: widget.isExtraSlot ? 2.5 : 2,
      boxShadow: [
        BoxShadow(
          color: AppColors.of(context).woodShadow.withValues(alpha: 0.25),
          offset: const Offset(0, 3),
          blurRadius: 6,
        ),
      ],
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: PowerupIcon(type: widget.powerupType ?? '', size: 40),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            PowerupCopy.nameFor(widget.powerupType),
            style: PixelText.title(
              size: 8,
              color: AppColors.of(context).textDark,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
