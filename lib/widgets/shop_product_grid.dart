import 'package:flutter/material.dart';

/// Shared merchandise geometry for Featured and Powerups.
class ShopProductGrid extends StatelessWidget {
  const ShopProductGrid({
    super.key,
    required this.children,
    this.gridKey,
    this.compact = false,
    this.spaciousPowerups = false,
  });
  final List<Widget> children;
  final Key? gridKey;
  final bool compact;
  final bool spaciousPowerups;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 600;
      final grid = GridView.count(
        key: gridKey,
        crossAxisCount: spaciousPowerups
            ? (MediaQuery.textScalerOf(context).scale(1) > 1.3 ||
                      constraints.maxWidth < 320
                  ? 2
                  : wide
                  ? 5
                  : 3)
            : compact
            ? ((constraints.maxWidth >= 600
                          ? 6
                          : constraints.maxWidth >= 360
                          ? 4
                          : 3) /
                      MediaQuery.textScalerOf(context).scale(1).clamp(1, 2))
                  .floor()
                  .clamp(2, 6)
            : wide
            ? 4
            : 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: spaciousPowerups
            ? const EdgeInsets.fromLTRB(16, 12, 16, 8)
            : const EdgeInsets.fromLTRB(10, 10, 10, 6),
        mainAxisSpacing: spaciousPowerups ? 16 : 14,
        crossAxisSpacing: 12,
        childAspectRatio: spaciousPowerups
            ? 0.68
            : !wide && constraints.maxWidth < 350
            ? 0.70
            : 0.82,
        children: children,
      );
      return spaciousPowerups
          ? Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: grid,
              ),
            )
          : grid;
    },
  );
}
