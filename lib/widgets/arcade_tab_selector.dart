import 'package:flutter/material.dart';

import '../styles.dart';

/// A two-segment arcade-styled pill tab selector.
///
/// Renders side-by-side pill buttons; the active tab uses primary arcade
/// colors and inactive tabs use muted parchment colors. An optional unread
/// dot appears on a tab's label.
class ArcadeTabSelector extends StatelessWidget {
  final List<String> labels;
  final int activeIndex;
  final ValueChanged<int> onChanged;

  /// Per-index unread indicators. A dot is drawn when the entry is true and
  /// the tab is not currently active.
  final List<bool> unread;

  const ArcadeTabSelector({
    super.key,
    required this.labels,
    required this.activeIndex,
    required this.onChanged,
    this.unread = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.parchmentDark.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.parchmentBorder),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: _TabPill(
                label: labels[i],
                active: i == activeIndex,
                showUnread:
                    i != activeIndex && i < unread.length && unread[i],
                onTap: () => onChanged(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  final String label;
  final bool active;
  final bool showUnread;
  final VoidCallback onTap;

  const _TabPill({
    required this.label,
    required this.active,
    required this.showUnread,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = active ? AppColors.accent : Colors.transparent;
    final textColor = active
        ? Colors.white
        : AppColors.textMid.withValues(alpha: 0.8);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: PixelText.title(size: 14, color: textColor),
            ),
            if (showUnread) ...[
              const SizedBox(width: 6),
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
