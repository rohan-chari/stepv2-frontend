import 'package:flutter/material.dart';

/// Shared merchandise geometry for Featured and Powerups.
class ShopProductGrid extends StatelessWidget {
  const ShopProductGrid({super.key, required this.children, this.gridKey});
  final List<Widget> children;
  final Key? gridKey;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 600;
      return GridView.count(
        key: gridKey,
        crossAxisCount: wide ? 4 : 3,
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
