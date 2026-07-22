import 'package:flutter/material.dart';

import '../styles.dart';

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

  /// Optional per-item keys, aligned by index. Used by the tutorial to
  /// spotlight a specific tab (e.g. Ranked). Null entries are skipped, so the
  /// real app can omit this entirely without any wrapper overhead.
  final List<GlobalKey?>? itemKeys;

  const WoodenTabBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    this.itemKeys,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return DecoratedBox(
      // Deep forest bar so the arcade-green tabs sit on a darker "ledge";
      // matches the ink borders of the game-piece cards above it.
      decoration: BoxDecoration(
        color: AppColors.of(context).roofDark,
        border: Border(
          top: BorderSide(color: AppColors.of(context).roofEdge, width: 2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
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
                child: _withItemKey(
                  index,
                  _TabItemWidget(
                    item: items[index],
                    selected: index == currentIndex,
                    onTap: () => onTap(index),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _withItemKey(int index, Widget child) {
    final key = (itemKeys != null && index < itemKeys!.length)
        ? itemKeys![index]
        : null;
    return key == null ? child : KeyedSubtree(key: key, child: child);
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
    // Selected tab reads like the clay-gold game buttons; inactive items keep
    // enough contrast to remain obvious navigation in both themes.
    final color = selected
        ? AppColors.of(context).textDark
        : AppColors.of(context).isDark
        ? AppColors.of(context).textMid
        : AppColors.of(context).textLight;
    final background = selected
        ? AppColors.of(context).pillGold
        : Colors.transparent;

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
                  ? AppColors.of(context).pillGoldDark
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
                style: PixelText.body(size: 10, color: color).copyWith(
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
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
        color: AppColors.of(context).pillTerra,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.of(context).roofDark, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Text(
          '$count',
          style: PixelText.body(
            size: 9,
            color: Colors.white,
          ).copyWith(fontWeight: FontWeight.w900, height: 1),
        ),
      ),
    );
  }
}
