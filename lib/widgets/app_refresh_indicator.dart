import 'package:flutter/material.dart';

import '../styles.dart';

/// The single source of truth for pull-to-refresh styling across the app.
///
/// Every screen used to construct its own [RefreshIndicator] with a hardcoded
/// `color: accent` (green), which is illegible on the night parchment. Routing
/// all sites through this widget keeps the spinner on-brand and legible in both
/// themes: slate-blue ([AppPalette.pillTerra]) in dark, forest green
/// ([AppPalette.accent]) in light, on the parchment surface.
class AppRefreshIndicator extends StatelessWidget {
  const AppRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
    this.edgeOffset,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  /// Forwarded to [RefreshIndicator.edgeOffset] for screens whose scrollable
  /// starts under a status-bar inset (e.g. the home tab).
  final double? edgeOffset;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return RefreshIndicator(
      onRefresh: onRefresh,
      edgeOffset: edgeOffset ?? 0.0,
      color: colors.isDark ? colors.pillTerra : colors.accent,
      backgroundColor: colors.parchment,
      child: child,
    );
  }
}
