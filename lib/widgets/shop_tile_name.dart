import 'package:flutter/material.dart';
import '../styles.dart';

/// The tile's item name at the largest size that still fits two lines.
///
/// The responsive redesign supports a larger nominal name size while this
/// still picks the biggest size from [_sizes] whose
/// two-line layout fits the tile, so the type gets bigger wherever there's room
/// and never smaller than what shipped.
class ShopTileName extends StatelessWidget {
  const ShopTileName({super.key, required this.name, required this.color});

  final String name;
  final Color color;

  /// Largest first. The floor is deliberately below the old 11pt: on the
  /// narrowest phones a long name would otherwise still ellipsise.
  static const _sizes = [13.0, 12.0, 11.0, 10.0, 9.0];

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        var chosen = _sizes.last;
        for (final size in _sizes) {
          final painter = TextPainter(
            text: TextSpan(
              text: name,
              style: PixelText.title(size: size),
            ),
            maxLines: 2,
            textAlign: TextAlign.center,
            textDirection: direction,
            textScaler: textScaler,
          )..layout(maxWidth: constraints.maxWidth);
          final fits =
              !painter.didExceedMaxLines &&
              painter.height <= constraints.maxHeight;
          painter.dispose();
          if (fits) {
            chosen = size;
            break;
          }
        }
        return Text(
          name,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: PixelText.title(size: chosen, color: color),
        );
      },
    );
  }
}
