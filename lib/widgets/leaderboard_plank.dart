import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../styles.dart';
import '../utils/race_participant_display.dart';

/// A styled wooden plank for leaderboard rows with medal and depth.
class LeaderboardPlank extends StatelessWidget {
  final int rank;
  final String name;
  final int steps;
  final bool isUser;
  final bool isStealthed;
  final bool isFinished;
  final int? finishPlace;
  final String formattedSteps;
  final List<Widget> effectIcons;

  const LeaderboardPlank({
    super.key,
    required this.rank,
    required this.name,
    required this.steps,
    required this.formattedSteps,
    this.isUser = false,
    this.isStealthed = false,
    this.isFinished = false,
    this.finishPlace,
    this.effectIcons = const [],
  });

  Color? get _medalColor {
    switch (rank) {
      case 0:
        return AppColors.medalGold;
      case 1:
        return AppColors.medalSilver;
      case 2:
        return AppColors.medalBronze;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = isStealthed ? '???' : (isUser ? '$name (you)' : name);
    final finishLabel = finishPlace == null
        ? 'FINISH'
        : '${formatOrdinal(finishPlace!)} FINISH';

    return Padding(
      padding: EdgeInsets.only(top: rank == 0 ? 0 : 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isFinished
              ? AppColors.coinLight.withValues(alpha: 0.14)
              : _medalColor?.withValues(alpha: 0.08) ??
                    AppColors.parchmentDark.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isFinished
                ? AppColors.coinDark.withValues(alpha: 0.45)
                : _medalColor?.withValues(alpha: 0.3) ??
                      AppColors.parchmentBorder.withValues(alpha: 0.3),
            width: 1,
          ),
          boxShadow: isFinished
              ? [
                  BoxShadow(
                    color: AppColors.coinDark.withValues(alpha: 0.18),
                    offset: const Offset(0, 2),
                    blurRadius: 4,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            // Medal/rank badge
            SizedBox(
              width: 26,
              height: 30,
              child: CustomPaint(
                painter: _MedalPainter(
                  rank: rank,
                  color: _medalColor ?? AppColors.woodMid,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Name + effects
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      displayName,
                      style: PixelText.body(
                        size: 15,
                        color: isStealthed
                            ? AppColors.textMid.withValues(alpha: 0.5)
                            : isUser
                            ? AppColors.accent
                            : AppColors.textDark,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (effectIcons.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    ...effectIcons,
                  ],
                  if (isFinished && !isStealthed) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(7),
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppColors.roofLight,
                            AppColors.roofMid,
                            AppColors.roofDark,
                          ],
                        ),
                        border: Border.all(
                          color: AppColors.coinLight.withValues(alpha: 0.9),
                          width: 1.1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.coinDark.withValues(alpha: 0.45),
                            offset: const Offset(0, 2),
                            blurRadius: 0,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.flag_rounded,
                            size: 12,
                            color: AppColors.coinLight,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            finishLabel,
                            style: PixelText.title(
                              size: 9.5,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Step count
            Text(
              isStealthed ? '???' : formattedSteps,
              style: PixelText.number(
                size: 16,
                color: isStealthed
                    ? AppColors.textMid.withValues(alpha: 0.5)
                    : AppColors.textMid,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Draws a shield/medallion shape with the rank number inside.
class _MedalPainter extends CustomPainter {
  final int rank;
  final Color color;

  _MedalPainter({required this.rank, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Shield path
    final path = Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(w, h * 0.08)
      ..lineTo(w, h * 0.65)
      ..quadraticBezierTo(w, h * 0.85, w * 0.5, h)
      ..quadraticBezierTo(0, h * 0.85, 0, h * 0.65)
      ..lineTo(0, h * 0.08)
      ..close();

    // Fill
    final fillPaint = Paint()..color = color;
    canvas.drawPath(path, fillPaint);

    // Dark border
    final borderPaint = Paint()
      ..color = color.withValues(alpha: 0.6) == color
          ? AppColors.woodShadow
          : Color.lerp(color, Colors.black, 0.4)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(path, borderPaint);

    // Inner highlight
    final highlightPath = Path()
      ..moveTo(w * 0.5, h * 0.08)
      ..lineTo(w * 0.88, h * 0.14)
      ..lineTo(w * 0.88, h * 0.45)
      ..quadraticBezierTo(w * 0.88, h * 0.55, w * 0.5, h * 0.65)
      ..quadraticBezierTo(w * 0.12, h * 0.55, w * 0.12, h * 0.45)
      ..lineTo(w * 0.12, h * 0.14)
      ..close();
    final highlightPaint = Paint()..color = Colors.white.withValues(alpha: 0.2);
    canvas.drawPath(highlightPath, highlightPaint);

    // Rank text
    final labels = ['1', '2', '3'];
    final label = rank < 3 ? labels[rank] : '${rank + 1}';

    final paragraphBuilder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              textAlign: TextAlign.center,
              fontSize: h * 0.4,
              fontWeight: FontWeight.w900,
            ),
          )
          ..pushStyle(
            ui.TextStyle(
              color: Colors.white,
              fontSize: h * 0.4,
              fontWeight: FontWeight.w900,
              shadows: [
                const Shadow(
                  color: Color(0x80000000),
                  offset: Offset(1, 1),
                  blurRadius: 0,
                ),
              ],
            ),
          )
          ..addText(label);

    final paragraph = paragraphBuilder.build()
      ..layout(ui.ParagraphConstraints(width: w));

    canvas.drawParagraph(
      paragraph,
      Offset(0, (h - paragraph.height) / 2 - h * 0.02),
    );
  }

  @override
  bool shouldRepaint(covariant _MedalPainter oldDelegate) =>
      oldDelegate.rank != rank || oldDelegate.color != color;
}
