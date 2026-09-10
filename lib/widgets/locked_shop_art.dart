import 'package:flutter/material.dart';
import '../styles.dart';

/// A decorative lock over the bounded artwork region, keeping card taps intact.
class LockedShopArt extends StatelessWidget {
  const LockedShopArt({super.key, required this.child, required this.locked});

  final Widget child;
  final bool locked;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      if (locked)
        ColorFiltered(
          key: const Key('locked-shop-art-shade'),
          colorFilter: ColorFilter.mode(
            Colors.black.withValues(alpha: .22),
            BlendMode.srcATop,
          ),
          child: child,
        )
      else
        child,
      if (locked)
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: Center(
                child: Icon(
                  Icons.lock_rounded,
                  size: 28,
                  color: AppColors.of(context).textLight,
                  shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
