import 'package:flutter/material.dart';

import '../styles.dart';
import '../widgets/game_container.dart';
import '../widgets/info_board_card.dart';
import '../widgets/pill_button.dart';

class SpotlightOverlay extends StatelessWidget {
  const SpotlightOverlay({
    super.key,
    required this.targetRect,
    required this.title,
    required this.body,
    required this.stepIndex,
    required this.stepCount,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  final Rect? targetRect;
  final String title;
  final String body;
  final int stepIndex;
  final int stepCount;
  final VoidCallback onNext;
  final VoidCallback? onBack;
  final VoidCallback onSkip;

  static const double _calloutWidth = 320;
  static const double _calloutGap = 16;
  static const double _padding = 8;
  static const double _estimatedCalloutHeight = 244;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final padded = targetRect == null
            ? null
            : Rect.fromLTRB(
                targetRect!.left - _padding,
                targetRect!.top - _padding,
                targetRect!.right + _padding,
                targetRect!.bottom + _padding,
              );

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: CustomPaint(painter: _SpotlightPainter(rect: padded)),
              ),
            ),
            Positioned.fill(child: _calloutLayer(size, padded)),
          ],
        );
      },
    );
  }

  Widget _calloutLayer(Size screen, Rect? padded) {
    final isLast = stepIndex == stepCount - 1;
    final calloutWidth = _calloutWidth.clamp(0.0, screen.width - 24).toDouble();

    double calloutLeft;
    double calloutTop;
    if (padded == null) {
      calloutLeft = (screen.width - calloutWidth) / 2;
      calloutTop = (screen.height - _estimatedCalloutHeight) / 2;
    } else {
      final below = padded.bottom + _calloutGap;
      final above = padded.top - _calloutGap - _estimatedCalloutHeight;
      final hasRoomBelow =
          below + _estimatedCalloutHeight <= screen.height - 12;
      calloutTop =
          (hasRoomBelow
                  ? below
                  : above.clamp(
                      12.0,
                      screen.height - _estimatedCalloutHeight - 12,
                    ))
              .toDouble();
      calloutLeft = (padded.center.dx - calloutWidth / 2)
          .clamp(12.0, screen.width - calloutWidth - 12)
          .toDouble();
    }

    return Stack(
      children: [
        AnimatedPositioned(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          top: calloutTop,
          left: calloutLeft,
          width: calloutWidth,
          child: _CalloutCard(
            title: title,
            body: body,
            stepIndex: stepIndex,
            stepCount: stepCount,
            onNext: onNext,
            onBack: onBack,
            onSkip: onSkip,
            isLast: isLast,
          ),
        ),
      ],
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter({required this.rect});
  final Rect? rect;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = const Color(0xD917231C);
    if (rect == null) {
      canvas.drawRect(Offset.zero & size, dim);
      return;
    }
    final radius = const Radius.circular(12);
    final cutout = RRect.fromRectAndRadius(rect!, radius);
    final outer = Path()..addRect(Offset.zero & size);
    final hole = Path()..addRRect(cutout);
    final shape = Path.combine(PathOperation.difference, outer, hole);
    canvas.drawPath(shape, dim);

    final border = Paint()
      ..color = AppColors.pillGold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRRect(cutout, border);

    final innerBorder = Paint()
      ..color = Colors.white.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(cutout.deflate(3), innerBorder);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter old) => old.rect != rect;
}

class _CalloutCard extends StatelessWidget {
  const _CalloutCard({
    required this.title,
    required this.body,
    required this.stepIndex,
    required this.stepCount,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
    required this.isLast,
  });

  final String title;
  final String body;
  final int stepIndex;
  final int stepCount;
  final VoidCallback onNext;
  final VoidCallback? onBack;
  final VoidCallback onSkip;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: GameContainer(
        key: const Key('tutorial-callout-card'),
        padding: EdgeInsets.zero,
        frameColor: AppColors.accent,
        surfaceColor: AppColors.accent,
        borderRadius: 8,
        child: CustomPaint(
          painter: const ArcadeCheckerPainter(
            tileColor: Color(0x10FFFFFF),
            stripeColor: Color(0x18000000),
            drawBottomStripe: false,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    InfoBoardBadge(
                      label: 'STEP ${stepIndex + 1} / $stepCount',
                      fontSize: 10.5,
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: onSkip,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 7,
                        ),
                        child: Text(
                          'SKIP',
                          style: PixelText.title(
                            size: 11,
                            color: AppColors.parchment,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: PixelText.title(size: 22, color: AppColors.parchment),
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  style: PixelText.body(size: 14, color: AppColors.parchment),
                ),
                const SizedBox(height: 14),
                _ProgressDots(stepIndex: stepIndex, stepCount: stepCount),
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (onBack != null)
                      Expanded(
                        child: PillButton(
                          label: 'BACK',
                          variant: PillButtonVariant.accent,
                          fontSize: 12,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          onPressed: onBack,
                        ),
                      ),
                    if (onBack != null) const SizedBox(width: 10),
                    Expanded(
                      child: PillButton(
                        label: isLast ? 'DONE' : 'NEXT',
                        variant: PillButtonVariant.secondary,
                        fontSize: 12,
                        fullWidth: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        onPressed: onNext,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.stepIndex, required this.stepCount});

  final int stepIndex;
  final int stepCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < stepCount; i++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 5,
              decoration: BoxDecoration(
                color: i <= stepIndex
                    ? AppColors.pillGold
                    : AppColors.parchment.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          if (i < stepCount - 1) const SizedBox(width: 5),
        ],
      ],
    );
  }
}
