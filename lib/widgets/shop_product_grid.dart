import 'package:flutter/material.dart';

/// Shared merchandise geometry for Featured and Powerups.
class ShopProductGrid extends StatelessWidget {
  const ShopProductGrid({
    super.key,
    required this.children,
    this.gridKey,
    this.compact = false,
  });
  final List<Widget> children;
  final Key? gridKey;
  final bool compact;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 600;
      return GridView.count(
        key: gridKey,
        crossAxisCount: compact
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
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
        mainAxisSpacing: 14,
        crossAxisSpacing: 12,
        childAspectRatio: !wide && constraints.maxWidth < 350 ? 0.70 : 0.82,
        children: children,
      );
    },
  );
}
