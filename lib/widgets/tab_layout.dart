import 'package:flutter/material.dart';
import 'content_board.dart';
import '../styles.dart';

/// Single full-screen section layout for non-home tabs.
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
    final isPushedRoute = Navigator.canPop(context);
    final tabBarHeight = 77.5 + bottomInset;
    final boardBottomPadding = isPushedRoute
        ? bottomInset + 24
        : tabBarHeight + 110;

    return Column(
      children: [
        // Sky area above the board (status bar / notch region)
        SizedBox(height: topInset + (isPushedRoute ? 12 : 24)),
        // Board from here down to the nav bar
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: boardBottomPadding),
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
                                size: 24,
                                color: AppColors.of(context).textDark,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Container(
                            height: 1,
                            color: AppColors.of(
                              context,
                            ).parchmentBorder.withValues(alpha: 0.5),
                          ),
                        ],
                        Expanded(
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: child,
                            ),
                          ),
                        ),
                      ],
                    )
                  : _buildScrollable(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScrollableContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTitle) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (Navigator.canPop(context))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: Icon(
                        Icons.arrow_back,
                        color: AppColors.of(context).textDark,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                Text(
                  title,
                  style: PixelText.title(
                    size: 24,
                    color: AppColors.of(context).textDark,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          Container(
            height: 1,
            color: AppColors.of(context).parchmentBorder.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
        ],
        child,
      ],
    );
  }

  Widget _buildScrollable(BuildContext context) {
    if (onRefresh != null) {
      return RefreshIndicator(
        onRefresh: onRefresh!,
        color: AppColors.of(context).accent,
        backgroundColor: AppColors.of(context).parchment,
        child: AlwaysScrollableScrollView(
          padding: const EdgeInsets.only(top: 4, bottom: 16),
          child: _buildScrollableContent(context),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      child: _buildScrollableContent(context),
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
