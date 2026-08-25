import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'app_avatar.dart';
import 'multiplier_chip.dart';
import '../styles.dart';
import '../utils/at_name.dart';
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
  final String? profilePhotoUrl;
  final VoidCallback? onProfileTap;

  /// The participant's current (stacked, global-event-inclusive) step
  /// multiplier from the backend. Nullable/absent on older backends → no badge
  /// (safe degradation). Semantics: >1 buffed ("Nx" badge), 1 neutral
  /// (nothing), 0 frozen (frost chip), <0 reversed (reversed chip).
  final double? currentMultiplier;

  /// Item 18 (batch 2026-08-08): the backend masks `placement` on a stealthed
  /// row, so there is no rank to show. The shield then paints "?" instead of a
  /// number — deriving one from the row's array position is exactly the
  /// "1 2 1 2" bug, where two stealthed rows showed 1 and 2 above visible rows
  /// also showing 1, 2, 3. Defaults false, so every existing caller is
  /// unchanged.
  final bool rankHidden;

  // Issue 1: team races render larger, more legible rows. These default to the
  // solo/ranked values so those layouts are UNCHANGED; the team-grouped
  // standings pass bumped sizes.
  final double avatarSize;
  final double nameSize;
  final double stepsSize;
  final double verticalPadding;

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
    this.profilePhotoUrl,
    this.onProfileTap,
    this.currentMultiplier,
    this.rankHidden = false,
    this.avatarSize = 32,
    this.nameSize = 15,
    this.stepsSize = 16,
    this.verticalPadding = 8,
  });

  /// What the shield paints. Exposed so a widget test can assert the masked
  /// rank without reaching into a CustomPainter's canvas.
  String get rankLabel => rankHidden ? '?' : '${rank + 1}';

  Color? _medalColor(BuildContext context) {
    // A masked row has no rank, so it must not wear a medal either — a gold
    // shield on a "?" would read as "the hidden runner is winning".
    if (rankHidden) return null;
    switch (rank) {
      case 0:
        return AppColors.of(context).medalGold;
      case 1:
        return AppColors.of(context).medalSilver;
      case 2:
        return AppColors.of(context).medalBronze;
      default:
        return null;
    }
  }

  Widget _buildAvatar(BuildContext context) {
    return AppAvatar(
      // The raw name, not displayName: the " (you)" suffix would turn the
      // fallback initials into "M(".
      name: isStealthed ? '???' : name,
      imageUrl: isStealthed ? null : profilePhotoUrl,
      size: avatarSize,
      isUser: isUser,
      isStealthed: isStealthed,
      borderColor: isUser ? AppColors.of(context).accent : Colors.white,
    );
  }

  /// The name-row chip reflecting the multiplier. Item 19 moved the body into
  /// the shared [MultiplierChip] so the team scoreboard renders the identical
  /// chip under the identical suppression rules; this stays as the plank's
  /// null-or-widget adapter.
  Widget? _multiplierChip(BuildContext context) {
    return MultiplierChip.maybe(
      currentMultiplier: currentMultiplier,
      isStealthed: isStealthed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final medalColor = _medalColor(context);
    final displayName = isStealthed ? '???' : (isUser ? '$name (you)' : name);
    final finishLabel = finishPlace == null
        ? 'FINISH'
        : '${formatOrdinal(finishPlace!)} FINISH';

    return Padding(
      padding: EdgeInsets.only(top: rank == 0 ? 0 : 4),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 10,
          vertical: verticalPadding,
        ),
        decoration: BoxDecoration(
          color: isFinished
              ? AppColors.of(context).coinLight.withValues(alpha: 0.14)
              : medalColor?.withValues(alpha: 0.08) ??
                    AppColors.of(context).parchmentDark.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isFinished
                ? AppColors.of(context).coinDark.withValues(alpha: 0.45)
                : medalColor?.withValues(alpha: 0.3) ??
                      AppColors.of(
                        context,
                      ).parchmentBorder.withValues(alpha: 0.3),
            width: 1,
          ),
          boxShadow: isFinished
              ? [
                  BoxShadow(
                    color: AppColors.of(
                      context,
                    ).coinDark.withValues(alpha: 0.18),
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
                  label: rankLabel,
                  color: medalColor ?? AppColors.of(context).woodMid,
                  // Item 13: a CustomPainter has no BuildContext, so the
                  // fallback border colour has to be resolved here and passed
                  // in — and compared in shouldRepaint — or the medal keeps its
                  // daytime edge through the 19:00 auto-night flip.
                  borderFallback: AppColors.of(context).woodShadow,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onProfileTap,
              child: _buildAvatar(context),
            ),
            const SizedBox(width: 8),
            // Name + horizontally swipeable status tray.
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onProfileTap,
                      child: Text(
                        atName(displayName),
                        style: PixelText.body(
                          size: nameSize,
                          color: isStealthed
                              ? AppColors.of(
                                  context,
                                ).textMid.withValues(alpha: 0.5)
                              : isUser
                              ? AppColors.of(context).textAccent
                              : AppColors.of(context).textDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  ...() {
                    final chip = _multiplierChip(context);
                    return chip == null
                        ? const <Widget>[]
                        : [const SizedBox(width: 6), chip];
                  }(),
                  if (effectIcons.isNotEmpty) ...[
                    const SizedBox(width: 5),
                    // Flexible so a full tray shrinks (it scrolls internally)
                    // instead of overflowing when a wide step count + a
                    // multiplier chip squeeze the middle on narrow phones.
                    for (final icon in effectIcons) Flexible(child: icon),
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
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppColors.of(context).roofLight,
                            AppColors.of(context).roofMid,
                            AppColors.of(context).roofDark,
                          ],
                        ),
                        border: Border.all(
                          color: AppColors.of(
                            context,
                          ).coinLight.withValues(alpha: 0.9),
                          width: 1.1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.of(
                              context,
                            ).coinDark.withValues(alpha: 0.45),
                            offset: const Offset(0, 2),
                            blurRadius: 0,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.flag_rounded,
                            size: 12,
                            color: AppColors.of(context).coinLight,
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
                size: stepsSize,
                color: isStealthed
                    ? AppColors.of(context).textMid.withValues(alpha: 0.5)
                    : AppColors.of(context).textMid,
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
  /// The glyph inside the shield — a 1-based rank, or "?" for a row whose
  /// placement the backend deliberately masked (item 18).
  final String label;
  final Color color;

  /// Theme-resolved stand-in for the old bare `AppColors.woodShadow`
  /// constant (item 13). Painters cannot read the palette themselves.
  final Color borderFallback;

  _MedalPainter({
    required this.label,
    required this.color,
    required this.borderFallback,
  });

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
          ? borderFallback
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
      oldDelegate.label != label ||
      oldDelegate.color != color ||
      oldDelegate.borderFallback != borderFallback;
}
