import 'package:flutter/material.dart';

import 'home_chrome.dart';

class WoodenTabItem {
  final IconData icon;
  final String label;
  final int badgeCount;

  const WoodenTabItem({
    required this.icon,
    required this.label,
    this.badgeCount = 0,
  });
}

class WoodenTabBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<WoodenTabItem> items;

  const WoodenTabBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: HomeColors.surface,
        border: Border(
          top: BorderSide(
            color: HomeColors.lineSoft.withValues(alpha: 0.95),
            width: 2,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: HomeColors.ink.withValues(alpha: 0.14),
            blurRadius: 0,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.fromLTRB(12, 8, 12, bottomPadding > 0 ? 4 : 10),
        child: Row(
          children: [
            for (var index = 0; index < items.length; index++)
              Expanded(
                child: _TabItemWidget(
                  item: items[index],
                  selected: index == currentIndex,
                  onTap: () => onTap(index),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TabItemWidget extends StatelessWidget {
  final WoodenTabItem item;
  final bool selected;
  final VoidCallback onTap;

  const _TabItemWidget({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? HomeColors.ink : HomeColors.muted;
    final background = selected ? HomeColors.surfaceMuted : Colors.transparent;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: 56,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? HomeColors.lineSoft.withValues(alpha: 0.95)
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(item.icon, size: 23, color: color),
                  if (item.badgeCount > 0)
                    Positioned(
                      top: -7,
                      right: -9,
                      child: _Badge(count: item.badgeCount),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HomeText.body(
                  size: 10,
                  color: color,
                  weight: selected ? FontWeight.w800 : FontWeight.w700,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: HomeColors.clay,
        shape: BoxShape.circle,
        border: Border.all(color: HomeColors.surface, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Text(
          '$count',
          style: HomeText.body(
            size: 9,
            color: Colors.white,
            weight: FontWeight.w900,
            height: 1,
          ),
        ),
      ),
    );
  }
}
