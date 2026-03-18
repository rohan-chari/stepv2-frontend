import 'package:flutter/material.dart';
import 'content_board.dart';
import 'trail_sign.dart';
import '../styles.dart';

/// Enforces the "one board per screen" pattern for tabs.
/// Fixed TrailSign header at top, single scrollable ContentBoard below.
class TabLayout extends StatelessWidget {
  final String title;
  final Widget child;
  final Future<void> Function()? onRefresh;

  const TabLayout({
    super.key,
    required this.title,
    required this.child,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final boardWidth = MediaQuery.of(context).size.width - 48;

    Widget scrollable = SingleChildScrollView(
      padding: const EdgeInsets.only(top: 16, left: 24, right: 24, bottom: 120),
      child: Center(
        child: ContentBoard(
          width: boardWidth,
          child: child,
        ),
      ),
    );

    if (onRefresh != null) {
      scrollable = RefreshIndicator(
        onRefresh: onRefresh!,
        color: AppColors.accent,
        backgroundColor: AppColors.parchment,
        child: AlwaysScrollableScrollView(
          padding: const EdgeInsets.only(top: 16, left: 24, right: 24, bottom: 120),
          child: Center(
            child: ContentBoard(
              width: boardWidth,
              child: child,
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: Column(
        children: [
          // Fixed header
          Padding(
            padding: const EdgeInsets.only(top: 24, left: 24, right: 24),
            child: TrailSign(
              width: boardWidth,
              child: Text(
                title,
                style: PixelText.title(size: 24, color: AppColors.textDark),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          // Scrollable content board
          Expanded(child: scrollable),
        ],
      ),
    );
  }
}

/// A SingleChildScrollView that always allows scrolling (for RefreshIndicator).
class AlwaysScrollableScrollView extends StatelessWidget {
  final EdgeInsets padding;
  final Widget child;

  const AlwaysScrollableScrollView({
    super.key,
    required this.padding,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: padding,
          sliver: SliverToBoxAdapter(child: child),
        ),
      ],
    );
  }
}
