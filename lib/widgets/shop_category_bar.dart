import 'package:flutter/material.dart';
import '../styles.dart';

/// The shop owns its navigation for the lifetime of its pushed route.
enum ShopCategory { featured, powerups, characters }

extension ShopCategoryPresentation on ShopCategory {
  String get label => switch (this) {
    ShopCategory.featured => 'FEATURED',
    ShopCategory.powerups => 'POWERUPS',
    ShopCategory.characters => 'CHARACTERS',
  };
  IconData get icon => switch (this) {
    ShopCategory.featured => Icons.auto_awesome_rounded,
    ShopCategory.powerups => Icons.bolt_rounded,
    ShopCategory.characters => Icons.pets_rounded,
  };
}

class ShopCategoryBar extends StatelessWidget {
  const ShopCategoryBar({
    super.key,
    required this.selected,
    required this.onSelected,
  });
  final ShopCategory selected;
  final ValueChanged<ShopCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return ColoredBox(
      color: colors.roofLight,
      child: SafeArea(
        top: false,
        child: Padding(
          key: const Key('shop-bottom-navigation'),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Row(
            children: [
              for (final category in ShopCategory.values) ...[
                if (category != ShopCategory.featured) const SizedBox(width: 6),
                Expanded(
                  child: Semantics(
                    key: Key('shop-category-semantics-${category.label}'),
                    button: true,
                    selected: category == selected,
                    label: '${category.label} category',
                    child: InkWell(
                      key: Key('shop-category-${category.label}'),
                      onTap: () => onSelected(category),
                      borderRadius: BorderRadius.circular(10),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        constraints: const BoxConstraints(minHeight: 56),
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 3,
                        ),
                        decoration: BoxDecoration(
                          color: category == selected
                              ? colors.parchment
                              : Colors.black.withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: category == selected
                                ? colors.pillGoldDark
                                : colors.textLight.withValues(alpha: .14),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              category.icon,
                              size: 20,
                              color: category == selected
                                  ? colors.coinDark
                                  : colors.textLight,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              category.label,
                              textAlign: TextAlign.center,
                              style: PixelText.title(
                                size: 10.5,
                                color: category == selected
                                    ? colors.textDark
                                    : colors.textLight,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
