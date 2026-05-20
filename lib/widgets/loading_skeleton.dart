import 'package:flutter/material.dart';

import '../styles.dart';
import 'game_container.dart';
import 'pill_button.dart';

class LoadingSkeleton extends StatefulWidget {
  const LoadingSkeleton({
    super.key,
    required this.child,
    this.baseColor,
    this.highlightColor,
  });

  final Widget child;
  final Color? baseColor;
  final Color? highlightColor;

  @override
  State<LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends State<LoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..repeat(reverse: true);
    _opacity = Tween<double>(
      begin: 0.48,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _opacity, child: widget.child);
  }
}

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.radius = 6,
    this.color,
  });

  final double width;
  final double height;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color ?? AppColors.parchmentDark.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class SkeletonLine extends StatelessWidget {
  const SkeletonLine({super.key, this.width, this.height = 12, this.color});

  final double? width;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SkeletonBox(
      width: width ?? double.infinity,
      height: height,
      radius: height / 2,
      color: color,
    );
  }
}

class SkeletonCircle extends StatelessWidget {
  const SkeletonCircle({super.key, required this.size, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color ?? AppColors.parchmentDark.withValues(alpha: 0.55),
        shape: BoxShape.circle,
      ),
    );
  }
}

class ListSkeleton extends StatelessWidget {
  const ListSkeleton({
    super.key,
    required this.itemCount,
    this.showAvatar = false,
    this.itemHeight = 58,
  });

  final int itemCount;
  final bool showAvatar;
  final double itemHeight;

  @override
  Widget build(BuildContext context) {
    return LoadingSkeleton(
      child: GameContainer(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
        child: Column(
          children: [
            for (var i = 0; i < itemCount; i++) ...[
              if (i > 0)
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  color: AppColors.parchmentBorder.withValues(alpha: 0.35),
                ),
              SizedBox(
                height: itemHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      if (showAvatar) ...[
                        const SkeletonCircle(size: 34),
                        const SizedBox(width: 10),
                      ],
                      const Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonLine(width: 150, height: 14),
                            SizedBox(height: 8),
                            SkeletonLine(width: 92, height: 10),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      const SkeletonLine(width: 52, height: 16),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class LoadErrorPanel extends StatelessWidget {
  const LoadErrorPanel({
    super.key,
    required this.title,
    this.message,
    this.onRetry,
    this.icon = Icons.wifi_off_rounded,
  });

  final String title;
  final String? message;
  final VoidCallback? onRetry;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return GameContainer(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32, color: AppColors.textMid.withValues(alpha: 0.7)),
          const SizedBox(height: 8),
          Text(
            title,
            style: PixelText.title(size: 15, color: AppColors.textDark),
            textAlign: TextAlign.center,
          ),
          if (message != null && message!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              style: PixelText.body(size: 13, color: AppColors.textMid),
              textAlign: TextAlign.center,
            ),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: 14),
            PillButton(
              label: 'TRY AGAIN',
              variant: PillButtonVariant.secondary,
              fontSize: 12,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}
