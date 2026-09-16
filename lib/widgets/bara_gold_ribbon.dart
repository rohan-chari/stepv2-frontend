import 'package:flutter/material.dart';

import '../styles.dart';

/// Shared Gold identity chrome for catalog and wardrobe surfaces.
class BaraGoldRibbon extends StatelessWidget {
  const BaraGoldRibbon({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final body = colors.isDark ? colors.medalGold : colors.pillGold;
    final edge = colors.isDark ? colors.pillGoldShadow : colors.pillGoldDark;
    return DecoratedBox(
      key: const Key('bara-gold-ribbon'),
      decoration: const BoxDecoration(),
      child: SizedBox(
        width: compact ? 116 : 148,
        height: compact ? 35 : 43,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _BaraGoldRibbonPainter(body: body, edge: edge),
            ),
            Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: compact ? 1 : 2),
                child: Text(
                  'Bara Gold',
                  style: PixelText.title(
                    size: compact ? 9 : 10,
                    color: colors.textLight,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BaraGoldRibbonPainter extends CustomPainter {
  const _BaraGoldRibbonPainter({required this.body, required this.edge});

  final Color body;
  final Color edge;

  @override
  void paint(Canvas canvas, Size size) {
    final shadow = Paint()..color = edge.withValues(alpha: .9);
    final fill = Paint()..color = body;
    final outline = Paint()
      ..color = edge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round;

    final leftTail = _tailPath(size, left: true, yOffset: 3);
    final rightTail = _tailPath(size, left: false, yOffset: 3);
    canvas.drawPath(leftTail, shadow);
    canvas.drawPath(rightTail, shadow);

    final shadowBody = _bodyPath(size, yOffset: 3);
    canvas.drawPath(shadowBody, shadow);

    canvas.drawPath(_tailPath(size, left: true), fill);
    canvas.drawPath(_tailPath(size, left: false), fill);
    canvas.drawPath(_bodyPath(size), fill);

    canvas.drawPath(_tailPath(size, left: true), outline);
    canvas.drawPath(_tailPath(size, left: false), outline);
    canvas.drawPath(_bodyPath(size), outline);
  }

  Path _tailPath(Size size, {required bool left, double yOffset = 0}) {
    final outer = left ? 1.0 : size.width - 1.0;
    final inner = left ? 22.0 : size.width - 22.0;
    final direction = left ? 1.0 : -1.0;
    return Path()
      ..moveTo(inner, 9 + yOffset)
      ..lineTo(outer, 8 + yOffset)
      ..lineTo(outer + direction * 5, 15 + yOffset)
      ..lineTo(outer, 20 + yOffset)
      ..lineTo(outer + direction * 6, 28 + yOffset)
      ..quadraticBezierTo(
        outer + direction * 11,
        30 + yOffset,
        outer + direction * 16,
        26 + yOffset,
      )
      ..lineTo(inner, 23 + yOffset)
      ..close();
  }

  Path _bodyPath(Size size, {double yOffset = 0}) {
    final left = 14.0;
    final right = size.width - 14.0;
    final top = 3.0 + yOffset;
    final bottom = size.height - 8.0 + yOffset;
    return Path()
      ..moveTo(left + 10, top)
      ..lineTo(right - 10, top)
      ..quadraticBezierTo(right, top, right, top + 10)
      ..lineTo(right, bottom - 7)
      ..quadraticBezierTo(right, bottom, right - 9, bottom - 1)
      ..quadraticBezierTo(size.width / 2, bottom + 3, left + 9, bottom - 1)
      ..quadraticBezierTo(left, bottom, left, bottom - 7)
      ..lineTo(left, top + 10)
      ..quadraticBezierTo(left, top, left + 10, top)
      ..close();
  }

  @override
  bool shouldRepaint(covariant _BaraGoldRibbonPainter oldDelegate) =>
      oldDelegate.body != body || oldDelegate.edge != edge;
}
