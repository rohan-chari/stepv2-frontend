import 'package:flutter/material.dart';

import '../styles.dart';
import 'home_chrome.dart';

String _formatStepCount(int value) {
  final digits = value.abs().toString();
  final firstGroup = digits.length % 3;
  if (firstGroup == 0) {
    return RegExp(r'.{3}').allMatches(digits).map((m) => m.group(0)!).join(',');
  }
  final groups = <String>[digits.substring(0, firstGroup)];
  for (var i = firstGroup; i < digits.length; i += 3) {
    groups.add(digits.substring(i, i + 3));
  }
  return groups.join(',');
}

/// A signed step delta with the visual treatment shared by race and Home
/// bonus popups. Zero is intentionally not renderable: a zero delta is not a
/// user-visible step change.
class SignedStepAmount extends StatelessWidget {
  const SignedStepAmount({super.key, required this.steps, this.size = 26});

  final int steps;
  final double size;

  @override
  Widget build(BuildContext context) {
    final positive = steps > 0;
    final sign = positive ? '+' : '-';
    final amount = _formatStepCount(steps);
    return Text(
      '$sign$amount steps',
      textAlign: TextAlign.center,
      style: HomeText.display(
        size: size,
        color: positive
            ? AppColors.of(context).success
            : AppColors.of(context).error,
      ).copyWith(fontWeight: FontWeight.w900),
    );
  }
}
