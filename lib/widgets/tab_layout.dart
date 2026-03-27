import 'package:flutter/material.dart';
import 'content_board.dart';
import '../styles.dart';

/// Single full-screen board layout for tabs.
/// Sky background shows above the board (behind the notch/status bar).
/// The wood frame starts below the safe area, contains the title + content,
/// and its bottom rests on the nav bar.
class TabLayout extends StatelessWidget {
  final String title;
  final Widget child;
  final Future<void> Function()? onRefresh;
  final bool centerContent;
  final bool showTitle;

  const TabLayout({
    super.key,
    required this.title,
    required this.child,
    this.onRefresh,
    this.centerContent = false,
    this.showTitle = true,
  });

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final tabBarHeight = 77.5 + bottomInset;

    return Column(
      children: [
        // Sky area above the board (status bar / notch region)
        SizedBox(height: topInset + 24),
        // Board from here down to the nav bar
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: tabBarHeight + 110),
            child: ContentBoard(
              expand: true,
              child: centerContent
                  ? Column(
                      children: [
                        if (showTitle) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 8),
                            child: Text(
                              title,
                              style: PixelText.title(
                                  size: 24, color: AppColors.textDark),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Container(
                            height: 1,
                            color: AppColors.parchmentBorder
                                .withValues(alpha: 0.5),
                          ),
                        ],
                        Expanded(
                          child: Center(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: child,
                            ),
                          ),
                        ),
                      ],
                    )
                  : _buildScrollable(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScrollableContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTitle) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              title,
              style: PixelText.title(size: 24, color: AppColors.textDark),
              textAlign: TextAlign.center,
            ),
          ),
          Container(
            height: 1,
            color: AppColors.parchmentBorder.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
        ],
        child,
      ],
    );
  }

  Widget _buildScrollable() {
    if (onRefresh != null) {
      return RefreshIndicator(
        onRefresh: onRefresh!,
        color: AppColors.accent,
        backgroundColor: AppColors.parchment,
        child: AlwaysScrollableScrollView(
          padding: const EdgeInsets.only(top: 4, bottom: 16),
          child: _buildScrollableContent(),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      child: _buildScrollableContent(),
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
