import 'package:flutter/material.dart';
import '../styles.dart';

/// A thin retro bulletin-board-style card: wood frame outline with
/// parchment interior. Inspired by ContentBoard but much thinner.
class RetroCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? highlightColor;

  const RetroCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: highlightColor ?? AppColors.woodDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: highlightColor ?? AppColors.woodShadow,
          width: 0.5,
        ),
      ),
      padding: const EdgeInsets.all(1.5),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: AppColors.parchment,
          borderRadius: BorderRadius.circular(8),
        ),
        child: child,
      ),
    );
  }
}
